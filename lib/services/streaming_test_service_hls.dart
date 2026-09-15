import 'dart:async';
import 'dart:convert';

import 'package:logger/logger.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../constants/config.dart';
import 'streaming_shared.dart';
import 'streaming_test_service.dart';
import 'traffic_stats_service.dart';

/// Détail d'un niveau annoncé par le manifeste HLS/DASH.
class StreamLevel {
  final int index;
  final int height;
  final int bitrate;

  const StreamLevel(
      {required this.index, required this.height, required this.bitrate});
}

/// Sélectionne, dans les niveaux du manifeste, celui qui correspond au palier
/// [targetHeight]. Retourne null si le manifeste ne propose rien.
///
/// Le service ne « simule » jamais une mesure : si le 2160p n'existe pas dans
/// l'échelle, le palier reste non servi — même convention d'honnêteté que le
/// backend YouTube (colonne « — »).
StreamLevel? matchLevelForHeight(List<StreamLevel> levels, int targetHeight) {
  StreamLevel? best;
  for (final l in levels) {
    if (l.height == targetHeight) return l;
    if (best == null ||
        (l.height - targetHeight).abs() < (best.height - targetHeight).abs()) {
      best = l;
    }
  }
  return best;
}

/// Mesures brutes d'un palier, avant d'être rangées dans le tableau.
class _LevelMeasurement {
  final bool played; // la lecture a démarré
  final double performanceRate;
  final double initialLoadingSec;
  final double bufferingSec;
  final int rebufferCount;
  final int dataUsedKiB;

  const _LevelMeasurement({
    required this.played,
    this.performanceRate = 0,
    this.initialLoadingSec = 0,
    this.bufferingSec = 0,
    this.rebufferCount = 0,
    this.dataUsedKiB = -1,
  });

  static const notPlayed = _LevelMeasurement(played: false);
}

/// Test de streaming **HLS/DASH** avec qualité verrouillée.
///
/// Différence fondamentale avec [StreamingTestService] (YouTube) : ici la
/// bibliothèque de lecture (hls.js, ou dash.js pour un manifeste `.mpd`)
/// expose l'échelle de qualité **avant** la lecture et obéit à un verrou
/// explicite — la qualité demandée est un fait, pas une suggestion. Chaque
/// palier est donc mesuré à la qualité exacte demandée : `servedLabel` reste
/// vide et le flag « qualité modifiée en cours de lecture » n'a plus lieu
/// d'être.
///
/// Réutilise à l'identique le reste de la chaîne de mesure : hébergement local
/// de la page ([PlayerHost]), contrôleur WebView
/// ([buildStreamingWebViewController]), compteurs de trafic
/// ([TrafficStatsService]), agrégation et score
/// ([aggregateStreamingResults]). La sortie ([StreamingTestResult]) est la
/// même que celle du backend YouTube : rien ne change ni dans l'historique ni
/// dans le tableau de résultats.
///
/// Choisir le backend : [streamingBackend] (drapeau dans
/// `constants/config.dart`) — 'hls' pour ce moteur, 'youtube' pour l'ancien ;
/// le drapeau existe pour le test A/B, basculer ensuite la constante.
class StreamingTestServiceHls {
  final logger = Logger();
  final TrafficStatsService _traffic = TrafficStatsService();

  Completer<void>? _ready; // bibliothèque chargée, manifeste parsé
  Completer<void>? _started; // première image du palier courant
  Completer<Map<String, dynamic>>? _level; // bilan du palier courant

  /// Niveaux du manifeste, connus dès le chargement (contrairement à
  /// l'IFrame API de YouTube, qui ne révèle l'échelle qu'en lisant).
  List<StreamLevel> _manifestLevels = const [];

  String? _playerError;

  Future<StreamingTestResult> runTest({
    StreamingControllerCallback? onController,
    StreamingProgressCallback? onProgress,
    StreamingRowsCallback? onRows,
  }) async {
    final levels = STREAMING_QUALITY_LEVELS;
    final rows = <StreamingQualityResult>[
      for (final label in levels.values)
        StreamingQualityResult.unavailable(label),
    ];
    onRows?.call(List.of(rows));

    final controller = buildStreamingWebViewController(onMessage: _onJsMessage);
    final host = PlayerHost();

    try {
      onProgress?.call(0.02, 'Préparation du lecteur…');
      // Le gabarit HLS n'a pas besoin de l'origine (pas d'IFrame API à
      // valider) ; le serveur local reste utile pour un contexte HTTP propre.
      await controller.loadRequest(await host.start((_) => playerHtml()));
      onController?.call(controller);

      _ready = Completer<void>();
      try {
        await _ready!.future.timeout(const Duration(seconds: 25));
      } on TimeoutException {
        logger.w('Streaming HLS: manifeste non chargé ($streamTestStreamUrl)');
        return aggregateStreamingResults(rows,
            error: 'Flux de test injoignable. Vérifiez la connexion Internet, '
                'puis relancez le test.');
      }
      if (_playerError != null) {
        return aggregateStreamingResults(rows, error: _playerError);
      }
      if (_manifestLevels.isEmpty) {
        return aggregateStreamingResults(rows,
            error: 'Le flux de test n\'expose aucune qualité exploitable.');
      }

      for (int i = 0; i < levels.length; i++) {
        final label = levels.values.elementAt(i);
        final target = int.tryParse(label.replaceAll('p', '')) ?? 0;
        final level = matchLevelForHeight(_manifestLevels, target);
        if (level == null) {
          logger.i('Streaming HLS: $label absente du manifeste, ignorée');
          continue;
        }

        onProgress?.call((i + 0.1) / levels.length, 'Chargement en $label…');
        final m = await _measureLevel(
          controller: controller,
          level: level,
          label: label,
          onProgress: (frac, msg) =>
              onProgress?.call((i + frac) / levels.length, msg),
        );
        if (!m.played) continue;

        // Qualité verrouillée : le palier servi EST le palier demandé.
        rows[i] = StreamingQualityResult(
          label: label,
          reached: true,
          performanceRate: m.performanceRate,
          initialLoadingSec: m.initialLoadingSec,
          bufferingSec: m.bufferingSec,
          rebufferCount: m.rebufferCount,
          dataUsedKiB: m.dataUsedKiB,
        );
        onRows?.call(List.of(rows));
      }
    } catch (e) {
      logger.e('Streaming HLS: test interrompu ($e)');
    } finally {
      // Libère la référence côté UI avant de couper la lecture.
      onController?.call(null);
      try {
        await controller.runJavaScript('stopLevel()');
      } catch (_) {
        // Le lecteur n'a jamais démarré : rien à arrêter.
      }
      await host.stop();
    }

    return aggregateStreamingResults(rows);
  }

  /// Joue le niveau [level] pendant [STREAMING_LEVEL_DURATION_SEC] et en
  /// mesure les quatre indicateurs.
  Future<_LevelMeasurement> _measureLevel({
    required WebViewController controller,
    required StreamLevel level,
    required String label,
    required StreamingProgressCallback onProgress,
  }) async {
    final rxBefore = await _traffic.rxBytes();

    _started = Completer<void>();
    _level = Completer<Map<String, dynamic>>();

    final wall = Stopwatch()..start();
    await controller.runJavaScript('startLevel(${level.index})');

    // Attente de la première image.
    try {
      await _started!.future
          .timeout(const Duration(seconds: STREAMING_LEVEL_TIMEOUT_SEC));
    } on TimeoutException {
      logger.w("Streaming HLS: $label n'a jamais démarré");
      await _stopLevel(controller);
      return _LevelMeasurement.notPlayed;
    }

    // Lecture mesurée.
    const durationMs = STREAMING_LEVEL_DURATION_SEC * 1000;
    final playStart = wall.elapsedMilliseconds;
    while (wall.elapsedMilliseconds - playStart < durationMs) {
      await Future.delayed(const Duration(milliseconds: 250));
      final frac =
          0.1 + 0.85 * (wall.elapsedMilliseconds - playStart) / durationMs;
      onProgress(frac.clamp(0.0, 0.95), 'Lecture en $label…');
    }

    final report = await _stopLevel(controller);
    wall.stop();
    final rxAfter = await _traffic.rxBytes();

    final initialSec = ((report['startupMs'] as num?)?.toDouble() ?? 0) / 1000;
    final bufferingSec = ((report['bufferMs'] as num?)?.toDouble() ?? 0) / 1000;
    final totalSec = wall.elapsedMilliseconds / 1000;
    final watchedSec =
        (totalSec - initialSec - bufferingSec).clamp(0.0, totalSec);
    final performance = totalSec > 0 ? watchedSec / totalSec * 100 : 0.0;

    return _LevelMeasurement(
      played: true,
      performanceRate: double.parse(performance.toStringAsFixed(2)),
      initialLoadingSec: double.parse(initialSec.toStringAsFixed(3)),
      bufferingSec: double.parse(bufferingSec.toStringAsFixed(3)),
      rebufferCount: (report['rebuffers'] as num?)?.toInt() ?? 0,
      dataUsedKiB: TrafficStatsService.kibBetween(rxBefore, rxAfter),
    );
  }

  /// Met la lecture en pause et récupère le bilan du palier.
  Future<Map<String, dynamic>> _stopLevel(WebViewController controller) async {
    try {
      await controller.runJavaScript('stopLevel()');
      return await _level!.future.timeout(const Duration(seconds: 5));
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  void _onJsMessage(JavaScriptMessage message) {
    Map<String, dynamic> event;
    try {
      event = Map<String, dynamic>.from(jsonDecode(message.message) as Map);
    } catch (_) {
      return;
    }

    switch (event['e']) {
      case 'ready':
        // Le manifeste est parsé : l'échelle réelle est connue.
        final raw = event['levels'];
        if (raw is List) {
          _manifestLevels = raw
              .whereType<Map>()
              .map((j) => StreamLevel(
                    index: (j['index'] as num?)?.toInt() ?? 0,
                    height: (j['height'] as num?)?.toInt() ?? 0,
                    bitrate: (j['bitrate'] as num?)?.toInt() ?? 0,
                  ))
              .toList();
        }
        if (_ready?.isCompleted == false) _ready!.complete();
        break;
      case 'start':
        if (_started?.isCompleted == false) _started!.complete();
        break;
      case 'level':
        if (_level?.isCompleted == false) _level!.complete(event);
        break;
      case 'jserror':
        // Erreur JavaScript dans la page hôte : sans elle, un échec de
        // chargement de la bibliothèque ressemblerait à un simple timeout.
        _playerError ??= 'Erreur du lecteur : ${event['msg']}';
        logger.w('Streaming HLS: erreur JS — ${event['msg']}');
        if (_ready?.isCompleted == false) _ready!.complete();
        break;
    }
  }

  /// Page hôte : charge hls.js ou dash.js depuis jsDelivr selon l'extension du
  /// flux, crée le lecteur MSE et verrouille la qualité par palier.
  ///
  /// La qualité est verrouillée via `hls.currentLevel` (hls.js, ABR coupé) ou
  /// en bornant l'ABR dash.js au seul niveau voulu : l'adaptatif ne décide
  /// plus rien, c'est toute la différence avec YouTube.
  ///
  /// Public pour tests de contrat : [streaming_hls_service_test] gèle les
  /// invariants de mesure (reset d'état par palier, chargement des segments
  /// piloté par palier, buffering d'amorçage hors interruptions) — c'est leur
  /// violation qui a fait ne servir que le 720p en terrain.
  String playerHtml() => '''
<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1, user-scalable=no">
<style>
  html,body{margin:0;padding:0;background:#000;overflow:hidden;height:100%}
  video{width:100%;height:100%;object-fit:contain}
</style>
</head>
<body>
<video id="video" muted playsinline autoplay></video>
<script>
var video = null, engine = null, engineKind = '';
// État du palier courant. Remis à zéro à CHAQUE startLevel() : c'est la
// convention du backend YouTube (un lecteur neuf par palier) transposée ici —
// sans reset, 'start' ne part qu'au premier palier et les suivants timeout.
var t0 = 0, startupMs = -1, bufferMs = 0, bufferStart = 0, rebuffers = 0;
var started = false, wantedLevel = -1;

function resetTierState() {
  t0 = Date.now();
  startupMs = -1; bufferMs = 0; bufferStart = 0; rebuffers = 0;
  started = false;
}

function send(o) { YeleStream.postMessage(JSON.stringify(o)); }

window.onerror = function (msg) { send({ e: 'jserror', msg: String(msg) }); };

// Chronométrie : mêmes conventions que le backend YouTube. Le buffering
// d'amorçage fait partie du « chargement initial », pas des interruptions :
// on ne compte que ce qui survient après la 1re image.
function onPlaying() {
  // Première image DU PALIER : 'start' part à chaque palier (le backend
  // YouTube envoie pareil pour chaque lecteur neuf).
  if (!started) {
    startupMs = Date.now() - t0;
    started = true;
    send({ e: 'start', startupMs: startupMs });
  }
  if (bufferStart > 0) { bufferMs += Date.now() - bufferStart; bufferStart = 0; }
}
function onStall() {
  // Le buffering d'amorçage (stall avant la 1re image) fait partie du
  // « chargement initial » — c'est déjà dans startupMs. On ne compte comme
  // interruption que les stalls APRÈS la 1re image : conventions YouTube.
  if (started && bufferStart === 0) { bufferStart = Date.now(); rebuffers++; }
}

function attach() {
  video = document.getElementById('video');
  video.addEventListener('playing', onPlaying);
  video.addEventListener('waiting', onStall);
  video.addEventListener('stalled', onStall);
}

// Verrouille le niveau hls.js : currentLevel AVANT startLoad (le premier
// fragment demandé est déjà le niveau verrouillé), puis startLoad explicite —
// avec autoStartLoad:false, AUCUN octet ne circule entre les paliers : le
// trafic mesuré (rxBefore/rxAfter côté Dart) appartient au seul palier courant.
// Le rattrapage LEVEL_SWITCHED (enregistré une seule fois, cf. onLibReady)
// repose le verrou si le CDN déclassait un segment.
function startHls(levelIndex) {
  resetTierState();
  wantedLevel = levelIndex;
  engine.currentLevel = levelIndex;
  engine.nextLevel = levelIndex;
  engine.startLoad();
  video.play().catch(function () {});
}

// Verrouille le niveau dash.js : pas d'API « joue l'index i » — l'usage
// documenté est de couper les règles ABR par défaut et de borner le choix au
// niveau voulu.
function startDash(levelIndex) {
  resetTierState();
  wantedLevel = levelIndex;
  engine.updateSettings({
    streaming: { abr: {
      useDefaultABRRules: false,
      ABRStrategy: 'abrBola',
      bitrateRules: { useDefaultABRRules: false }
    }}
  });
  try { engine.setQualityFor('video', levelIndex, true); } catch (e) {}
  try { engine.updateData(); } catch (e) {}
  t0 = Date.now();
  video.play().catch(function () {});
}

function startLevel(index) {
  if (engineKind === 'dash') startDash(index); else startHls(index);
}

function stopLevel() {
  if (!video) { send({ e: 'level', startupMs: 0, bufferMs: 0, rebuffers: 0 }); return; }
  if (bufferStart > 0) { bufferMs += Date.now() - bufferStart; bufferStart = 0; }
  try { video.pause(); } catch (e) {}
  // Coupe le chargement des segments : sans ça, hls.js continuerait à
  // précharger pendant la fenêtre de trafic du palier suivant.
  if (engineKind === 'hls' && engine && engine.stopLoad) {
    try { engine.stopLoad(); } catch (e) {}
  }
  send({
    e: 'level',
    startupMs: startupMs < 0 ? 0 : startupMs,
    bufferMs: bufferMs,
    rebuffers: rebuffers
  });
}

var isDash = '$streamTestStreamUrl'.split('?')[0].endsWith('.mpd');

// Remonte l'échelle de qualité à Dart dès le chargement du manifeste :
// l'IFrame API de YouTube ne le permettait qu'après la première lecture.
function report() {
  var levels = [];
  if (engineKind === 'dash') {
    var list = [];
    try { list = engine.getBitrateInfoListFor('video') || []; } catch (e) {}
    for (var i = 0; i < list.length; i++) {
      levels.push({ index: list[i].qualityIndex, height: (list[i].height || 0),
                    bitrate: list[i].bitrate || 0 });
    }
  } else {
    for (var i = 0; i < engine.levels.length; i++) {
      levels.push({ index: i, height: (engine.levels[i].height || 0),
                    bitrate: engine.levels[i].bitrate || 0 });
    }
  }
  send({ e: 'ready', engine: engineKind, levels: levels });
}

function onLibReady() {
  attach();
  if (isDash) {
    engineKind = 'dash';
    engine = dashjs.MediaPlayer().create();
    engine.initialize(video, '$streamTestStreamUrl', false);
    engine.on(dashjs.MediaPlayer.events.STREAM_INITIALIZED, report);
  } else {
    engineKind = 'hls';
    // autoStartLoad:false : le chargement des segments n'est déclenché que
    // par startLoad() dans startHls — condition d'une mesure de trafic par
    // palier (sinon hls.js précharge tout dès le manifeste parsé).
    engine = new Hls({ capLevelToPlayerSize: false, startLevel: -1,
                       autoStartLoad: false });
    engine.loadSource('$streamTestStreamUrl');
    engine.attachMedia(video);
    engine.on(Hls.Events.MANIFEST_PARSED, report);
    // Rattrapage du verrou : UN SEUL listener, qui applique le niveau du
    // palier courant (l'ancien code en enregistrait un par palier — ils se
    // battaient entre eux dès le deuxième palier).
    engine.on(Hls.Events.LEVEL_SWITCHED, function (e, d) {
      if (wantedLevel >= 0 && d.level !== wantedLevel) {
        engine.currentLevel = wantedLevel;
      }
    });
  }
}

function loadLib() {
  var s = document.createElement('script');
  if (isDash) {
    s.src = 'https://cdn.jsdelivr.net/npm/dashjs@4.7.4/dist/dash.all.min.js';
  } else {
    s.src = 'https://cdn.jsdelivr.net/npm/hls.js@1.5.20/dist/hls.min.js';
  }
  s.onload = onLibReady;
  s.onerror = function () {
    send({ e: 'jserror', msg: 'CDN hls.js/dash.js injoignable' });
  };
  document.head.appendChild(s);
}

loadLib();
</script>
</body>
</html>
''';
}
