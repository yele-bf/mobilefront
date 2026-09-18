import 'dart:async';
import 'dart:convert';

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
  final TrafficStatsService _traffic = TrafficStatsService();

  /// Vrai si le flux configuré est un manifeste HLS lu par hls.js. Le débit
  /// minimal requis n'a de sens QUE pour ce moteur : les fragments du
  /// manifeste sont connus d'avance (taille × durée) et le palier est
  /// verrouillé. Un flux DASH (.mpd) joué par dash.js est exclu — la forme
  /// des fragments (segments complets, pas d'init séparée en l'état) rend
  /// l'estimation fallacieuse.
  late final bool hlsEngine = streamTestStreamUrl
      .toLowerCase()
      .split('?')
      .first
      .endsWith('.m3u8');

  /// Débit mini requis par palier, rempli par [runTest] (label → kb/s).
  /// Sert au journal de diagnostic (logcat) ; l'affichage utilisateur le
  /// recalcule côté tableau à partir de la config (mêmes constantes).
  final Map<String, int> minRequiredKbps = {};

  /// Journal lisible dans logcat sous le tag [YELE-DIAG-HLS] : même convention
  /// print-based que les autres services ([YELE-DIAG-LOC], [YELE-DIAG-UI]…)
  /// pour que les captures terrain (`adb logcat | grep YELE-DIAG`) contiennent
  /// toute la chaîne de décision du moteur HLS — sans elle, un palier non
  /// servi est indiscernable d'un palier jamais tenté.
  void _log(String msg) => print('[YELE-DIAG-HLS] $msg');
  void _logErr(String msg) => print('[YELE-DIAG-HLS-ERR] $msg');

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

    // BANDWIDTH annoncée par le manifeste pour chaque palier (bit/s),
    // retrouvée via la correspondance clé lecteur YouTube → libellé affiché.
    final bandwidthBps = <String, int>{};
    for (final e in STREAMING_LEVEL_BANDWIDTH_BPS.entries) {
      final mapped = levels[e.key];
      if (mapped != null) bandwidthBps[mapped] = e.value;
    }

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
        _logErr('manifeste non chargé en 25 s ($streamTestStreamUrl) — '
            'AUCUN palier ne sera mesuré');
        return aggregateStreamingResults(rows,
            engine: 'hls',
            error: 'Flux de test injoignable. Vérifiez la connexion Internet, '
                'puis relancez le test.');
      }
      if (_playerError != null) {
        return aggregateStreamingResults(rows, engine: 'hls', error: _playerError);
      }
      if (_manifestLevels.isEmpty) {
        _logErr('manifeste parsé mais aucun niveau exploitable');
        return aggregateStreamingResults(rows,
            engine: 'hls',
            error: 'Le flux de test n\'expose aucune qualité exploitable.');
      }
      _log('manifeste : ${_manifestLevels.length} niveau(x) — '
          '${_manifestLevels.map((l) => '#${l.index} ${l.height}p '
              '@${(l.bitrate / 1e6).toStringAsFixed(1)} Mb/s').join(', ')}');
      // Débit minimal requis par palier : taille du premier fragment (4 s)
      // rapportée au timeout de démarrage — le réseau doit tenir ce débit
      // DÈS LA PREMIÈRE SECONDE, sinon le palier expire avant d'afficher une
      // image. C'est l'explication d'une colonne restée vide.
      if (hlsEngine) {
        for (final entry in bandwidthBps.entries) {
          minRequiredKbps[entry.key] = minRequiredKbpsFor(entry.value);
        }
        _log('débit mini requis (frag 4 s ÷ timeout '
            '$STREAMING_LEVEL_TIMEOUT_SEC s × marge $hlsMinBandwidthMargin) : '
            '${minRequiredKbps.entries.map((e) => '${e.key} ≥ '
                '${(e.value / 1e3).toStringAsFixed(2)} Mb/s').join(', ')}');
      }

      for (int i = 0; i < levels.length; i++) {
        final label = levels.values.elementAt(i);
        final target = int.tryParse(label.replaceAll('p', '')) ?? 0;
        final level = matchLevelForHeight(_manifestLevels, target);
        if (level == null) {
          _log('palier $label : ABSENT du manifeste, ignoré'
              '${hlsEngine && minRequiredKbps[label] != null ? ' — débit mini '
                  'requis était ${(minRequiredKbps[label]! / 1e3).toStringAsFixed(2)} '
                  'Mb/s' : ''}');
          continue;
        }
        _log('palier $label : niveau #${level.index} (${level.height}p) '
            'sélectionné');

        onProgress?.call((i + 0.1) / levels.length, 'Chargement en $label…');
        final m = await _measureLevel(
          controller: controller,
          level: level,
          label: label,
          demandedBps: bandwidthBps[label],
          manifestLevels: _manifestLevels,
          onProgress: (frac, msg) =>
              onProgress?.call((i + frac) / levels.length, msg),
        );
        if (!m.played) {
          _logErr('palier $label NON DÉMARRÉ (timeout '
              '$STREAMING_LEVEL_TIMEOUT_SEC s) — restera non servi'
              '${hlsEngine && minRequiredKbps[label] != null ? ' — débit mini '
                  'requis : ${(minRequiredKbps[label]! / 1e3).toStringAsFixed(2)} '
                  'Mb/s' : ''}');
          continue;
        }

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
      _logErr('test interrompu ($e) — paliers restants non servis');
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

    final result = aggregateStreamingResults(rows, engine: 'hls');
    final served = rows.where((r) => r.reached).map((r) => r.label).toList();
    _log('bilan : ${served.isEmpty ? 'AUCUN palier servi' : 'paliers servis ${served.join(', ')}'}'
        ' — score ${result.score}, résolution max ${result.maxResolution}, '
        'trafic total ${result.totalDataKiB >= 0 ? '${result.totalDataKiB} KiB' : 'non mesurable'}');
    if (result.error != null) {
      _logErr("motif remonté à l'écran : ${result.error}");
    }
    return result;
  }

  /// Joue le niveau [level] pendant [STREAMING_LEVEL_DURATION_SEC] et en
  /// mesure les quatre indicateurs.
  ///
  /// [demandedBps] : BANDWIDTH annoncée du palier demandé (bit/s), pour
  /// estimer le débit que le réseau a dû tenir (requête de calibration du
  /// manifeste exclue). [manifestLevels] : échelle du manifeste, pour localiser
  /// le fragment réellement servi quand le CDN déclassait la demande.
  Future<_LevelMeasurement> _measureLevel({
    required WebViewController controller,
    required StreamLevel level,
    required String label,
    required StreamingProgressCallback onProgress,
    int? demandedBps,
    List<StreamLevel> manifestLevels = const [],
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
      _logErr("[$label] aucune première image en $STREAMING_LEVEL_TIMEOUT_SEC s");
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
    final trafficKiB = TrafficStatsService.kibBetween(rxBefore, rxAfter);

    // Bilan vide = stopLevel n'a jamais reçu l'événement 'level' du pont JS :
    // la mesure part alors à zéro alors que la lecture a eu lieu. Distinguer
    // ce cas d'un vrai zéro est ce qui rend les données par palier crédibles.
    if (report.isEmpty) {
      _logErr('[$label] bilan du lecteur non reçu (pas d\'événement "level") '
          '— indicateurs à 0, trafic seul fiable');
    }
    _log('[$label] démarrage ${initialSec.toStringAsFixed(3)} s — buffer '
        '${bufferingSec.toStringAsFixed(3)} s — interruptions '
        '${report['rebuffers'] ?? '?'} — trafic '
        '${trafficKiB >= 0 ? '$trafficKiB KiB' : 'non mesurable'} — '
        'performance ${performance.toStringAsFixed(1)} %');
    if (demandedBps != null) {
      // Débit réel = octets mesurés / temps de téléchargement (dont le
      // démarrage) ; débit requis = fragmentation du palier DEMANDÉ. Le
      // palier servi peut différer (déclassement CDN) : on le note, sans
      // requalifier la mesure.
      final downloadSec = totalSec > 0 ? totalSec : 1;
      final actualKbps = trafficKiB >= 0
          ? (trafficKiB * 1024 * 8 / downloadSec / 1e3).round()
          : -1;
      final servedBps = matchLevelForHeight(manifestLevels, level.height)?.bitrate;
      _log('[$label] débit requis ≈ '
          '${(minRequiredKbpsFor(demandedBps) / 1e3).toStringAsFixed(2)} Mb/s '
          '(mini) · ${(demandedBps / 1e6).toStringAsFixed(2)} Mb/s '
          '(BANDWIDTH${servedBps != null && servedBps != demandedBps ? ', '
              'servi ${(servedBps / 1e6).toStringAsFixed(2)}' : ''}) — '
          'débit réel ${actualKbps >= 0 ? '${(actualKbps / 1e3).toStringAsFixed(2)} Mb/s' : 'n/m'}');
    }

    return _LevelMeasurement(
      played: true,
      performanceRate: double.parse(performance.toStringAsFixed(2)),
      initialLoadingSec: double.parse(initialSec.toStringAsFixed(3)),
      bufferingSec: double.parse(bufferingSec.toStringAsFixed(3)),
      rebufferCount: (report['rebuffers'] as num?)?.toInt() ?? 0,
      dataUsedKiB: trafficKiB,
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
        _log('moteur ${event['engine'] ?? '?'} — manifeste parsé, '
            '${(event['levels'] as List?)?.length ?? 0} niveau(x) annoncés');
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
        _log('première image (palier en cours) : startup=${event['startupMs']} ms');
        if (_started?.isCompleted == false) _started!.complete();
        break;
      case 'level':
        _log("bilan JS du palier : startup=${event['startupMs']} ms, "
            'buffer=${event['bufferMs']} ms, rebuffers=${event['rebuffers']}');
        if (_level?.isCompleted == false) _level!.complete(event);
        break;
      case 'audio':
        // Lecture muette malgré le unmute : politique autoplay de la WebView
        // (rejet de play() puis repli silencieux). Sans cette ligne, le
        // terrain ne peut pas distinguer un muet imposé d'un défaut de piste.
        if (event['muted'] == true) {
          _logErr('lecture MUETTE malgré le unmute — son non audible sur ce '
              'palier (politique autoplay de la WebView ?)');
        } else {
          _log('son autorisé côté page (non mueté) — si le terrain n\'entend '
              'rien malgré ce log, vérifier le volume multimédia du téléphone '
              '(invisible depuis la page)');
        }
        break;
      case 'jserror':
        // Erreur JavaScript dans la page hôte : sans elle, un échec de
        // chargement de la bibliothèque ressemblerait à un simple timeout.
        _playerError ??= 'Erreur du lecteur : ${event['msg']}';
        _logErr('erreur JS de la page lecteur — ${event['msg']}');
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
  /// invariants de mesure (moteur recréé à froid par palier, reset d'état par
  /// palier, chargement des segments piloté par palier, buffering d'amorçage
  /// hors interruptions) — c'est leur violation qui a fait ne servir que le
  /// 720p en terrain, puis mesurer des reprises au lieu de démarrages à froid.
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
<video id="video" playsinline autoplay></video>
<script>
var video = null, engine = null, engineKind = '';
// État du palier courant. Remis à zéro à CHAQUE startLevel() : c'est la
// convention du backend YouTube (un lecteur neuf par palier) transposée ici —
// sans reset, 'start' ne part qu'au premier palier et les suivants timeout.
var t0 = 0, startupMs = -1, bufferMs = 0, bufferStart = 0, rebuffers = 0;
var started = false, wantedLevel = -1, audioReported = false, unmuteArmed = false;

function resetTierState() {
  t0 = Date.now();
  startupMs = -1; bufferMs = 0; bufferStart = 0; rebuffers = 0;
  started = false; audioReported = false; unmuteArmed = false;
}

function send(o) { YeleStream.postMessage(JSON.stringify(o)); }

// État audio du palier, remonté UNE seule fois (compteur remis à chaque
// palier) : sans ce signal, un « pas de son » en terrain est indiscernable
// d'un muet imposé malgré le unmute. muted:false = son autorisé côté page
// (le volume multimédia du téléphone reste invisible depuis le JS),
// muted:true = lecture muette.
function reportAudio() {
  if (audioReported) return;
  audioReported = true;
  send({ e: 'audio', muted: video.muted === true });
}

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
  reportAudio();
}
function onStall() {
  // Le buffering d'amorçage (stall avant la 1re image) fait partie du
  // « chargement initial » — c'est déjà dans startupMs. On ne compte comme
  // interruption que les stalls APRÈS la 1re image : conventions YouTube.
  if (started && bufferStart === 0) { bufferStart = Date.now(); rebuffers++; }
}

// Démutage ARMÉ : un moteur neuf n'a encore aucune donnée au moment de
// startLevel — un play() immédiat serait rejeté et déclencherait le repli
// muet (fausse alerte « MUETTE », palier lu sans son). Le démutage part donc
// à canplay, quand le premier fragment du palier est décodable.
function onCanPlay() {
  if (unmuteArmed) { unmuteArmed = false; unmute(); }
}

function attach() {
  video = document.getElementById('video');
  video.addEventListener('playing', onPlaying);
  video.addEventListener('waiting', onStall);
  video.addEventListener('stalled', onStall);
  video.addEventListener('canplay', onCanPlay);
}

// Rend le lecteur audible : la WebView est déjà autorisée à jouer avec le son
// (setMediaPlaybackRequiresUserGesture(false) côté Android,
// mediaTypesRequiringUserAction vide côté iOS) mais elle coupe le son d'une
// lecture automatique sans geste — d'où des vidéos affichées sans audio.
// Appelé à canplay de chaque palier (moteur neuf) ; en cas de refus du
// système, on retombe silencieusement en muet pour ne pas bloquer la mesure.
function unmute() {
  video.muted = false;
  var p = video.play();
  if (p && p.catch) p.catch(function () { video.muted = true; reportAudio(); video.play().catch(function () {}); });
}

// Détruit le moteur courant : buffers MSE relâchés, listeners supprimés.
// Sans destruction, le moteur suivant hériterait de l'estimation de bande
// passante et des buffers du palier précédent — la contamination inter-paliers
// que le backend YouTube élimine en détruisant son lecteur (buildLevel).
function destroyEngine() {
  if (!engine) return;
  if (engineKind === 'hls') {
    try { engine.stopLoad(); } catch (e) {}
    try { engine.destroy(); } catch (e) {}
  } else {
    try { engine.reset(); } catch (e) {}
  }
  engine = null;
}

// Verrouille le niveau hls.js avec un moteur NEUF par palier — convention du
// backend YouTube (« un lecteur neuf par qualité », cf. buildLevel) : le
// startupMs de chaque palier mesure un vrai démarrage à froid, à périmètre
// égal entre les deux moteurs. Le verrou est appliqué dans MANIFEST_PARSED :
// le niveau est forcé AVANT startLoad, donc le premier fragment demandé est
// déjà au niveau verrouillé ; avec autoStartLoad:false, AUCUN octet ne circule
// avant ce verrou ni entre les paliers : le trafic mesuré (rxBefore/rxAfter
// côté Dart) appartient au seul palier courant. Le rattrapage LEVEL_SWITCHED
// repose le verrou si le CDN déclassait un segment.
function startHls(levelIndex) {
  resetTierState();
  destroyEngine();
  engine = new Hls({ capLevelToPlayerSize: false, startLevel: -1,
                      autoStartLoad: false });
  engine.on(Hls.Events.MANIFEST_PARSED, function () {
    report();
    engine.currentLevel = wantedLevel;
    engine.nextLevel = wantedLevel;
    engine.startLoad();
  });
  engine.on(Hls.Events.LEVEL_SWITCHED, function (e, d) {
    if (wantedLevel >= 0 && d.level !== wantedLevel) {
      engine.currentLevel = wantedLevel;
    }
  });
  wantedLevel = levelIndex;
  unmuteArmed = true;
  engine.loadSource('$streamTestStreamUrl');
  engine.attachMedia(video);
}

// Verrouille le niveau dash.js : pas d'API « joue l'index i » — l'usage
// documenté est de couper les règles ABR par défaut et de borner le choix au
// niveau voulu. Même principe qu'en HLS : moteur recréé à froid par palier.
function startDash(levelIndex) {
  resetTierState();
  destroyEngine();
  engine = dashjs.MediaPlayer().create();
  engine.initialize(video, '$streamTestStreamUrl', false);
  engine.on(dashjs.MediaPlayer.events.STREAM_INITIALIZED, report);
  engine.updateSettings({
    streaming: { abr: {
      useDefaultABRRules: false,
      ABRStrategy: 'abrBola',
      bitrateRules: { useDefaultABRRules: false }
    }}
  });
  try { engine.setQualityFor('video', levelIndex, true); } catch (e) {}
  try { engine.updateData(); } catch (e) {}
  wantedLevel = levelIndex;
  unmuteArmed = true;
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
    // Moteur de DÉCOUVERTE : il ne sert qu'à parser le manifeste et remonter
    // l'échelle à Dart (condition : l'échelle doit être connue AVANT le
    // premier palier pour choisir les niveaux). autoStartLoad:false → aucun
    // fragment, aucune lecture. Chaque palier détruit ce moteur et en recrée
    // un neuf (cf. startHls) : démarrage à froid, sans estimation de débit
    // ni buffers hérités du palier précédent.
    engine = new Hls({ capLevelToPlayerSize: false, startLevel: -1,
                       autoStartLoad: false });
    engine.loadSource('$streamTestStreamUrl');
    engine.attachMedia(video);
    engine.on(Hls.Events.MANIFEST_PARSED, report);
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
