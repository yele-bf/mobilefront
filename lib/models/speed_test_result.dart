import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

import '../services/streaming_test_service.dart';

part 'speed_test_result.g.dart';

@HiveType(typeId: 0)
class SpeedTestResult extends HiveObject {
  @HiveField(0)
  late String id;

  @HiveField(1)
  late DateTime timestamp;

  @HiveField(2)
  late double downloadSpeed; // Mbps

  @HiveField(3)
  late double uploadSpeed; // Mbps

  @HiveField(4)
  late double ping; // ms

  @HiveField(5)
  late double jitter; // ms

  @HiveField(6)
  late String server;

  @HiveField(7)
  late String? clientIp;

  @HiveField(8)
  late String? networkType; // WiFi, 4G, 5G

  @HiveField(9)
  late String? operator; // FAI de connexion (déduit de l'IP : WiFi ou data)

  @HiveField(10)
  late double? latitude;

  @HiveField(11)
  late double? longitude;

  @HiveField(12)
  late String? location; // Ville, Pays

  @HiveField(13)
  late String? deviceModel;

  @HiveField(14)
  late String? osVersion;

  // @HiveField(15) — ancien `batteryLevel`, retiré. Index réservé, ne pas réutiliser.

  @HiveField(16)
  late String? imagePath; // Chemin de l'image résultat

  @HiveField(17)
  late String? testLog;

  @HiveField(18)
  late bool isUploaded; // Indique si envoyé au serveur

  @HiveField(19)
  late int? qoeRating; // Note globale 1-5 étoiles

  @HiveField(20)
  late String? qoeUsage; // Usage principal (streaming, jeux...)

  @HiveField(21)
  late String? qoeSatisfaction; // Commentaire de satisfaction

  // ── Test de streaming vidéo (null = test non effectué) ──
  @HiveField(22)
  int? streamingStartupMs; // Délai avant le premier frame

  @HiveField(23)
  int? streamingRebufferCount; // Nombre d'interruptions

  @HiveField(24)
  double? streamingRebufferRatio; // Part du temps en mise en tampon (0-1)

  @HiveField(25)
  String? streamingMaxResolution; // 360p / 480p / 720p / 1080p

  @HiveField(26)
  double? streamingScore; // Score 0-100

  // ── Test de navigation web (null = test non effectué) ──
  @HiveField(27)
  double? browsingAvgLoadMs; // Temps de chargement moyen

  @HiveField(28)
  double? browsingSuccessRate; // Pages chargées en < 10 s (0-1)

  @HiveField(29)
  int? browsingPagesTested;

  @HiveField(30)
  double? browsingScore; // Score 0-100

  // ── Réseau mobile (SIM), distinct du FAI de connexion ──
  @HiveField(31)
  String? simOperator; // Opérateur de la SIM (Android ; null/n.d. sur iOS 16+)

  @HiveField(32)
  String? cellularTech; // Techno radio mobile : 2G/3G/4G/5G (même en WiFi)

  // Détail du streaming par qualité (720p/1080p/2160p), sérialisé en JSON.
  // Un champ unique plutôt que 6 champs × 3 qualités : le tableau évolue avec
  // la liste des qualités testées, sans réserver d'index Hive à chaque ajout.
  @HiveField(33)
  String? streamingQualitiesJson;

  // ── IMP-01 : données consommées pendant le test ──
  @HiveField(34)
  int? dataUsedKiB; // Total rx + tx du test, en kibioctets (-1 = non mesuré)

  SpeedTestResult({
    String? id,
    DateTime? timestamp,
    required this.downloadSpeed,
    required this.uploadSpeed,
    required this.ping,
    required this.jitter,
    required this.server,
    this.clientIp,
    this.networkType,
    this.operator,
    this.latitude,
    this.longitude,
    this.location,
    this.deviceModel,
    this.osVersion,
    this.imagePath,
    this.testLog,
    this.isUploaded = false,
    this.qoeRating,
    this.qoeUsage,
    this.qoeSatisfaction,
    this.streamingStartupMs,
    this.streamingRebufferCount,
    this.streamingRebufferRatio,
    this.streamingMaxResolution,
    this.streamingScore,
    this.browsingAvgLoadMs,
    this.browsingSuccessRate,
    this.browsingPagesTested,
    this.browsingScore,
    this.simOperator,
    this.cellularTech,
    this.streamingQualitiesJson,
    this.dataUsedKiB,
  }) {
    this.id = id ?? const Uuid().v4();
    this.timestamp = timestamp ?? DateTime.now();
  }

  // Convertir en JSON pour l'API
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'timestamp': timestamp.toIso8601String(),
      'downloadSpeed': downloadSpeed,
      'uploadSpeed': uploadSpeed,
      'ping': ping,
      'jitter': jitter,
      'server': server,
      'clientIp': clientIp,
      'networkType': networkType,
      'operator': operator,
      'latitude': latitude,
      'longitude': longitude,
      'location': location,
      'deviceModel': deviceModel,
      'osVersion': osVersion,
      'simOperator': simOperator,
      'cellularTech': cellularTech,
      'testLog': testLog,
      'qoeRating': qoeRating,
      'qoeUsage': qoeUsage,
      'qoeSatisfaction': qoeSatisfaction,
      'streamingStartupMs': streamingStartupMs,
      'streamingRebufferCount': streamingRebufferCount,
      'streamingRebufferRatio': streamingRebufferRatio,
      'streamingMaxResolution': streamingMaxResolution,
      'streamingScore': streamingScore,
      'streamingQualities': streamingQualitiesJson,
      'dataUsedKiB': dataUsedKiB,
      'browsingAvgLoadMs': browsingAvgLoadMs,
      'browsingSuccessRate': browsingSuccessRate,
      'browsingPagesTested': browsingPagesTested,
      'browsingScore': browsingScore,
    };
  }

  /// Vrai si le test de streaming a été effectué
  bool get hasStreamingTest => streamingScore != null && streamingScore! > 0;

  /// Détail par qualité (720p/1080p/2160p). Liste vide pour les résultats
  /// enregistrés avant l'ajout du test YouTube.
  List<StreamingQualityResult> get streamingQualities =>
      StreamingTestResult.decodeQualities(streamingQualitiesJson);

  /// Raison pour laquelle le test de streaming n'a rien mesuré, s'il a échoué.
  String? get streamingError =>
      StreamingTestResult.decodeError(streamingQualitiesJson);

  /// Vrai si le test de navigation web a été effectué
  bool get hasBrowsingTest => browsingScore != null && browsingScore! > 0;

  // Convertir depuis JSON
  factory SpeedTestResult.fromJson(Map<String, dynamic> json) {
    double readDouble(List<String> keys, {double fallback = 0}) {
      for (final key in keys) {
        final value = json[key];
        if (value is num) return value.toDouble();
        if (value is String) return double.tryParse(value) ?? fallback;
      }
      return fallback;
    }

    int? readInt(List<String> keys) {
      for (final key in keys) {
        final value = json[key];
        if (value is int) return value;
        if (value is num) return value.toInt();
        if (value is String) return int.tryParse(value);
      }
      return null;
    }

    DateTime? readTimestamp() {
      final value = json['timestamp']?.toString();
      if (value == null || value.isEmpty) return null;
      return DateTime.tryParse(value) ??
          DateTime.tryParse(value.replaceFirst(' ', 'T'));
    }

    return SpeedTestResult(
      id: (json['id'] ?? json['testId'])?.toString(),
      timestamp: readTimestamp(),
      downloadSpeed: readDouble(['downloadSpeed', 'download', 'dl']),
      uploadSpeed: readDouble(['uploadSpeed', 'upload', 'ul']),
      ping: readDouble(['ping']),
      jitter: readDouble(['jitter']),
      server: (json['server'] ?? 'Render.com').toString(),
      clientIp: (json['clientIp'] ?? json['ip'])?.toString(),
      networkType: json['networkType']?.toString(),
      operator: (json['operator'] ?? json['ispinfo'])?.toString(),
      latitude: readDouble(['latitude'], fallback: double.nan).isNaN
          ? null
          : readDouble(['latitude']),
      longitude: readDouble(['longitude'], fallback: double.nan).isNaN
          ? null
          : readDouble(['longitude']),
      location: json['location']?.toString(),
      deviceModel: json['deviceModel']?.toString(),
      osVersion: json['osVersion']?.toString(),
      simOperator: json['simOperator']?.toString(),
      cellularTech: json['cellularTech']?.toString(),
      streamingQualitiesJson: json['streamingQualities'] as String?,
      dataUsedKiB: readInt(['dataUsedKiB']),
      imagePath: json['imagePath'] as String?,
      testLog: json['testLog'] as String?,
      isUploaded: json['isUploaded'] as bool? ?? false,
      qoeRating: readInt(['qoeRating']),
      qoeUsage: json['qoeUsage']?.toString(),
      qoeSatisfaction: json['qoeSatisfaction']?.toString(),
    );
  }

  // Calculer la moyenne des 3 derniers tests
  static double? getAverageSpeed(List<SpeedTestResult> results) {
    if (results.isEmpty) return null;
    final last3 =
        results.length > 3 ? results.sublist(results.length - 3) : results;
    final sum = last3.fold<double>(0, (acc, r) => acc + r.downloadSpeed);
    return sum / last3.length;
  }

  // Comparer avec la moyenne nationale (exemple)
  String getSpeedRating() {
    if (downloadSpeed > 100) return 'Excellent';
    if (downloadSpeed > 50) return 'Très bon';
    if (downloadSpeed > 20) return 'Bon';
    if (downloadSpeed > 10) return 'Moyen';
    return 'Faible';
  }
}
