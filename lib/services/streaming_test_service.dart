import 'dart:async';
import 'dart:convert';
import 'dart:io' show ContentType, HttpServer, InternetAddress;
import 'dart:ui' show Color;

import 'package:logger/logger.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import '../constants/config.dart';
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

  /// Données téléchargées pendant la lecture. -1 = non mesurable (iOS).
  final int dataUsedKiB;

  /// Faux si YouTube a changé de qualité pendant la mesure : les chiffres
  /// mélangent plusieurs qualités et sont signalés comme approximatifs.
  final bool stable;

  /// Qualité réellement servie pendant le palier, quand elle diffère de
  /// [label] (demandée). Vide si YouTube a servi la qualité demandée — cas
  /// nominal. Exemple : palier 2160p, [label] = '2160p', [servedLabel] =
  /// '1440p' : YouTube n'avait pas assez de bande passante pour le 4K.
  /// La mesure reste valide : elle dit ce que le réseau a permis de tenir
  /// quand on a DEMANDÉ cette qualité, c'est pourquoi elle est rangée dans
  /// cette colonne au lieu d'être jetée.
  final String servedLabel;

  const StreamingQualityResult({
    required this.label,
    required this.reached,
    this.performanceRate = 0,
    this.initialLoadingSec = 0,
    this.bufferingSec = 0,
    this.rebufferCount = 0,
    this.dataUsedKiB = -1,
    this.stable = true,
    this.servedLabel = '',
  });

  /// Qualité non testée ou non servie par YouTube.
  const StreamingQualityResult.unavailable(this.label)
      : reached = false,
        performanceRate = 0,
        initialLoadingSec = 0,
        bufferingSec = 0,
        rebufferCount = 0,
        dataUsedKiB = -1,
        stable = true,
        servedLabel = '';

  /// Hauteur en pixels déduite du libellé ('1080p' → 1080).
  int get height => int.tryParse(label.replaceAll('p', '')) ?? 0;

  /// Libellé affiché en en-tête de colonne : la qualité que YouTube a
  /// réellement servie quand la colonne porte une mesure, sinon la qualité
  /// demandée (seule information disponible pour un palier sans mesure).
  /// Décision produit : l'en-tête reflète ce qui a été servi — YouTube
  /// servant souvent autre chose que la qualité demandée (1440p pour un
  /// palier 2160p), c'est le seul libellé honnête pour lire les chiffres.
  String get displayLabel =>
      (reached && servedLabel.isNotEmpty) ? servedLabel : label;

  /// Hauteur réellement servie : celle de [servedLabel] quand YouTube a
  /// livré autre chose que la qualité demandée, sinon [height]. C'est elle
  /// qui alimente la résolution maximale et le score — demander le 4K ne
  /// vaut preuve de débit que si le 4K a été servi.
  int get servedHeight =>
      int.tryParse(servedLabel.replaceAll(RegExp('[^0-9]'), '')) ?? height;

  Map<String, dynamic> toJson() => {
        'label': label,
        'reached': reached,
        'performanceRate': performanceRate,
        'initialLoadingSec': initialLoadingSec,
        'bufferingSec': bufferingSec,
        'rebufferCount': rebufferCount,
        'dataUsedKiB': dataUsedKiB,
        'stable': stable,
        if (servedLabel.isNotEmpty) 'servedLabel': servedLabel,
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
        servedLabel: (j['servedLabel'] ?? '').toString(),
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
class _LevelMeasurement {
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

  const _LevelMeasurement({
    required this.played,
    this.servedKey = '',
    this.performanceRate = 0,
    this.initialLoadingSec = 0,
    this.bufferingSec = 0,
    this.rebufferCount = 0,
    this.dataUsedKiB = -1,
    this.stable = true,
  });

  static const notPlayed = _LevelMeasurement(played: false);
}

typedef StreamingProgressCallback = void Function(
    double progress, String message);

/// Fournit le contrôleur WebView à l'interface pour afficher le lecteur,
/// puis null quand le test est terminé.
typedef StreamingControllerCallback = void Function(
    WebViewController? controller);

/// Remonte le tableau des qualités au fil de l'eau, pour l'affichage en direct.
typedef StreamingRowsCallback = void Function(
    List<StreamingQualityResult> rows);

/// Test de streaming **sur YouTube**, à la manière de nPerf.
///
/// Charge le lecteur YouTube (IFrame Player API) dans un WebView visible, puis
/// demande successivement chaque qualité (720p, 1080p, 2160p). Pour chacune on
/// mesure le délai avant la première image, le temps cumulé de mise en tampon,
/// le volume de données téléchargé, et on en dérive un **taux de performance** :
///
///     performance = temps réellement regardé / temps total écoulé
///
/// Autrement dit la part du temps passée à voir la vidéo plutôt qu'à l'attendre.
///
/// ⚠️ `setPlaybackQuality()` est déprécié et **ignoré** par le lecteur YouTube
/// depuis 2019 : la qualité demandée n'est qu'une suggestion. On relit donc
/// systématiquement `getPlaybackQuality()` en fin de palier, et une qualité qui
/// n'a pas été réellement servie est marquée non atteinte (colonne « — »).
/// C'est aussi ce que fait nPerf lorsqu'il affiche « - » pour le 2160p.
class StreamingTestService {
  final logger = Logger();
  final TrafficStatsService _traffic = TrafficStatsService();

  Completer<void>? _ready; // API YouTube chargée
  Completer<void>? _levelReady; // lecteur de la qualité courante construit
  Completer<void>? _started; // première image de la qualité courante
  Completer<Map<String, dynamic>>? _level; // bilan de la qualité courante

  /// Qualités disponibles sur la vidéo, connues seulement après le premier
  /// palier (l'API renvoie une liste vide tant que rien n'a été lu).
  final Set<String> _available = {};

  /// Renseigné si le lecteur signale une erreur, pour l'expliquer à l'écran.
  String? _playerError;

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

    final controller = _buildController();
    final host = _PlayerHost();

    try {
      onProgress?.call(0.02, 'Ouverture du lecteur YouTube…');
      final uri = await host.start(_playerHtml);
      await controller.loadRequest(uri);
      onController?.call(controller);

      _ready = Completer<void>();
      try {
        await _ready!.future.timeout(const Duration(seconds: 25));
      } on TimeoutException {
        logger.w('Streaming: lecteur YouTube non chargé (réseau ou ID vidéo)');
        return _aggregate(rows,
            error: 'Lecteur YouTube injoignable. Vérifiez la connexion '
                'Internet, puis relancez le test.');
      }
      if (_playerError != null) {
        return _aggregate(rows, error: _playerError);
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
          controller: controller,
          key: key,
          label: label,
          onProgress: (frac, msg) =>
              onProgress?.call((i + frac) / keys.length, msg),
        );
        if (!m.played) continue;

        // La mesure est rangée dans la colonne du palier DEMANDÉ (colonne i) :
        // elle dit ce que le réseau a permis de tenir quand on a demandé
        // cette qualité. La qualité réellement servie est conservée à part
        // (servedLabel) : YouTube ignore `setPlaybackQuality` depuis 2019 et
        // sert souvent 1440p quand on demande 2160p — jeter la mesure parce
        // que la qualité servie n'a pas de colonne laissait le tableau vide,
        // toutes les mesures partaient ainsi d'un `continue` précoce.
        final servedLabel = _qualityLabel(m.servedKey);
        served.add(servedLabel);

        rows[i] = StreamingQualityResult(
          label: label,
          reached: true,
          performanceRate: m.performanceRate,
          initialLoadingSec: m.initialLoadingSec,
          bufferingSec: m.bufferingSec,
          rebufferCount: m.rebufferCount,
          dataUsedKiB: m.dataUsedKiB,
          stable: m.stable,
          servedLabel: servedLabel == label ? '' : servedLabel,
        );
        onRows?.call(List.of(rows));
      }
    } catch (e) {
      logger.e('Streaming: test interrompu ($e)');
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

    final result = _aggregate(rows, error: _playerError ?? _servedNote(rows, served));
    logger.i('$result — servi : ${served.join(', ')}');
    return result;
  }

  /// Joue une qualité pendant [STREAMING_LEVEL_DURATION_SEC] et en mesure les
  /// quatre indicateurs.
  Future<_LevelMeasurement> _measureQuality({
    required WebViewController controller,
    required String key,
    required String label,
    required StreamingProgressCallback onProgress,
  }) async {
    // Le lecteur prend les dimensions de la qualité visée : c'est ce qui
    // détermine ce que YouTube accepte de servir.
    final height = int.tryParse(label.replaceAll('p', '')) ?? 1080;
    final width = (height * 16 / 9).round();

    // Lecteur NEUF pour cette qualité : pas d'estimation de bande passante
    // héritée du palier précédent.
    _levelReady = Completer<void>();
    await controller.runJavaScript('buildLevel("$key", $width, $height)');
    try {
      await _levelReady!.future
          .timeout(const Duration(seconds: STREAMING_LEVEL_TIMEOUT_SEC));
    } on TimeoutException {
      logger.w('Streaming: lecteur $label non construit');
      return _LevelMeasurement.notPlayed;
    }

    // Laisse YouTube prendre en compte les dimensions avant de lancer.
    await Future.delayed(
        const Duration(milliseconds: STREAMING_STAGE_SETTLE_MS));

    final rxBefore = await _traffic.rxBytes();
    _started = Completer<void>();
    _level = Completer<Map<String, dynamic>>();

    final wall = Stopwatch()..start();
    await controller.runJavaScript('startLevel("$key")');

    // Attente de la première image.
    try {
      await _started!.future
          .timeout(const Duration(seconds: STREAMING_LEVEL_TIMEOUT_SEC));
    } on TimeoutException {
      logger.w('Streaming: $label n\'a jamais démarré');
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

    final servedKey = (report['q'] ?? '').toString();
    if (servedKey != key) {
      logger.i('Streaming: $label demandé, ${_qualityLabel(servedKey)} servi');
    }

    final initialSec = ((report['startupMs'] as num?)?.toDouble() ?? 0) / 1000;
    final bufferingSec = ((report['bufferMs'] as num?)?.toDouble() ?? 0) / 1000;
    final totalSec = wall.elapsedMilliseconds / 1000;
    final watchedSec = (totalSec - initialSec - bufferingSec).clamp(0.0, totalSec);
    final performance = totalSec > 0 ? watchedSec / totalSec * 100 : 0.0;

    return _LevelMeasurement(
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

  /// Explique les colonnes restées vides, quand YouTube n'a pas servi toutes
  /// les qualités demandées. null si le tableau est complet.
  String? _servedNote(List<StreamingQualityResult> rows, List<String> served) {
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

  /// Nom lisible d'une clé de qualité de l'IFrame API.
  String _qualityLabel(String key) => const {
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

  /// Met la lecture en pause et récupère le bilan du palier.
  Future<Map<String, dynamic>> _stopLevel(WebViewController controller) async {
    try {
      await controller.runJavaScript('stopLevel()');
      return await _level!.future.timeout(const Duration(seconds: 5));
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  /// Consolide les mesures par qualité en indicateurs globaux (stockés dans
  /// l'historique et envoyés au serveur).
  StreamingTestResult _aggregate(List<StreamingQualityResult> rows,
      {String? error}) {
    final reached = rows.where((r) => r.reached).toList();

    // Résolution maximale et score : basés sur ce que YouTube a réellement
    // SERVI (servedHeight), pas sur ce qu'on a demandé. Demander 2160p sur
    // un réseau qui n'a tenu que 1440p ne doit pas rapporter les points du 4K.
    final bestHeight = reached.isEmpty
        ? 0
        : reached.map((r) => r.servedHeight).reduce((a, b) => a > b ? a : b);
    final startupMs =
        reached.isEmpty ? 0 : (reached.first.initialLoadingSec * 1000).round();
    final rebuffers =
        reached.fold<int>(0, (sum, r) => sum + r.rebufferCount);

    final buffering = reached.fold<double>(0, (sum, r) => sum + r.bufferingSec);
    final watched = reached.fold<double>(
        0, (sum, r) => sum + STREAMING_LEVEL_DURATION_SEC - r.bufferingSec);
    final measured = watched + buffering;
    final ratio = measured > 0 ? (buffering / measured).clamp(0.0, 1.0) : 0.0;

    final score = _computeScore(
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

  double _computeScore(
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

  // ── WebView ────────────────────────────────────────────────────────────────

  WebViewController _buildController() {
    // iOS : sans `allowsInlineMediaPlayback` la vidéo part en plein écran natif
    // et l'utilisateur perd de vue le test.
    final params = WebViewPlatform.instance is WebKitWebViewPlatform
        ? WebKitWebViewControllerCreationParams(
            allowsInlineMediaPlayback: true,
            mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
          )
        : const PlatformWebViewControllerCreationParams();

    final controller = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF000000))
      ..addJavaScriptChannel('YeleStream', onMessageReceived: _onJsMessage);

    // Android : sans ceci, `playVideo()` déclenché par du JS est bloqué faute
    // de geste utilisateur, et aucun palier ne démarrerait jamais.
    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      platform.setMediaPlaybackRequiresUserGesture(false);
    }

    return controller;
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
        _playerError = _errorMessage(code);
        logger.w('Streaming: erreur lecteur YouTube (code $code)');
        // Débloque les attentes en cours : la vidéo est injouable.
        if (_ready?.isCompleted == false) _ready!.complete();
        if (_started?.isCompleted == false) _started!.complete();
        break;
      case 'jserror':
        // Erreur JavaScript dans la page hôte : sans elle, un échec de
        // chargement du script de l'API ressemblerait à un simple timeout.
        _playerError ??= 'Erreur du lecteur : ${event['msg']}';
        logger.w('Streaming: erreur JS — ${event['msg']}');
        if (_ready?.isCompleted == false) _ready!.complete();
        break;
    }
  }

  /// Traduit les codes d'erreur de l'IFrame Player API.
  String _errorMessage(int code) {
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
        // par un en-tête Referer qu'il juge légitime, ce qu'une page servie
        // depuis la boucle locale ne garantit pas.
        return 'YouTube refuse la lecture intégrée depuis cette application '
            '(erreur $code). Le test de streaming ne peut pas aboutir tant '
            'que YouTube n\'accepte pas l\'intégration.';
      default:
        return 'Le lecteur YouTube a renvoyé l\'erreur $code.';
    }
  }

  /// Page hôte du lecteur YouTube, servie par [_PlayerHost] depuis
  /// `http://127.0.0.1:<port>`.
  ///
  /// L'IFrame API valide l'origine de la page hôte par un échange
  /// `postMessage` avant d'émettre `onReady`. Une page injectée via
  /// `loadHtmlString` — même avec un `baseUrl` pointant sur youtube.com —
  /// n'a pas d'origine réelle : la validation échoue silencieusement, le
  /// lecteur reste noir et `onReady` n'arrive jamais. D'où le serveur local,
  /// qui fournit une vraie origine HTTP, transmise ici en `origin`.
  String _playerHtml(String origin) => '''
<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1, user-scalable=no">
<style>
  html,body{margin:0;padding:0;background:#000;overflow:hidden;height:100%}
  /* Le lecteur est RÉELLEMENT dimensionné en 1920x1080, puis réduit
     visuellement par une transformation. YouTube choisit sa qualité d'après
     la taille du lecteur : une zone de quelques centaines de pixels de large
     ne se voit jamais servir de 1080p, encore moins de 2160p. Sans cette
     mise à l'échelle, le test plafonnerait à 360p quelle que soit la
     qualité demandée, et les colonnes resteraient vides. */
  #stage{position:absolute;top:0;left:0;width:1920px;height:1080px;
         transform-origin:0 0}
  #player{width:100%;height:100%}
</style>
</head>
<body>
<div id="stage"><div id="player"></div></div>
<script>
var player = null;
var stageW = 1920, stageH = 1080;
var t0 = 0, startupMs = -1, bufferMs = 0, bufferStart = 0;
var rebuffers = 0, started = false;

// Durée passée dans chaque qualité pendant la fenêtre mesurée. YouTube peut
// basculer en cours de lecture : sans ce suivi, on attribuerait à une qualité
// des chiffres qui en mélangent deux.
var qSegments = [], curQ = null, curQStart = 0;

function send(o) { YeleStream.postMessage(JSON.stringify(o)); }

// Sans ceci, un échec de chargement du script de l'API serait indiscernable
// d'un simple dépassement de délai.
window.onerror = function (msg) { send({ e: 'jserror', msg: String(msg) }); };

// La taille du lecteur pilote le choix de qualité de YouTube : un lecteur
// 1280x720 obtient du 720p, un lecteur 3840x2160 rend le 4K envisageable.
// La scène garde ses dimensions réelles et n'est réduite qu'à l'affichage.
function setStage(w, h) {
  stageW = w; stageH = h;
  var stage = document.getElementById('stage');
  stage.style.width = w + 'px';
  stage.style.height = h + 'px';
  fitStage();
}

function fitStage() {
  document.getElementById('stage').style.transform =
    'scale(' + (window.innerWidth / stageW) + ')';
}
window.addEventListener('resize', fitStage);

function onYouTubeIframeAPIReady() { send({ e: 'ready' }); }

// Reconstruit un lecteur NEUF pour chaque qualité. Réutiliser le même lecteur
// laissait l'algorithme adaptatif de YouTube conserver son estimation de
// bande passante d'un palier à l'autre : après un palier en 4K il restait
// haut, et inversement. Les paliers se contaminaient, d'où des résultats
// différents d'un test à l'autre.
function buildLevel(q, w, h) {
  if (player && player.destroy) { try { player.destroy(); } catch (e) {} }
  player = null;
  document.getElementById('stage').innerHTML = '<div id="player"></div>';
  setStage(w, h);

  startupMs = -1; bufferMs = 0; bufferStart = 0; rebuffers = 0;
  started = false; qSegments = []; curQ = null; curQStart = 0;

  player = new YT.Player('player', {
    width: String(w),
    height: String(h),
    videoId: '$STREAMING_YOUTUBE_VIDEO_ID',
    playerVars: {
      autoplay: 0, controls: 0, disablekb: 1, fs: 0,
      modestbranding: 1, playsinline: 1, rel: 0, iv_load_policy: 3,
      enablejsapi: 1, origin: '$origin', vq: q
    },
    events: {
      onReady: function () { send({ e: 'levelready' }); },
      onStateChange: onState,
      onPlaybackQualityChange: function (ev) { markQuality(ev.data); },
      onError: function (ev) { send({ e: 'error', code: ev.data }); }
    }
  });
}

function markQuality(q) {
  var now = Date.now();
  if (curQ !== null) {
    var ms = now - curQStart;
    for (var i = 0; i < qSegments.length; i++) {
      if (qSegments[i].q === curQ) { qSegments[i].ms += ms; curQ = null; break; }
    }
    if (curQ !== null) qSegments.push({ q: curQ, ms: ms });
  }
  curQ = q; curQStart = now;
}

// Qualité ayant duré le plus longtemps sur la fenêtre mesurée.
function dominantQuality() {
  var best = null;
  for (var i = 0; i < qSegments.length; i++) {
    if (!best || qSegments[i].ms > best.ms) best = qSegments[i];
  }
  return best ? best.q : 'unknown';
}

function onState(ev) {
  var s = ev.data;
  if (s === YT.PlayerState.PLAYING) {
    if (startupMs < 0) {
      startupMs = Date.now() - t0;
      started = true;
      try { markQuality(player.getPlaybackQuality()); } catch (e) {}
      send({ e: 'start', startupMs: startupMs });
    }
    // Sortie de mise en tampon : on referme le chrono.
    if (bufferStart > 0) { bufferMs += Date.now() - bufferStart; bufferStart = 0; }
  } else if (s === YT.PlayerState.BUFFERING) {
    // Le buffering d'amorçage fait partie du « chargement initial », pas des
    // interruptions : on ne compte que ce qui survient après la 1re image.
    if (started && bufferStart === 0) { bufferStart = Date.now(); rebuffers++; }
  }
}

function startLevel(q) {
  t0 = Date.now();
  try { player.setPlaybackQualityRange(q, q); } catch (e) {}
  try { player.setPlaybackQuality(q); } catch (e) {}
  player.playVideo();
}

function stopLevel() {
  if (!player) { send({ e: 'level', q: 'unknown', segments: 0 }); return; }
  if (bufferStart > 0) { bufferMs += Date.now() - bufferStart; bufferStart = 0; }
  markQuality(null); // referme le segment en cours

  var avail = '';
  try { avail = player.getAvailableQualityLevels().join(','); } catch (e) {}
  try { player.pauseVideo(); } catch (e) {}

  send({
    e: 'level', startupMs: startupMs < 0 ? 0 : startupMs,
    bufferMs: bufferMs, rebuffers: rebuffers,
    q: dominantQuality(), segments: qSegments.length, avail: avail
  });
}
</script>
<script src="https://www.youtube.com/iframe_api"></script>
</body>
</html>
''';
}

/// Sert la page hôte du lecteur sur la boucle locale, le temps du test.
///
/// L'unique raison d'être de ce serveur est de donner à la page une **origine
/// HTTP réelle** : l'IFrame Player API la vérifie avant d'initialiser le
/// lecteur, et rejette les pages injectées sans origine.
class _PlayerHost {
  HttpServer? _server;

  /// Démarre le serveur et retourne l'URL à charger. [builder] reçoit
  /// l'origine effective, à recopier dans le playerVar `origin`.
  Future<Uri> start(String Function(String origin) builder) async {
    // Port 0 : le système en attribue un libre, ce qui évite tout conflit
    // avec une autre application.
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;

    final origin = 'http://127.0.0.1:${server.port}';
    final html = builder(origin);

    server.listen((request) async {
      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.html
        ..headers.set('Cache-Control', 'no-store')
        ..write(html);
      await request.response.close();
    });

    return Uri.parse('$origin/');
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }
}
