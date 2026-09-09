import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:logger/logger.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../constants/config.dart';
import 'streaming_test_service_native.dart' as native_impl;
import 'streaming_test_service_web.dart'
    if (dart.library.io) 'streaming_test_service_web_stub.dart' as web_impl;
import 'traffic_stats_service.dart';

/// Mesures d'une qualité vidéo — une colonne du tableau de résultats.
class StreamingQualityResult {
  /// Libellé affiché : '720p', '1080p', '2160p'.
  final String label;

  /// Vrai si YouTube a réellement servi cette qualité. Faux → colonne « — ».
  final bool reached;

  /// Part du temps passée à regarder plutôt qu'à attendre, en %.
  final double performanceRate;

  /// Délai avant la première image.
  final double initialLoadingSec;

  /// Temps cumulé passé en mise en tampon pendant la lecture.
  final double bufferingSec;

  /// Nombre d'interruptions après le démarrage.
  final int rebufferCount;

  /// Données téléchargées pendant la lecture. -1 = non mesurable (iOS/web).
  final int dataUsedKiB;

  /// Faux si YouTube a changé de qualité pendant la mesure : les chiffres
  /// mélangent plusieurs qualités et sont signalés comme approximatifs.
  final bool stable;

  const StreamingQualityResult({
    required this.label,
    required this.reached,
    this.performanceRate = 0,
    this.initialLoadingSec = 0,
    this.bufferingSec = 0,
    this.rebufferCount = 0,
    this.dataUsedKiB = -1,
    this.stable = true,
  });

  /// Qualité non testée ou non servie par YouTube.
  const StreamingQualityResult.unavailable(this.label)
      : reached = false,
        performanceRate = 0,
        initialLoadingSec = 0,
        bufferingSec = 0,
        rebufferCount = 0,
        dataUsedKiB = -1,
        stable = true;

  /// Hauteur en pixels déduite du libellé ('1080p' → 1080).
  int get height => int.tryParse(label.replaceAll('p', '')) ?? 0;

  Map<String, dynamic> toJson() => {
        'label': label,
        'reached': reached,
        'performanceRate': performanceRate,
        'initialLoadingSec': initialLoadingSec,
        'bufferingSec': bufferingSec,
        'rebufferCount': rebufferCount,
        'dataUsedKiB': dataUsedKiB,
        'stable': stable,
      };

  factory StreamingQualityResult.fromJson(Map<String, dynamic> j) =>
      StreamingQualityResult(
        label: (j['label'] ?? '').toString(),
        reached: j['reached'] == true,
        performanceRate: (j['performanceRate'] as num?)?.toDouble() ?? 0,
        initialLoadingSec: (j['initialLoadingSec'] as num?)?.toDouble() ?? 0,
        bufferingSec: (j['bufferingSec'] as num?)?.toDouble() ?? 0,
        rebufferCount: (j['rebufferCount'] as num?)?.toInt() ?? 0,
        dataUsedKiB: (j['dataUsedKiB'] as num?)?.toInt() ?? -1,
        stable: j['stable'] != false,
      );
}

/// Résultat du test de streaming vidéo.
class StreamingTestResult {
  /// Une entrée par qualité testée, dans l'ordre d'affichage.
  final List<StreamingQualityResult> qualities;

  final int startupMs; // démarrage de la première qualité obtenue
  final int rebufferCount; // interruptions cumulées
  final double rebufferRatio; // part du temps en mise en tampon (0-1)
  final String maxResolution; // plus haute qualité réellement servie
  final double score; // score synthétique 0-100

  /// Raison d'un test sans mesure, affichée à l'utilisateur. null si tout va
  /// bien. Sans cela, un échec est indiscernable d'un réseau catastrophique :
  /// dans les deux cas le tableau n'affiche que des tirets.
  final String? error;

  const StreamingTestResult({
    required this.qualities,
    required this.startupMs,
    required this.rebufferCount,
    required this.rebufferRatio,
    required this.maxResolution,
    required this.score,
    this.error,
  });

  /// Total des données consommées par le test. -1 si non mesurable.
  int get totalDataKiB {
    final measured = qualities.where((q) => q.dataUsedKiB >= 0);
    if (measured.isEmpty) return -1;
    return measured.fold<int>(0, (sum, q) => sum + q.dataUsedKiB);
  }

  String encodeQualities() => jsonEncode({
        'rows': qualities.map((q) => q.toJson()).toList(),
        if (error != null) 'error': error,
      });

  /// Relit le tableau des qualités depuis sa forme stockée. Liste vide si
  /// la valeur est absente ou illisible (anciens résultats en base).
  ///
  /// Accepte les deux formes : la liste nue écrite par les premières versions,
  /// et l'enveloppe actuelle `{rows, error}`.
  static List<StreamingQualityResult> decodeQualities(String? json) {
    final data = _decode(json);
    final rows = data is List ? data : (data is Map ? data['rows'] : null);
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map((e) => StreamingQualityResult.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Message d'échec conservé avec le résultat, ou null si le test a abouti.
  static String? decodeError(String? json) {
    final data = _decode(json);
    if (data is! Map) return null;
    final error = data['error']?.toString();
    return (error == null || error.isEmpty) ? null : error;
  }

  static dynamic _decode(String? json) {
    if (json == null || json.isEmpty) return null;
    try {
      return jsonDecode(json);
    } catch (_) {
      return null;
    }
  }

  @override
  String toString() => 'Streaming: max $maxResolution, démarrage ${startupMs}ms, '
      '$rebufferCount interruptions (${(rebufferRatio * 100).toStringAsFixed(1)}%), '
      'score ${score.toStringAsFixed(1)}';
}

/// Mesures brutes d'un palier, avant d'être rangées dans le tableau.
///
/// [servedKey] est la qualité que YouTube a **réellement** servie, qui n'est
/// pas forcément celle demandée : c'est elle qui détermine la colonne.
class LevelMeasurement {
  final bool played; // la lecture a démarré
  final String servedKey;
  final double performanceRate;
  final double initialLoadingSec;
  final double bufferingSec;
  final int rebufferCount;
  final int dataUsedKiB;

  /// Faux si YouTube a changé de qualité pendant la fenêtre mesurée : les
  /// chiffres mélangent alors plusieurs qualités et ne valent qu'en ordre
  /// de grandeur.
  final bool stable;

  const LevelMeasurement({
    required this.played,
    this.servedKey = '',
    this.performanceRate = 0,
    this.initialLoadingSec = 0,
    this.bufferingSec = 0,
    this.rebufferCount = 0,
    this.dataUsedKiB = -1,
    this.stable = true,
  });

  static const notPlayed = LevelMeasurement(played: false);
}

/// Ce que l'interface doit afficher pendant le test de streaming.
sealed class StreamingDisplay {
  const StreamingDisplay();
}

/// Lecteur YouTube dans une WebView (Android, iOS, macOS).
class NativeStreamingDisplay extends StreamingDisplay {
  final WebViewController controller;
  const NativeStreamingDisplay({required this.controller});
}

/// Lecteur YouTube dans un élément DOM embarqué (web/Chrome).
class WebStreamingDisplay extends StreamingDisplay {
  /// Identifiant de vue enregistré via `platformViewRegistry`.
  final String viewType;
  const WebStreamingDisplay({required this.viewType});
}

typedef StreamingProgressCallback = void Function(
    double progress, String message);

/// Fournit le contrôleur WebView à l'interface pour afficher le lecteur,
/// puis null quand le test est terminé.
typedef StreamingControllerCallback = void Function(
    StreamingDisplay? display);

/// Remonte le tableau des qualités au fil de l'eau, pour l'affichage en direct.
typedef StreamingRowsCallback = void Function(
    List<StreamingQualityResult> rows);

/// Calculs partagés entre les implémentations native (WebView) et web du test
/// de streaming : consolidation des paliers, scores et messages d'erreur.
class StreamingMetrics {
  /// Nom lisible d'une clé de qualité de l'IFrame API.
  static String qualityLabel(String key) => const {
        'tiny': '144p',
        'small': '240p',
        'medium': '360p',
        'large': '480p',
        'hd720': '720p',
        'hd1080': '1080p',
        'hd1440': '1440p',
        'hd2160': '2160p',
        'highres': 'au-delà de 2160p',
      }[key] ??
      (key.isEmpty ? 'inconnue' : key);

  /// Explique les colonnes restées vides, quand YouTube n'a pas servi toutes
  /// les qualités demandées. null si le tableau est complet.
  static String? servedNote(
      List<StreamingQualityResult> rows, List<String> served) {
    if (served.isEmpty) {
      return 'Aucune qualité n\'a pu être lue. Réseau trop faible ou lecteur '
          'indisponible.';
    }
    if (rows.every((r) => r.reached)) return null;

    final unique = served.toSet().toList();
    return 'YouTube choisit lui-même la qualité selon le réseau et la taille '
        'du lecteur : il a servi ${unique.join(', ')} pendant ce test. Les '
        'qualités non servies restent vides.';
  }

  /// Consolide les mesures par qualité en indicateurs globaux (stockés dans
  /// l'historique et envoyés au serveur).
  static StreamingTestResult aggregate(List<StreamingQualityResult> rows,
      {String? error}) {
    final reached = rows.where((r) => r.reached).toList();

    final bestHeight = reached.isEmpty
        ? 0
        : reached.map((r) => r.height).reduce((a, b) => a > b ? a : b);
    final startupMs =
        reached.isEmpty ? 0 : (reached.first.initialLoadingSec * 1000).round();
    final rebuffers =
        reached.fold<int>(0, (sum, r) => sum + r.rebufferCount);

    final buffering = reached.fold<double>(0, (sum, r) => sum + r.bufferingSec);
    final watched = reached.fold<double>(
        0, (sum, r) => sum + STREAMING_LEVEL_DURATION_SEC - r.bufferingSec);
    final measured = watched + buffering;
    final ratio = measured > 0 ? (buffering / measured).clamp(0.0, 1.0) : 0.0;

    final score = computeScore(
        bestHeight.toDouble(), startupMs, ratio.toDouble(), rebuffers);

    return StreamingTestResult(
      qualities: rows,
      startupMs: startupMs,
      rebufferCount: rebuffers,
      rebufferRatio: double.parse(ratio.toStringAsFixed(3)),
      maxResolution: bestHeight > 0 ? '${bestHeight}p' : 'inconnue',
      score: double.parse(score.toStringAsFixed(1)),
      error: error,
    );
  }

  static double computeScore(
      double maxHeight, int startupMs, double rebufferRatio, int rebufferCount) {
    final double base = maxHeight >= 2160
        ? 100
        : maxHeight >= 1080
            ? 90
            : maxHeight >= 720
                ? 75
                : maxHeight >= 480
                    ? 55
                    : maxHeight > 0
                        ? 35
                        : 0;
    double score = base;
    if (startupMs > 2000) score -= (startupMs - 2000) / 500;
    score -= 40 * rebufferRatio + 2 * rebufferCount;
    return score.clamp(0, 100);
  }

  /// Traduit les codes d'erreur de l'IFrame Player API.
  static String errorMessage(int code) {
    switch (code) {
      case 2:
        return 'Identifiant de vidéo invalide.';
      case 5:
        return 'Le lecteur HTML5 ne peut pas lire cette vidéo sur cet appareil.';
      case 100:
        return 'Vidéo introuvable ou retirée de YouTube.';
      case 101:
      case 150:
        return 'Le propriétaire de la vidéo en interdit la lecture intégrée. '
            'Choisissez une autre vidéo dans la configuration.';
      case 152:
      case 153:
        // Codes non documentés par Google, apparus avec le durcissement des
        // règles d'intégration : YouTube exige que l'application s'identifie
        // par un en-tête Referer qu'il juge légitime.
        return 'YouTube refuse la lecture intégrée depuis cette application '
            '(erreur $code). Le test de streaming ne peut pas aboutir tant '
            'que YouTube n\'accepte pas l\'intégration.';
      default:
        return 'Le lecteur YouTube a renvoyé l\'erreur $code.';
    }
  }
}

/// Logique commune aux deux plateformes du test de streaming : enchaînement
/// des paliers (720p, 1080p, 2160p), mesure d'un palier, consolidation.
///
/// La plateforme n'intervient que par cinq points d'extension :
///  - [openPlayer] / [closePlayer] : mise en place et retrait du lecteur ;
///  - [jsBuildLevel] / [jsStartLevel] / [jsStopLevel] : pilotage du lecteur.
abstract class StreamingRunner {
  final Logger logger = Logger();
  final TrafficStatsService _traffic = TrafficStatsService();

  Completer<void>? _ready; // API YouTube chargée
  Completer<void>? _levelReady; // lecteur de la qualité courante construit
  Completer<void>? _started; // première image de la qualité courante
  Completer<Map<String, dynamic>>? _level; // bilan de la qualité courante

  /// Qualités disponibles sur la vidéo, connues seulement après le premier
  /// palier (l'API renvoie une liste vide tant que rien n'a été lu).
  final Set<String> _available = {};

  /// Renseigné si le lecteur signale une erreur, pour l'expliquer à l'écran.
  ///
  /// Lecture publique : les implémentations de plateforme peuvent aussi
  /// renseigner une erreur (ex. API YouTube injoignable).
  String? playerError;

  /// Vrai tant que l'événement 'ready' de l'API n'est pas arrivé. Sert aux
  /// implémentations de plateforme à débloquer l'attente en cas de panne.
  bool get isReadyPending => _ready?.isCompleted == false;

  /// Débloque l'attente de l'API (implémentations de plateforme).
  void completeReady() {
    if (_ready?.isCompleted == false) _ready!.complete();
  }

  Future<StreamingTestResult> runTest({
    StreamingControllerCallback? onController,
    StreamingProgressCallback? onProgress,
    StreamingRowsCallback? onRows,
  }) async {
    final keys = STREAMING_QUALITY_LEVELS.keys.toList();
    final rows = <StreamingQualityResult>[
      for (final label in STREAMING_QUALITY_LEVELS.values)
        StreamingQualityResult.unavailable(label),
    ];
    // Qualités effectivement servies, dans l'ordre : sert à expliquer à
    // l'utilisateur pourquoi certaines colonnes restent vides.
    final served = <String>[];
    onRows?.call(List.of(rows));

    try {
      onProgress?.call(0.02, 'Ouverture du lecteur YouTube…');
      _ready = Completer<void>();
      await openPlayer(onController);

      try {
        await _ready!.future.timeout(const Duration(seconds: 25));
      } on TimeoutException {
        logger.w('Streaming: lecteur YouTube non chargé (réseau ou ID vidéo)');
        return StreamingMetrics.aggregate(rows,
            error: 'Lecteur YouTube injoignable. Vérifiez la connexion '
                'Internet, puis relancez le test.');
      }
      if (playerError != null) {
        return StreamingMetrics.aggregate(rows, error: playerError);
      }

      for (int i = 0; i < keys.length; i++) {
        final key = keys[i];
        final label = STREAMING_QUALITY_LEVELS[key]!;

        // Après le premier palier on connaît les qualités de la vidéo : inutile
        // de perdre 10 s sur une qualité que la source n'a pas.
        if (_available.isNotEmpty && !_available.contains(key)) {
          logger.i('Streaming: $label indisponible sur cette vidéo, ignoré');
          continue;
        }

        onProgress?.call((i + 0.1) / keys.length, 'Chargement en $label…');
        final m = await _measureQuality(
          key: key,
          label: label,
          onProgress: (frac, msg) =>
              onProgress?.call((i + frac) / keys.length, msg),
        );
        if (!m.played) continue;

        // La qualité demandée n'est qu'une suggestion : `setPlaybackQuality`
        // est ignoré par le lecteur depuis 2019. On range donc la mesure dans
        // la colonne de ce qui a été SERVI, jamais de ce qui a été demandé —
        // sinon on jetterait des mesures parfaitement valides.
        served.add(StreamingMetrics.qualityLabel(m.servedKey));
        final column = keys.indexOf(m.servedKey);
        if (column < 0) continue; // qualité hors tableau (360p, 1440p…)

        rows[column] = StreamingQualityResult(
          label: STREAMING_QUALITY_LEVELS[m.servedKey]!,
          reached: true,
          performanceRate: m.performanceRate,
          initialLoadingSec: m.initialLoadingSec,
          bufferingSec: m.bufferingSec,
          rebufferCount: m.rebufferCount,
          dataUsedKiB: m.dataUsedKiB,
          stable: m.stable,
        );
        onRows?.call(List.of(rows));
      }
    } catch (e) {
      logger.e('Streaming: test interrompu ($e)');
    } finally {
      // Libère la référence côté UI avant de couper la lecture.
      onController?.call(null);
      try {
        await jsStopLevel();
      } catch (_) {
        // Le lecteur n'a jamais démarré : rien à arrêter.
      }
      await closePlayer();
    }

    final result = StreamingMetrics.aggregate(
        rows, error: playerError ?? StreamingMetrics.servedNote(rows, served));
    logger.i('$result — servi : ${served.join(', ')}');
    return result;
  }

  /// Joue une qualité pendant [STREAMING_LEVEL_DURATION_SEC] et en mesure les
  /// quatre indicateurs.
  Future<LevelMeasurement> _measureQuality({
    required String key,
    required String label,
    required void Function(double frac, String msg) onProgress,
  }) async {
    // Le lecteur prend les dimensions de la qualité visée : c'est ce qui
    // détermine ce que YouTube accepte de servir.
    final height = int.tryParse(label.replaceAll('p', '')) ?? 1080;
    final width = (height * 16 / 9).round();

    // Lecteur NEUF pour cette qualité : pas d'estimation de bande passante
    // héritée du palier précédent.
    _levelReady = Completer<void>();
    await jsBuildLevel(key, width, height);
    try {
      await _levelReady!.future
          .timeout(const Duration(seconds: STREAMING_LEVEL_TIMEOUT_SEC));
    } on TimeoutException {
      logger.w('Streaming: lecteur $label non construit');
      return LevelMeasurement.notPlayed;
    }

    // Laisse YouTube prendre en compte les dimensions avant de lancer.
    await Future.delayed(
        const Duration(milliseconds: STREAMING_STAGE_SETTLE_MS));

    final rxBefore = await _traffic.rxBytes();
    _started = Completer<void>();
    _level = Completer<Map<String, dynamic>>();

    final wall = Stopwatch()..start();
    await jsStartLevel(key);

    // Attente de la première image.
    try {
      await _started!.future
          .timeout(const Duration(seconds: STREAMING_LEVEL_TIMEOUT_SEC));
    } on TimeoutException {
      logger.w('Streaming: $label n\'a jamais démarré');
      await jsStopLevel();
      return LevelMeasurement.notPlayed;
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

    final report = await jsStopLevel();
    wall.stop();
    final rxAfter = await _traffic.rxBytes();

    final servedKey = (report['q'] ?? '').toString();
    if (servedKey != key) {
      logger.i('Streaming: $label demandé, '
          '${StreamingMetrics.qualityLabel(servedKey)} servi');
    }

    final initialSec = ((report['startupMs'] as num?)?.toDouble() ?? 0) / 1000;
    final bufferingSec = ((report['bufferMs'] as num?)?.toDouble() ?? 0) / 1000;
    final totalSec = wall.elapsedMilliseconds / 1000;
    final watchedSec = (totalSec - initialSec - bufferingSec).clamp(0.0, totalSec);
    final performance = totalSec > 0 ? watchedSec / totalSec * 100 : 0.0;

    return LevelMeasurement(
      played: true,
      servedKey: servedKey,
      performanceRate: double.parse(performance.toStringAsFixed(2)),
      initialLoadingSec: double.parse(initialSec.toStringAsFixed(3)),
      bufferingSec: double.parse(bufferingSec.toStringAsFixed(3)),
      rebufferCount: (report['rebuffers'] as num?)?.toInt() ?? 0,
      dataUsedKiB: TrafficStatsService.kibBetween(rxBefore, rxAfter),
      stable: ((report['segments'] as num?)?.toInt() ?? 1) <= 1,
    );
  }

  /// Attend le bilan du palier courant (complété par l'événement 'level').
  Future<Map<String, dynamic>> waitLevelReport() async {
    try {
      return await _level!.future.timeout(const Duration(seconds: 5));
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  /// Répartit les événements remontés par le lecteur (mêmes messages sur
  /// les deux plateformes : ready, levelready, start, level, error, jserror).
  void handleEvent(Map<String, dynamic> event) {
    switch (event['e']) {
      case 'ready':
        if (_ready?.isCompleted == false) _ready!.complete();
        break;
      case 'levelready':
        if (_levelReady?.isCompleted == false) _levelReady!.complete();
        break;
      case 'start':
        if (_started?.isCompleted == false) _started!.complete();
        break;
      case 'level':
        final avail = (event['avail'] ?? '').toString();
        if (avail.isNotEmpty) {
          _available
            ..clear()
            ..addAll(avail.split(',').where((e) => e.isNotEmpty));
        }
        if (_level?.isCompleted == false) _level!.complete(event);
        break;
      case 'error':
        final code = (event['code'] as num?)?.toInt() ?? 0;
        playerError = StreamingMetrics.errorMessage(code);
        logger.w('Streaming: erreur lecteur YouTube (code $code)');
        // Débloque les attentes en cours : la vidéo est injouable.
        completeReady();
        if (_started?.isCompleted == false) _started!.complete();
        break;
      case 'jserror':
        // Erreur JavaScript dans la page hôte : sans elle, un échec de
        // chargement du script de l'API ressemblerait à un simple timeout.
        playerError ??= 'Erreur du lecteur : ${event['msg']}';
        logger.w('Streaming: erreur JS — ${event['msg']}');
        completeReady();
        break;
    }
  }

  /// Mise en place du lecteur (WebView ou élément DOM) ; doit livrer le
  /// display via [onController] et déclencher l'événement 'ready'.
  Future<void> openPlayer(StreamingControllerCallback? onController);

  /// Nettoyage après le test.
  Future<void> closePlayer();

  Future<void> jsBuildLevel(String key, int width, int height);

  Future<void> jsStartLevel(String key);

  Future<Map<String, dynamic>> jsStopLevel();
}

/// Test de streaming **sur YouTube**, à la manière de nPerf.
///
/// Charge le lecteur YouTube (IFrame Player API) puis demande successivement
/// chaque qualité (720p, 1080p, 2160p). Pour chacune on mesure le délai avant
/// la première image, le temps cumulé de mise en tampon, le volume de données
/// téléchargé, et on en dérive un **taux de performance** :
///
///     performance = temps réellement regardé / temps total écoulé
///
/// Sur Android/iOS/macOS le lecteur tourne dans une WebView ; sur le web
/// (Chrome) il est embarqué directement dans la page. Le comportement et les
/// résultats sont identiques.
class StreamingTestService {
  Future<StreamingTestResult> runTest({
    StreamingControllerCallback? onController,
    StreamingProgressCallback? onProgress,
    StreamingRowsCallback? onRows,
  }) {
    final runner = kIsWeb
        ? web_impl.WebStreamingRunner()
        : native_impl.NativeStreamingRunner();
    return runner.runTest(
      onController: onController,
      onProgress: onProgress,
      onRows: onRows,
    );
  }
}