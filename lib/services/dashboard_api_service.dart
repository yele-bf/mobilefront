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

  /// Nombre de mesures prises en compte.
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

  /// En dessous, le serveur ne calcule pas de centile par opérateur.
  static const minOperatorSample = 5;

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
  });

  /// Vrai si la comparaison par opérateur est significative.
  bool get hasOperatorComparison =>
      (operator ?? '').isNotEmpty && operatorSampleSize >= minOperatorSample;

  factory BarometerResult.fromJson(Map<String, dynamic> j) {
    double d(String k) => (j[k] as num?)?.toDouble() ?? 0;
    return BarometerResult(
      downloadPercentile: d('downloadPercentile'),
      uploadPercentile: d('uploadPercentile'),
      pingPercentile: d('pingPercentile'),
      sampleSize: (j['sampleSize'] as num?)?.toInt() ?? 0,
      nationalAvgDownload: d('nationalAvgDownload'),
      operator: j['operator'] as String?,
      operatorSampleSize: (j['operatorSampleSize'] as num?)?.toInt() ?? 0,
      operatorDownloadPercentile: d('operatorDownloadPercentile'),
      operatorUploadPercentile: d('operatorUploadPercentile'),
      operatorPingPercentile: d('operatorPingPercentile'),
      operatorAvgDownload: d('operatorAvgDownload'),
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
  /// par rapport à toutes les mesures de la base et, si [operator] est
  /// fourni, par rapport aux seuls clients de cet opérateur. null si
  /// indisponible.
  Future<BarometerResult?> fetchBarometer(
      double download, double upload, double ping,
      {String? operator}) async {
    try {
      final res = await _dio.get('/api/dashboard/barometer', queryParameters: {
        'download': download,
        'upload': upload,
        'ping': ping,
        if ((operator ?? '').isNotEmpty) 'operator': operator,
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
