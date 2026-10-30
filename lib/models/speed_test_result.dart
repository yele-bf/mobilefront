import 'dart:convert';

import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

import '../constants/config.dart';
import '../services/streaming_test_service.dart';
import '../services/yele_scoring_engine.dart';

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

  // ── IMP-03 : compte connecté au moment du test, null si anonyme ──
  // Index 59 : 52 est réservé à IMP-07 et 53 à 58 à ISS-06.
  @HiveField(59)
  String? accountId;

  @HiveField(35)
  int? simSlot; // Emplacement 0-indexé de la SIM data active (ISS-02)

  // ── Métriques de signal au moment du test (Android ; null = non mesuré) ──
  // Le champ 35 est réservé à simSlot (ISS-02) : les nouveaux champs
  // commencent à 36 et ne renumérotent jamais un champ existant.
  @HiveField(36)
  int? signalDbm; // Puissance générique toutes technos (dBm)

  @HiveField(37)
  int? signalRsrp; // RSRP LTE/4G (dBm)

  @HiveField(38)
  int? signalRsrq; // RSRQ LTE/4G (dB)

  @HiveField(39)
  int? signalNrRsrp; // SS-RSRP 5G SA (dBm) ; null en 5G NSA (ancre LTE)

  @HiveField(40)
  int? signalNrRsrq; // SS-RSRQ 5G SA (dB)

  @HiveField(41)
  int? wifiRssi; // RSSI du Wi-Fi associé (dBm), null en données mobiles

  // ── IMP-12 : score global ouvert (yele-open-1.0.0) ──
  // Null = résultat antérieur au scoring : aucune version ni aucun score ne
  // doit être rétro-attribué à un enregistrement qui ne les a jamais portés.
  @HiveField(44)
  String? scoringVersion; // ex. 'yele-open-1.0.0'

  @HiveField(45)
  double? scoreDownload; // points, non plafonné

  @HiveField(46)
  double? scoreUpload; // points, non plafonné

  @HiveField(47)
  double? scorePingJitter; // points, plafond 15 000

  @HiveField(48)
  double? scoreBrowsing; // points, plafond 17 500

  @HiveField(49)
  double? scoreStreaming; // points, plafond 17 500

  @HiveField(50)
  double? scoreGlobal; // somme des cinq, null si incomplet

  @HiveField(51)
  String? scoringStatusesJson; // JSON {composante: statut}

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
    this.simSlot,
    this.accountId,
    this.signalDbm,
    this.signalRsrp,
    this.signalRsrq,
    this.signalNrRsrp,
    this.signalNrRsrq,
    this.wifiRssi,
    this.scoringVersion,
    this.scoreDownload,
    this.scoreUpload,
    this.scorePingJitter,
    this.scoreBrowsing,
    this.scoreStreaming,
    this.scoreGlobal,
    this.scoringStatusesJson,
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
      'simSlot': simSlot,
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
      'signalDbm': signalDbm,
      'signalRsrp': signalRsrp,
      'signalRsrq': signalRsrq,
      'signalNrRsrp': signalNrRsrp,
      'signalNrRsrq': signalNrRsrq,
      'wifiRssi': wifiRssi,
      // IMP-12 : champs additionnels, ignorés par un backend plus ancien.
      'scoringVersion': scoringVersion,
      'scoreDownload': scoreDownload,
      'scoreUpload': scoreUpload,
      'scorePingJitter': scorePingJitter,
      'scoreBrowsing': scoreBrowsing,
      'scoreStreaming': scoreStreaming,
      'scoreGlobal': scoreGlobal,
      'scoringStatuses': scoringStatusesJson,
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

  // ── IMP-12 : score global ouvert ──

  /// Vrai si ce résultat porte le scoring ouvert et un score global complet.
  bool get hasOpenScore => scoringVersion != null && scoreGlobal != null;

  /// Indice 0-100 du score global, dérivé de la somme de référence 75 000.
  ///
  /// Le score ouvert est exprimé en points et n'est pas plafonné ; cet indice
  /// est la seule valeur 0-100, identique dans l'app et l'historique. Il n'est
  /// calculé que sur un score global complet (jamais sur un sous-total).
  double? get scoreGlobalOn100 {
    final s = scoreGlobal;
    if (s == null || !s.isFinite || s < 0) return null;
    final v = s / YeleScoringEngine.referenceTotal * 100;
    return v > 100 ? 100 : v;
  }

  /// Somme des composantes réellement mesurées — jamais complétée par des
  /// zéros. Null si aucune composante n'est disponible.
  double? get scoreMeasuredSubtotal {
    final parts = <double>[
      ?scoreDownload,
      ?scoreUpload,
      ?scorePingJitter,
      ?scoreBrowsing,
      ?scoreStreaming,
    ];
    if (parts.isEmpty) return null;
    return parts.fold<double>(0, (a, b) => a + b);
  }

  /// Indice 0-100 du sous-total mesuré (voir [scoreMeasuredSubtotal]).
  /// À n'afficher qu'accompagné d'une mention explicite : ce n'est pas le
  /// score global, qui exige les cinq composantes complètes.
  double? get scoreMeasuredOn100 {
    final s = scoreMeasuredSubtotal;
    if (s == null) return null;
    final v = s / YeleScoringEngine.referenceTotal * 100;
    return v > 100 ? 100 : v;
  }

  /// Statuts des composantes du scoring ouvert ({composante: statut}).
  Map<String, String> get scoringStatuses {
    final raw = scoringStatusesJson;
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      return decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
    } on FormatException {
      return const {};
    }
  }

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

    // Lit un double optionnel : absent, illisible ou NaN → null (jamais 0,
    // pour ne pas confondre absence de mesure et mesure nulle).
    double? readOptionalDouble(List<String> keys) {
      for (final key in keys) {
        final value = json[key];
        if (value is num) {
          final d = value.toDouble();
          return d.isNaN ? null : d;
        }
        if (value is String) {
          final d = double.tryParse(value);
          if (d != null && !d.isNaN) return d;
        }
      }
      return null;
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
      server: (json['server'] ?? serverDisplayName).toString(),
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
      simSlot: readInt(['simSlot', 'dataSimSlot']),
      streamingQualitiesJson: json['streamingQualities'] as String?,
      dataUsedKiB: readInt(['dataUsedKiB']),
      signalDbm: readInt(['signalDbm']),
      signalRsrp: readInt(['signalRsrp']),
      signalRsrq: readInt(['signalRsrq']),
      signalNrRsrp: readInt(['signalNrRsrp']),
      signalNrRsrq: readInt(['signalNrRsrq']),
      wifiRssi: readInt(['wifiRssi']),
      // IMP-12 : lecture tolérante (absent = ancien résultat, rien n'est
      // recalculé et aucune version de scoring n'est fabriquée).
      scoringVersion: json['scoringVersion']?.toString(),
      scoreDownload: readOptionalDouble(['scoreDownload']),
      scoreUpload: readOptionalDouble(['scoreUpload']),
      scorePingJitter: readOptionalDouble(['scorePingJitter']),
      scoreBrowsing: readOptionalDouble(['scoreBrowsing']),
      scoreStreaming: readOptionalDouble(['scoreStreaming']),
      scoreGlobal: readOptionalDouble(['scoreGlobal']),
      scoringStatusesJson: json['scoringStatuses']?.toString(),
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
