import 'package:dio/dio.dart';
import 'package:logger/logger.dart';

import '../constants/config.dart';

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

/// IMP-11 — Position d'un résultat dans le baromètre de comparaison.
class BarometerResult {
  /// % de mesures de la base plus lentes que le résultat testé.
  final double downloadPercentile;
  final double uploadPercentile;

  /// % de mesures de la base avec une latence pire (supérieure) au résultat.
  final double pingPercentile;

  /// Nombre de mesures prises en compte.
  final int sampleSize;

  BarometerResult({
    required this.downloadPercentile,
    required this.uploadPercentile,
    required this.pingPercentile,
    required this.sampleSize,
  });

  factory BarometerResult.fromJson(Map<String, dynamic> j) => BarometerResult(
        downloadPercentile: (j['downloadPercentile'] as num?)?.toDouble() ?? 0,
        uploadPercentile: (j['uploadPercentile'] as num?)?.toDouble() ?? 0,
        pingPercentile: (j['pingPercentile'] as num?)?.toDouble() ?? 0,
        sampleSize: (j['sampleSize'] as num?)?.toInt() ?? 0,
      );
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

  /// IMP-11 — Situe un résultat ([download]/[upload] en Mb/s, [ping] en ms)
  /// par rapport à toutes les mesures de la base. null si indisponible.
  Future<BarometerResult?> fetchBarometer(
      double download, double upload, double ping) async {
    try {
      final res = await _dio.get('/api/dashboard/barometer', queryParameters: {
        'download': download,
        'upload': upload,
        'ping': ping,
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
