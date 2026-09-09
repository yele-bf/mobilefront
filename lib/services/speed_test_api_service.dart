import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../constants/config.dart';
import '../models/speed_test_result.dart';
import '../models/test_selection.dart';
import 'browsing_test_service.dart';
import 'device_identity_service.dart';
import 'streaming_test_service.dart';
import 'traffic_stats_service.dart';

enum SpeedTestPhase {
  initializing,
  download,
  ping,
  upload,
  streaming,
  browsing,
  telemetry,
  completed,
  failed,
}

class SpeedTestProgress {
  final SpeedTestPhase phase;
  final String message;
  final double? downloadSpeed;
  final double? uploadSpeed;
  final double? ping;
  final double? jitter;

  /// Avancement de la phase en cours, de 0 à 1. Alimente le pourcentage
  /// affiché sous la jauge pendant la mesure.
  final double phaseProgress;

  const SpeedTestProgress({
    required this.phase,
    required this.message,
    this.downloadSpeed,
    this.uploadSpeed,
    this.ping,
    this.jitter,
    this.phaseProgress = 0,
  });

  /// Index de la phase parmi les phases réellement exécutées, selon la
  /// sélection de tests (les phases non sélectionnées sont sautées).
  int phaseIndexFor(TestSelection selection) {
    int index;
    switch (phase) {
      case SpeedTestPhase.initializing:
      case SpeedTestPhase.failed:
        return 0;
      case SpeedTestPhase.download:
        return 1;
      case SpeedTestPhase.upload:
        return 2;
      case SpeedTestPhase.ping:
        return 3;
      case SpeedTestPhase.streaming:
        return 4;
      case SpeedTestPhase.browsing:
        index = 4 + (selection.streaming ? 1 : 0);
        return index;
      case SpeedTestPhase.telemetry:
        index = 4 +
            (selection.streaming ? 1 : 0) +
            (selection.browsing ? 1 : 0);
        return index;
      case SpeedTestPhase.completed:
        index = 5 +
            (selection.streaming ? 1 : 0) +
            (selection.browsing ? 1 : 0);
        return index;
    }
  }

  /// Compatibilité : index sans tests optionnels.
  int get phaseIndex => phaseIndexFor(const TestSelection());
}

class SpeedTransferMeasurement {
  final double mbps;
  final int bytes;
  final Duration duration;

  const SpeedTransferMeasurement({
    required this.mbps,
    required this.bytes,
    required this.duration,
  });
}

class LatencyMeasurement {
  final double ping;
  final double jitter;

  const LatencyMeasurement({
    required this.ping,
    required this.jitter,
  });
}

typedef SpeedTestProgressCallback = void Function(SpeedTestProgress progress);

/// Débit en mégabits par seconde pour [bytes] transférés en [duration].
double _mbps(int bytes, Duration duration) {
  final seconds =
      max(duration.inMicroseconds / Duration.microsecondsPerSecond, 0.001);
  return (bytes * 8) / seconds / 1000000;
}

/// État d'une phase de transfert à durée fixe (download ou upload).
///
/// Agrège les octets remontés par les workers parallèles et produit deux
/// chiffres distincts :
///  - le **débit instantané**, calculé sur une fenêtre glissante de quelques
///    secondes — c'est lui qui anime la jauge, il doit réagir vite ;
///  - le **débit final**, calculé sur tout le transfert *sauf* la montée en
///    charge initiale, où TCP n'a pas encore atteint son régime.
class _TransferRun {
  final Duration duration;
  final void Function(double mbps, double progress)? onLive;

  final Stopwatch _watch = Stopwatch()..start();

  /// Coupe les transferts encore en vol à l'échéance. Sans cela, un bloc
  /// commencé juste avant la fin s'achèverait quand même : sur un lien mobile
  /// lent, un envoi de 2 Mo déborderait de plusieurs dizaines de secondes.
  final CancelToken cancelToken = CancelToken();
  late final Timer _deadline;

  /// Fenêtre glissante : (instant du relevé en ms, octets reçus).
  final Queue<({int ms, int bytes})> _window = Queue();
  int _windowBytes = 0;

  int _totalBytes = 0;
  int _warmupBytes = 0; // octets déjà transférés à la fin de la montée en charge
  bool _warmupDone = false;
  int _lastEmitMs = 0;

  _TransferRun({required this.duration, this.onLive}) {
    _deadline = Timer(duration, () {
      if (!cancelToken.isCancelled) cancelToken.cancel('phase terminée');
    });
  }

  bool isExpired() => _watch.elapsed >= duration;

  void addBytes(int delta) {
    final nowMs = _watch.elapsedMilliseconds;
    _totalBytes += delta;

    if (!_warmupDone && nowMs >= SPEED_WARMUP_MS) {
      _warmupDone = true;
      _warmupBytes = _totalBytes;
    }

    _window.add((ms: nowMs, bytes: delta));
    _windowBytes += delta;
    while (_window.isNotEmpty && nowMs - _window.first.ms > SPEED_LIVE_WINDOW_MS) {
      _windowBytes -= _window.removeFirst().bytes;
    }

    if (onLive == null) return;
    // ~8 émissions/s : assez pour une jauge fluide, sans noyer l'UI.
    if (nowMs - _lastEmitMs < 120) return;
    _lastEmitMs = nowMs;
    onLive!(
      _liveMbps(nowMs),
      (nowMs / duration.inMilliseconds).clamp(0.0, 1.0),
    );
  }

  /// Débit sur la fenêtre glissante. Au tout début la fenêtre est plus courte
  /// que sa taille nominale : on divise par sa durée réelle, sinon les
  /// premières secondes afficheraient un débit artificiellement bas.
  double _liveMbps(int nowMs) {
    if (_window.isEmpty) return 0;
    final spanMs = (nowMs - _window.first.ms).clamp(200, SPEED_LIVE_WINDOW_MS);
    return _mbps(_windowBytes, Duration(milliseconds: spanMs));
  }

  SpeedTransferMeasurement finish() {
    _watch.stop();
    _deadline.cancel();
    final elapsed = _watch.elapsed;

    // Sur un transfert trop court pour sortir de la montée en charge, on garde
    // tout : mieux vaut une mesure imparfaite que pas de mesure.
    final bytes = _warmupDone ? _totalBytes - _warmupBytes : _totalBytes;
    final window = _warmupDone
        ? elapsed - const Duration(milliseconds: SPEED_WARMUP_MS)
        : elapsed;

    return SpeedTransferMeasurement(
      mbps: _mbps(bytes, window),
      bytes: _totalBytes,
      duration: elapsed,
    );
  }
}

class SpeedTestApiService {
  final logger = Logger();
  late final Dio _dio;
  final String baseUrl = API_BASE_URL;

  SpeedTestApiService() {
    _dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 300),
        sendTimeout: const Duration(seconds: 300),
        contentType: 'application/json',
        validateStatus: (status) =>
            status != null && status >= 200 && status < 300,
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          logger.i('Request: ${options.method} ${options.path}');
          return handler.next(options);
        },
        onError: (error, handler) {
          logger.e('DIO Error: ${error.message}');
          return handler.next(error);
        },
      ),
    );
  }

  Future<SpeedTestResult> runSpeedTest({
    double? latitude,
    double? longitude,
    String? location,
    String? networkType,
    String? operator,
    String? simOperator,
    String? cellularTech,
    String? deviceModel,
    String? osVersion,
    TestSelection selection = const TestSelection(),
    SpeedTestProgressCallback? onProgress,
    StreamingControllerCallback? onStreamingController,
    StreamingRowsCallback? onStreamingRows,
    BrowsingControllerCallback? onBrowsingController,
    // Permet à l'UI de recueillir la note QoE et de l'attacher au résultat
    // AVANT l'envoi au serveur, pour qu'elle soit incluse dans la télémétrie.
    Future<void> Function(SpeedTestResult result)? onCollectQoe,
    // Si faux, le résultat est retourné sans QoE ni envoi : l'UI peut alors
    // afficher le bilan d'abord, puis déclencher QoE + envoi (uploadTestResult).
    bool autoUpload = true,
  }) async {
    String? ipInfo; // chaîne résumée ("IP - FAI, pays") pour l'affichage
    String? ipRawJson; // JSON complet de /getIP : envoyé au serveur (city/country)

    try {
      onProgress?.call(
        const SpeedTestProgress(
          phase: SpeedTestPhase.initializing,
          message: 'Initialisation du test',
        ),
      );

      final ipDetails = await getPublicIpInfo();
      ipInfo = ipDetails?.processedString;
      ipRawJson = ipDetails?.rawJson;

      // IMP-01 : relevé des compteurs data juste avant la 1re phase réseau.
      final dataUsage = DataUsageCapture();
      await dataUsage.start();

      // Débit : exécuté uniquement si demandé (tests indépendants).
      // Ordre : download, upload, puis latence.
      double dlMbps = 0, ulMbps = 0, pingMs = 0, jitterMs = 0;
      if (selection.speed) {
        onProgress?.call(const SpeedTestProgress(
          phase: SpeedTestPhase.download,
          message: 'Mesure du téléchargement',
        ));
        final download = await measureDownloadSpeed(
          // Débit instantané pendant le transfert → la jauge bouge en direct.
          onLive: (mbps, progress) => onProgress?.call(SpeedTestProgress(
            phase: SpeedTestPhase.download,
            message: 'Mesure du téléchargement',
            downloadSpeed: mbps,
            phaseProgress: progress,
          )),
        );
        dlMbps = download.mbps;
        onProgress?.call(SpeedTestProgress(
          phase: SpeedTestPhase.download,
          message: 'Téléchargement mesuré',
          downloadSpeed: dlMbps,
        ));

        onProgress?.call(SpeedTestProgress(
          phase: SpeedTestPhase.upload,
          message: 'Mesure du chargement',
          downloadSpeed: dlMbps,
        ));
        final upload = await measureUploadSpeed(
          onLive: (mbps, progress) => onProgress?.call(SpeedTestProgress(
            phase: SpeedTestPhase.upload,
            message: 'Mesure du chargement',
            downloadSpeed: dlMbps,
            uploadSpeed: mbps,
            phaseProgress: progress,
          )),
        );
        ulMbps = upload.mbps;

        // La latence se mesure en dernier, donc juste après avoir saturé le
        // lien. Les files d'attente des équipements réseau mettent un instant
        // à se vider (bufferbloat) : sans cette pause, on mesurerait le
        // reliquat du transfert plutôt que la latence au repos.
        await Future.delayed(
            const Duration(milliseconds: LATENCY_SETTLE_MS));

        onProgress?.call(SpeedTestProgress(
          phase: SpeedTestPhase.ping,
          message: 'Mesure de la latence',
          downloadSpeed: dlMbps,
          uploadSpeed: ulMbps,
        ));
        final latency = await measureLatency(
          onSample: (ping, jitter, progress) =>
              onProgress?.call(SpeedTestProgress(
            phase: SpeedTestPhase.ping,
            message: 'Mesure de la latence',
            downloadSpeed: dlMbps,
            uploadSpeed: ulMbps,
            ping: ping,
            jitter: jitter,
            phaseProgress: progress,
          )),
        );
        pingMs = latency.ping;
        jitterMs = latency.jitter;
        onProgress?.call(SpeedTestProgress(
          phase: SpeedTestPhase.ping,
          message: 'Latence mesurée',
          downloadSpeed: dlMbps,
          uploadSpeed: ulMbps,
          ping: pingMs,
          jitter: jitterMs,
        ));
      }

      // ── Tests optionnels : streaming vidéo et navigation web ──────────────
      StreamingTestResult? streaming;
      if (selection.streaming) {
        onProgress?.call(
          SpeedTestProgress(
            phase: SpeedTestPhase.streaming,
            message: 'Test de streaming vidéo',
            downloadSpeed: dlMbps,
            uploadSpeed: ulMbps,
            ping: pingMs,
            jitter: jitterMs,
          ),
        );
        try {
          streaming = await StreamingTestService().runTest(
            onController: onStreamingController,
            onRows: onStreamingRows,
            onProgress: (progress, message) => onProgress?.call(
              SpeedTestProgress(
                phase: SpeedTestPhase.streaming,
                message: message,
                downloadSpeed: dlMbps,
                uploadSpeed: ulMbps,
                ping: pingMs,
                jitter: jitterMs,
              ),
            ),
          );
        } catch (e) {
          logger.e('Test streaming échoué: $e');
        }
      }

      BrowsingTestResult? browsing;
      if (selection.browsing) {
        onProgress?.call(
          SpeedTestProgress(
            phase: SpeedTestPhase.browsing,
            message: 'Test de navigation web',
            downloadSpeed: dlMbps,
            uploadSpeed: ulMbps,
            ping: pingMs,
            jitter: jitterMs,
          ),
        );
        try {
          browsing = await BrowsingTestService().runTest(
            onController: onBrowsingController,
            onProgress: (progress, message) => onProgress?.call(
              SpeedTestProgress(
                phase: SpeedTestPhase.browsing,
                message: message,
                downloadSpeed: dlMbps,
                uploadSpeed: ulMbps,
                ping: pingMs,
                jitter: jitterMs,
              ),
            ),
          );
        } catch (e) {
          logger.e('Test navigation échoué: $e');
        }
      }

      final result = SpeedTestResult(
        downloadSpeed: dlMbps,
        uploadSpeed: ulMbps,
        ping: pingMs,
        jitter: jitterMs,
        server: 'Render.com',
        clientIp: _extractIp(ipInfo),
        networkType: networkType,
        operator: operator ?? _extractOperator(ipInfo),
        latitude: latitude,
        longitude: longitude,
        location: location ?? _extractLocation(ipInfo),
        deviceModel: deviceModel,
        osVersion: osVersion,
        simOperator: simOperator,
        cellularTech: cellularTech,
        // JSON complet -> le backend en extrait city/country/coordonnées IP.
        testLog: ipRawJson ?? ipInfo,
        streamingStartupMs: streaming?.startupMs,
        streamingRebufferCount: streaming?.rebufferCount,
        streamingRebufferRatio: streaming?.rebufferRatio,
        streamingMaxResolution: streaming?.maxResolution,
        streamingScore: streaming?.score,
        streamingQualitiesJson: streaming?.encodeQualities(),
        browsingAvgLoadMs: browsing?.avgLoadMs,
        browsingSuccessRate: browsing?.successRate,
        browsingPagesTested: browsing?.pagesTested,
        browsingScore: browsing?.score,
        // IMP-01 : volume rx + tx consommé par l'app pendant le test.
        dataUsedKiB: await dataUsage.stopKiB(),
      );

      // Par défaut : QoE puis envoi immédiat. Si autoUpload=false, l'UI gère
      // l'affichage du bilan, le QoE et l'envoi après coup.
      if (autoUpload) {
        if (onCollectQoe != null) {
          await onCollectQoe(result);
        }

        onProgress?.call(
          SpeedTestProgress(
            phase: SpeedTestPhase.telemetry,
            message: 'Envoi des résultats au serveur',
            downloadSpeed: result.downloadSpeed,
            uploadSpeed: result.uploadSpeed,
            ping: result.ping,
            jitter: result.jitter,
          ),
        );

        result.isUploaded = await uploadTestResult(result);
      }

      onProgress?.call(
        SpeedTestProgress(
          phase: SpeedTestPhase.completed,
          message: 'Test terminé',
          downloadSpeed: result.downloadSpeed,
          uploadSpeed: result.uploadSpeed,
          ping: result.ping,
          jitter: result.jitter,
        ),
      );

      return result;
    } catch (e) {
      onProgress?.call(
        SpeedTestProgress(
          phase: SpeedTestPhase.failed,
          message: 'Erreur pendant le test: $e',
        ),
      );
      rethrow;
    }
  }

  // Démarrer un test de vitesse
  // speedtest-go ne démarre pas de job serveur: le client mesure /garbage et /empty.
  Future<Map<String, dynamic>?> startSpeedTest({
    required double latitude,
    required double longitude,
    required String? networkType,
    required String? deviceModel,
    required String? osVersion,
  }) async {
    try {
      final ipResponse = await getPublicIP();
      if (ipResponse != null) {
        logger.i('Test ready, IP: $ipResponse');
        return {
          'testId': DateTime.now().millisecondsSinceEpoch.toString(),
          'status': 'ready',
          'ip': ipResponse,
        };
      }
      return null;
    } on DioException catch (e) {
      logger.e('Erreur init test: ${e.message}');
      _handleDioError(e);
    }
    return null;
  }

  // Récupérer les résultats d'un test en JSON.
  Future<Map<String, dynamic>?> getTestResults(String testId) async {
    try {
      final response = await _dio.get(
        '/results/json',
        queryParameters: {'id': testId},
      );

      if (response.statusCode == 200) {
        logger.i('Résultats reçus pour test: $testId');
        return response.data is Map<String, dynamic>
            ? response.data as Map<String, dynamic>
            : <String, dynamic>{'raw': response.data};
      }
    } on DioException catch (e) {
      logger.e('Erreur récupération résultats: ${e.message}');
      _handleDioError(e);
    }
    return null;
  }

  /// Récupère l'IP publique et les infos ISP.
  ///
  /// Retourne à la fois la chaîne résumée ("IP - FAI, pays"), pour
  /// l'affichage, et le JSON COMPLET de /getIP : c'est lui qu'on envoie au
  /// serveur (champ ispinfo), pour qu'il remplisse city/country et les
  /// coordonnées IP de secours — la chaîne seule ne le permettait pas.
  Future<({String? processedString, String? rawJson})?>
      getPublicIpInfo() async {
    try {
      final response = await _dio.get(
        '/getIP',
        queryParameters: {'isp': 'true'},
      );

      if (response.statusCode == 200) {
        final data = response.data;
        if (data is Map) {
          final rawIspInfo = data['rawIspInfo'];
          final processed = (data['processedString'] ??
                  data['ip'] ??
                  (rawIspInfo is Map ? rawIspInfo['ip'] : null))
              ?.toString();
          logger.i('IP publique récupérée: $processed');
          return (processedString: processed, rawJson: jsonEncode(data));
        }
        final processed = data?.toString();
        logger.i('IP publique récupérée: $processed');
        return (processedString: processed, rawJson: null);
      }
    } on DioException catch (e) {
      logger.e('Erreur récupération IP: ${e.message}');
      _handleDioError(e);
    }
    return null;
  }

  // Compatibilité : ancienne API qui ne retourne que la chaîne résumée.
  Future<String?> getPublicIP() async =>
      (await getPublicIpInfo())?.processedString;

  /// Mesure le débit descendant pendant [duration], en gardant [parallel]
  /// connexions saturées : chaque worker enchaîne les chunks jusqu'à
  /// l'échéance. C'est une mesure à durée fixe, pas à volume fixe — sur un
  /// lien rapide, un volume fixe serait transféré trop vite pour être
  /// représentatif (et pour être visible à l'écran).
  Future<SpeedTransferMeasurement> measureDownloadSpeed({
    int chunkSize = 8,
    int parallel = 4,
    Duration duration = const Duration(seconds: SPEED_PHASE_DURATION_SEC),
    // Débit instantané (Mb/s) et avancement (0-1), émis pendant le transfert.
    void Function(double mbps, double progress)? onLive,
  }) async {
    final run = _TransferRun(duration: duration, onLive: onLive);

    await Future.wait(List.generate(
      parallel,
      (_) => _transferWorker(
        run,
        () => _downloadChunk(
          chunkSize,
          onBytes: run.addBytes,
          shouldStop: run.isExpired,
          cancelToken: run.cancelToken,
        ),
      ),
    ));

    final measurement = run.finish();
    logger.i('Download: ${measurement.mbps.toStringAsFixed(2)} Mbps, '
        'bytes: ${measurement.bytes} en ${measurement.duration.inSeconds}s');
    return measurement;
  }

  /// Mesure le débit montant, même principe que [measureDownloadSpeed].
  Future<SpeedTransferMeasurement> measureUploadSpeed({
    int uploadSize = 2,
    int parallel = 3,
    Duration duration = const Duration(seconds: SPEED_PHASE_DURATION_SEC),
    void Function(double mbps, double progress)? onLive,
  }) async {
    // Buffer alloué directement (rempli de zéros) : évite de générer puis
    // convertir une List<int> de plusieurs millions d'éléments.
    final uploadData = Uint8List(uploadSize * 1024 * 1024);
    final run = _TransferRun(duration: duration, onLive: onLive);

    await Future.wait(List.generate(
      parallel,
      (_) => _transferWorker(
        run,
        () => _uploadChunk(
          uploadData,
          onBytes: run.addBytes,
          cancelToken: run.cancelToken,
        ),
      ),
    ));

    final measurement = run.finish();
    logger.i('Upload: ${measurement.mbps.toStringAsFixed(2)} Mbps, '
        'bytes: ${measurement.bytes} en ${measurement.duration.inSeconds}s');
    return measurement;
  }

  /// Enchaîne les transferts jusqu'à l'échéance de [run].
  ///
  /// Une erreur en fin de course est normale : couper un flux à l'échéance fait
  /// remonter une exception réseau. On ne la propage que si le budget de temps
  /// n'est pas épuisé — auquel cas c'est une vraie panne.
  Future<void> _transferWorker(
    _TransferRun run,
    Future<int> Function() transfer,
  ) async {
    while (!run.isExpired()) {
      try {
        await transfer();
      } catch (e) {
        if (!run.isExpired()) rethrow;
        return;
      }
    }
  }

  Future<LatencyMeasurement> measureLatency({
    int samples = 5,
    // Moyenne/gigue provisoires + avancement, après chaque échantillon.
    void Function(double ping, double jitter, double progress)? onSample,
  }) async {
    final measurements = <double>[];

    for (int i = 0; i < samples; i++) {
      final stopwatch = Stopwatch()..start();
      await _dio.get(
        '/getIP',
        queryParameters: {
          'isp': 'false',
          'r': DateTime.now().microsecondsSinceEpoch,
        },
        options: Options(responseType: ResponseType.plain),
      );
      stopwatch.stop();
      measurements.add(stopwatch.elapsedMicroseconds / 1000);
      onSample?.call(
          _avg(measurements), _jitterOf(measurements), (i + 1) / samples);
    }

    final ping = _avg(measurements);
    final jitter = _jitterOf(measurements);

    logger.i(
        'Ping: ${ping.toStringAsFixed(2)} ms, jitter: ${jitter.toStringAsFixed(2)} ms');
    return LatencyMeasurement(ping: ping, jitter: jitter);
  }

  double _avg(List<double> values) =>
      values.isEmpty ? 0 : values.reduce((a, b) => a + b) / values.length;

  double _jitterOf(List<double> values) => values.length < 2
      ? 0.0
      : List.generate(
            values.length - 1,
            (index) => (values[index + 1] - values[index]).abs(),
          ).reduce((a, b) => a + b) /
          (values.length - 1);

  // Obtenir la liste des serveurs disponibles.
  Future<List<Map<String, dynamic>>?> getServers() async {
    logger.i('Serveur unique: Render.com');
    return [
      {
        'name': 'Render.com Default',
        'url': baseUrl,
        'location': 'Render',
        'sponsor': 'Render Platform',
      }
    ];
  }

  // Envoyer les résultats sauvegardés au serveur via telemetry.
  Future<bool> uploadTestResult(SpeedTestResult result) async {
    try {
      // IMP-13 : UUID d'appareil anonyme et stable, généré localement —
      // aucune donnée privée n'est lue ni transmise.
      final deviceId = await DeviceIdentityService.instance.getUuid();
      final response = await _dio.post(
        '/results/telemetry',
        data: {
          'ispinfo': result.testLog ?? result.location ?? 'Unknown',
          'dl': result.downloadSpeed.toStringAsFixed(2),
          'ul': result.uploadSpeed.toStringAsFixed(2),
          'ping': result.ping.toStringAsFixed(2),
          'jitter': result.jitter.toStringAsFixed(2),
          'log': 'Yélé Mobile Test',
          'extra': jsonEncode({
            // Distingue un test lancé par l'utilisateur d'une relève passive
            // envoyée par le service d'arrière-plan. Sans ce marqueur, les
            // relèves automatiques — bien plus nombreuses et sans utilisateur
            // présent — fausseraient toutes les statistiques et l'entraînement
            // des modèles.
            'type': 'active',
            'operator': result.operator ?? '',
            'networkType': result.networkType ?? '',
            'simOperator': result.simOperator ?? '',
            'cellularTech': result.cellularTech ?? '',
            'deviceModel': result.deviceModel ?? '',
            'deviceId': deviceId,
            // location n'est plus transmis : le serveur le compose depuis
            // city/country extraits du JSON ispinfo (source unique).
            'latitude': result.latitude ?? 0.0,
            'longitude': result.longitude ?? 0.0,
            'qoeRating': result.qoeRating ?? 0,
            'qoeSatisfaction': result.qoeSatisfaction ?? '',
            // Streaming / navigation web : 0 = test non effectué
            'streamingStartupMs': result.streamingStartupMs ?? 0,
            'streamingRebufferCount': result.streamingRebufferCount ?? 0,
            'streamingRebufferRatio': result.streamingRebufferRatio ?? 0.0,
            'streamingMaxResolution': result.streamingMaxResolution ?? '',
            'streamingScore': result.streamingScore ?? 0.0,
            // Détail par qualité (720p/1080p/2160p) : taux de performance,
            // chargement initial, mise en tampon, données consommées.
            'streamingQualities': result.streamingQualitiesJson ?? '',
            'browsingAvgLoadMs': result.browsingAvgLoadMs ?? 0.0,
            'browsingSuccessRate': result.browsingSuccessRate ?? 0.0,
            'browsingPagesTested': result.browsingPagesTested ?? 0,
            'browsingScore': result.browsingScore ?? 0.0,
          }),
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final serverId = _extractTelemetryId(response.data?.toString());
        if (serverId != null) {
          result.id = serverId;
        }
        logger.i('Résultat uploadé: ${result.id}');
        return true;
      }
    } on DioException catch (e) {
      logger.e('Erreur upload résultat: ${e.message}');
      _handleDioError(e);
    }
    return false;
  }

  // speedtest-go ne liste pas l'historique complet côté mobile.
  Future<List<SpeedTestResult>?> getHistory({
    int limit = 50,
    int offset = 0,
  }) async {
    logger.i('Historique géré localement par Hive');
    return null;
  }

  // API de compatibilité: mesure un download et retourne le chronomètre.
  Future<Stopwatch?> downloadTest({
    int chunkSize = 2,
    int parallel = 2,
  }) async {
    try {
      final stopwatch = Stopwatch()..start();
      await Future.wait(
          List.generate(parallel, (_) => _downloadChunk(chunkSize)));
      stopwatch.stop();
      return stopwatch;
    } on DioException catch (e) {
      logger.e('Erreur test download: ${e.message}');
      _handleDioError(e);
    }
    return null;
  }

  // API de compatibilité: mesure un upload et retourne le chronomètre.
  Future<Stopwatch?> uploadTest({
    int uploadSize = 1,
    int parallel = 4,
  }) async {
    try {
      final bytesPerUpload = uploadSize * 1024 * 1024;
      final uploadData = Uint8List.fromList(
        List<int>.generate(bytesPerUpload, (index) => index % 256),
      );
      final stopwatch = Stopwatch()..start();
      await Future.wait(
          List.generate(parallel, (_) => _uploadChunk(uploadData)));
      stopwatch.stop();
      return stopwatch;
    } on DioException catch (e) {
      logger.e('Erreur test upload: ${e.message}');
      _handleDioError(e);
    }
    return null;
  }

  Future<SpeedTestResult?> pollTestResults(String testId) async {
    try {
      int maxAttempts = 60;
      int attempts = 0;

      while (attempts < maxAttempts) {
        final results = await getTestResults(testId);

        if (results != null) {
          if (results['status'] == 'failed') {
            logger.e('Test échoué: $testId');
            return null;
          }

          if (results['status'] == 'completed' ||
              results.containsKey('download') ||
              results.containsKey('downloadSpeed')) {
            return SpeedTestResult.fromJson({
              ...results,
              'id': testId,
              'server': results['server'] ?? 'Render.com',
            });
          }
        }

        await Future.delayed(const Duration(seconds: 5));
        attempts++;
      }

      logger.e('Timeout: polling dépassé pour test $testId');
    } catch (e) {
      logger.e('Erreur polling: $e');
    }
    return null;
  }

  Future<int> _downloadChunk(
    int chunkSize, {
    // Notifie chaque paquet reçu (delta d'octets) pour la jauge en direct.
    void Function(int delta)? onBytes,
    // Interrompt la réception en cours de flux dès que la phase est terminée,
    // sans attendre la fin du chunk (qui peut faire plusieurs mégaoctets).
    bool Function()? shouldStop,
    CancelToken? cancelToken,
  }) async {
    // Sur le web (pas de streaming), Dio fournit la progression cumulée.
    int lastReceived = 0;
    final response = await _dio.get(
      '/garbage',
      queryParameters: {
        'ckSize': chunkSize,
        'r': DateTime.now().microsecondsSinceEpoch,
      },
      cancelToken: cancelToken,
      options: Options(
        responseType: kIsWeb ? ResponseType.bytes : ResponseType.stream,
      ),
      onReceiveProgress: kIsWeb
          ? (received, _) {
              onBytes?.call(received - lastReceived);
              lastReceived = received;
            }
          : null,
    );

    if (response.statusCode != 200) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
      );
    }

    final data = response.data;
    if (data is ResponseBody) {
      int bytes = 0;
      await for (final chunk in data.stream) {
        bytes += chunk.length;
        onBytes?.call(chunk.length);
        if (shouldStop?.call() ?? false) break;
      }
      return bytes;
    }

    if (data is List<int>) {
      return data.length;
    }

    return data?.toString().length ?? 0;
  }

  Future<int> _uploadChunk(
    Uint8List uploadData, {
    // Notifie chaque paquet envoyé (delta d'octets) pour la jauge en direct.
    void Function(int delta)? onBytes,
    CancelToken? cancelToken,
  }) async {
    int lastSent = 0;
    final response = await _dio.post(
      '/empty',
      data: uploadData,
      queryParameters: {'r': DateTime.now().microsecondsSinceEpoch},
      cancelToken: cancelToken,
      options: Options(
        contentType: 'application/octet-stream',
        responseType: ResponseType.plain,
      ),
      onSendProgress: (sent, _) {
        onBytes?.call(sent - lastSent);
        lastSent = sent;
      },
    );

    if (response.statusCode != 200) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
      );
    }

    return uploadData.length;
  }

  String? _extractIp(String? value) {
    if (value == null) return null;
    return RegExp(r'\b(?:\d{1,3}\.){3}\d{1,3}\b').firstMatch(value)?.group(0);
  }

  String? _extractOperator(String? value) {
    if (value == null || !value.contains(' - ')) return null;
    return value.split(' - ').last.split(',').first.trim();
  }

  String? _extractLocation(String? value) {
    // La chaîne résumée ("IP - Opérateur, CC (distance)") ne contient PAS de
    // ville : on n'en extrait que le code pays. Découper sur les virgules
    // produisait des fragments corrompus quand le nom d'opérateur contenait
    // lui-même une virgule (ex. "ONATEL (..., PTT), BF" -> "PTT), BF").
    if (value == null) return null;
    return RegExp(r',\s*([A-Z]{2})\s*\(').firstMatch(value)?.group(1);
  }

  String? _extractTelemetryId(String? value) {
    if (value == null) return null;
    final match = RegExp(r'id\s+([A-Za-z0-9_-]+)').firstMatch(value);
    return match?.group(1);
  }

  void _handleDioError(DioException error) {
    if (error.type == DioExceptionType.connectionTimeout) {
      logger.e('Timeout de connexion');
    } else if (error.type == DioExceptionType.receiveTimeout) {
      logger.e('Timeout de réception');
    } else if (error.type == DioExceptionType.badResponse) {
      logger.e('Erreur serveur: ${error.response?.statusCode}');
    } else if (error.type == DioExceptionType.connectionError) {
      logger.e('Erreur de connexion');
    }
  }
}
