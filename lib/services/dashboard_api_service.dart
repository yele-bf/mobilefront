import 'package:dio/dio.dart';
import 'package:logger/logger.dart';

import '../constants/config.dart';
import '../models/speed_test_result.dart';

/// Un point de couverture agrégé (issu des tests réels stockés en base).
class CoveragePoint {
  final double lat;
  final double lng;
  final String operator;
  final String networkType;
  final double download;

  CoveragePoint({
    required this.lat,
    required this.lng,
    required this.operator,
    required this.networkType,
    required this.download,
  });

  factory CoveragePoint.fromJson(Map<String, dynamic> j) => CoveragePoint(
        lat: (j['lat'] as num?)?.toDouble() ?? 0,
        lng: (j['lng'] as num?)?.toDouble() ?? 0,
        operator: (j['operator'] ?? '').toString(),
        networkType: (j['networkType'] ?? '').toString(),
        download: (j['download'] as num?)?.toDouble() ?? 0,
      );
}

/// IMP-09 — Position d'un résultat dans le baromètre de comparaison.
class BarometerResult {
  /// % de mesures de la base plus lentes que le résultat testé.
  final double downloadPercentile;
  final double uploadPercentile;

  /// % de mesures de la base avec une latence pire (supérieure) au résultat.
  final double pingPercentile;

  /// Nombre de mesures prises en compte (déjà segmentées par connexion).
  final int sampleSize;

  /// Débit descendant moyen de toutes les mesures (Mb/s), 0 si inconnu.
  final double nationalAvgDownload;

  /// IMP-09 — Comparaison aux seuls clients du même opérateur : nom unifié
  /// renvoyé par le serveur (« Orange », « Moov Africa », « Telecel »…),
  /// nombre de mesures, centiles et débit moyen. [operator] est null si
  /// aucun opérateur n'a été transmis.
  final String? operator;
  final int operatorSampleSize;
  final double operatorDownloadPercentile;
  final double operatorUploadPercentile;
  final double operatorPingPercentile;
  final double operatorAvgDownload;

  // IMP-09 v2 — Médianes de la base comparée (affichées sur les barres).
  final double medianDownload;
  final double medianUpload;
  final double medianPing;

  // IMP-09 v2 — Rang du résultat (1 = le plus rapide ; nombre de mesures
  // battues + 1).
  final int downloadRank;
  final int uploadRank;
  final int pingRank;

  // IMP-09 v2 — Scores de streaming et de navigation. Le serveur ne les
  // renvoie que si le testeur a fait l'usage ; 0 sinon.
  final double streamingPercentile;
  final double browsingPercentile;

  // IMP-09 v2 — Sous-groupe opérateur × techno (« 4G »…) : mêmes centiles,
  // calculés seulement si l'échantillon atteint minSubgroupSample.
  final String? operatorTech;
  final int operatorTechSampleSize;
  final double operatorTechDownloadPercentile;
  final double operatorTechUploadPercentile;
  final double operatorTechPingPercentile;

  // IMP-09 v2 — Sous-groupe géographique (~10 km autour du test), même
  // seuil d'échantillon.
  final int zoneSampleSize;
  final double zoneDownloadPercentile;
  final double zoneUploadPercentile;
  final double zonePingPercentile;

  // IMP-09 v2 — Tendance : 5 derniers tests du même appareil, du plus
  // récent au plus ancien (vide si l'appareil est inconnu de la base).
  final List<double> recentDownloads;

  // Segment réellement appliqué par le serveur (« wifi »/« mobile »),
  // confirmé dans la réponse : l'entête n'affiche « mesures Wi-Fi » que si
  // la comparaison a bien été filtrée sur ce segment.
  final String? networkType;

  /// En dessous, le serveur ne calcule pas de centile par opérateur.
  static const minOperatorSample = 5;

  /// En dessous, pas de sous-groupe techno ni de zone (comparaison plus
  /// fine que le groupe opérateur : échantillon plus exigeant).
  static const minSubgroupSample = 10;

  BarometerResult({
    required this.downloadPercentile,
    required this.uploadPercentile,
    required this.pingPercentile,
    required this.sampleSize,
    this.nationalAvgDownload = 0,
    this.operator,
    this.operatorSampleSize = 0,
    this.operatorDownloadPercentile = 0,
    this.operatorUploadPercentile = 0,
    this.operatorPingPercentile = 0,
    this.operatorAvgDownload = 0,
    this.medianDownload = 0,
    this.medianUpload = 0,
    this.medianPing = 0,
    this.downloadRank = 0,
    this.uploadRank = 0,
    this.pingRank = 0,
    this.streamingPercentile = 0,
    this.browsingPercentile = 0,
    this.operatorTech,
    this.operatorTechSampleSize = 0,
    this.operatorTechDownloadPercentile = 0,
    this.operatorTechUploadPercentile = 0,
    this.operatorTechPingPercentile = 0,
    this.zoneSampleSize = 0,
    this.zoneDownloadPercentile = 0,
    this.zoneUploadPercentile = 0,
    this.zonePingPercentile = 0,
    this.recentDownloads = const [],
    this.networkType,
  });

  /// Vrai si la comparaison par opérateur est significative.
  bool get hasOperatorComparison =>
      (operator ?? '').isNotEmpty && operatorSampleSize >= minOperatorSample;

  /// Vrai si le sous-groupe opérateur × techno est significatif.
  bool get hasOperatorTechComparison =>
      (operatorTech ?? '').isNotEmpty &&
      operatorTechSampleSize >= minSubgroupSample;

  /// Vrai si la comparaison de zone est significative.
  bool get hasZoneComparison => zoneSampleSize >= minSubgroupSample;

  /// Vrai si une tendance personnelle est affichable (au moins deux tests
  /// du même appareil dans la base).
  bool get hasTrend => recentDownloads.length >= 2;

  factory BarometerResult.fromJson(Map<String, dynamic> j) {
    double d(String k) => (j[k] as num?)?.toDouble() ?? 0;
    int i(String k) => (j[k] as num?)?.toInt() ?? 0;
    return BarometerResult(
      downloadPercentile: d('downloadPercentile'),
      uploadPercentile: d('uploadPercentile'),
      pingPercentile: d('pingPercentile'),
      sampleSize: i('sampleSize'),
      nationalAvgDownload: d('nationalAvgDownload'),
      operator: j['operator'] as String?,
      operatorSampleSize: i('operatorSampleSize'),
      operatorDownloadPercentile: d('operatorDownloadPercentile'),
      operatorUploadPercentile: d('operatorUploadPercentile'),
      operatorPingPercentile: d('operatorPingPercentile'),
      operatorAvgDownload: d('operatorAvgDownload'),
      medianDownload: d('medianDownload'),
      medianUpload: d('medianUpload'),
      medianPing: d('medianPing'),
      downloadRank: i('downloadRank'),
      uploadRank: i('uploadRank'),
      pingRank: i('pingRank'),
      streamingPercentile: d('streamingPercentile'),
      browsingPercentile: d('browsingPercentile'),
      operatorTech: j['operatorTech'] as String?,
      operatorTechSampleSize: i('operatorTechSampleSize'),
      operatorTechDownloadPercentile: d('operatorTechDownloadPercentile'),
      operatorTechUploadPercentile: d('operatorTechUploadPercentile'),
      operatorTechPingPercentile: d('operatorTechPingPercentile'),
      zoneSampleSize: i('zoneSampleSize'),
      zoneDownloadPercentile: d('zoneDownloadPercentile'),
      zoneUploadPercentile: d('zoneUploadPercentile'),
      zonePingPercentile: d('zonePingPercentile'),
      recentDownloads: (j['recentDownloads'] as List?)
              ?.whereType<num>()
              .map((v) => v.toDouble())
              .toList() ??
          const [],
      networkType: j['networkType'] as String?,
    );
  }
}

/// Accès aux données agrégées du backend (couverture, stats opérateurs).
class DashboardApiService {
  final logger = Logger();
  final Dio _dio = Dio(BaseOptions(
    baseUrl: API_BASE_URL,
    connectTimeout: const Duration(seconds: 60),
    receiveTimeout: const Duration(seconds: 60),
  ));

  /// Points géolocalisés de tous les tests réels (carte de couverture).
  Future<List<CoveragePoint>> fetchCoveragePoints() async {
    try {
      final res = await _dio.get('/api/dashboard/map');
      final data = res.data;
      if (data is List) {
        return data
            .whereType<Map>()
            .map((e) => CoveragePoint.fromJson(Map<String, dynamic>.from(e)))
            .where((p) => p.lat != 0 && p.lng != 0)
            .toList();
      }
      return [];
    } catch (e) {
      logger.w('Couverture indisponible: $e');
      return [];
    }
  }

  /// IMP-09 — Situe un résultat ([download]/[upload] en Mb/s, [ping] en ms)
  /// par rapport aux mesures de la base, segmentées comme le testeur :
  /// [netType] (« wifi »/« mobile »), [operator], et si fournis, sous-groupes
  /// [tech] (opérateur × techno), [lat]/[lng] (zone ~10 km), [streaming]/
  /// [browsing] (scores des tests associés) et [deviceId] (tendance sur les
  /// 5 derniers tests du même appareil). null si indisponible.
  Future<BarometerResult?> fetchBarometer(
      double download, double upload, double ping,
      {String? operator,
      String? netType,
      String? tech,
      double? lat,
      double? lng,
      double? streaming,
      double? browsing,
      String? deviceId}) async {
    try {
      final res = await _dio.get('/api/dashboard/barometer', queryParameters: {
        'download': download,
        'upload': upload,
        'ping': ping,
        if ((operator ?? '').isNotEmpty) 'operator': operator,
        if ((netType ?? '').isNotEmpty) 'netType': netType,
        if ((tech ?? '').isNotEmpty) 'tech': tech,
        // 0,0 = position absente ou inexploitable : pas de comparaison de
        // zone côté serveur.
        if (lat != null && lat != 0) 'lat': lat,
        if (lng != null && lng != 0) 'lng': lng,
        if ((streaming ?? 0) > 0) 'streaming': streaming,
        if ((browsing ?? 0) > 0) 'browsing': browsing,
        if ((deviceId ?? '').isNotEmpty) 'deviceId': deviceId,
      });
      if (res.data is Map) {
        return BarometerResult.fromJson(Map<String, dynamic>.from(res.data));
      }
      return null;
    } catch (e) {
      logger.w('Baromètre indisponible: $e');
      return null;
    }
  }
}

/// IMP-09 — Opérateur transmis au baromètre : celui de la SIM pour un test en
/// données mobiles, sinon le fournisseur d'accès (Wi-Fi). Le serveur unifie
/// les libellés (« Orange BF », « Orange Burkina Faso » → « Orange »).
String? barometerOperatorOf(SpeedTestResult r) {
  final wifi = (r.networkType ?? '').toUpperCase().contains('WIFI');
  final sim = (r.simOperator ?? '').trim();
  if (!wifi && sim.isNotEmpty) return sim;
  final isp = (r.operator ?? '').trim();
  return isp.isEmpty ? null : isp;
}
