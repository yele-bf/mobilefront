import 'package:hive_flutter/hive_flutter.dart';
import 'package:logger/logger.dart';
import '../models/speed_test_result.dart';

class LocalStorageService {
  final logger = Logger();
  static Box<SpeedTestResult>? _resultsBox;

  static const String boxName = 'speedTestResults';

  Future<void> initialize() async {
    try {
      if (_resultsBox?.isOpen ?? false) {
        return;
      }

      await Hive.initFlutter();

      // Enregistrer l'adaptateur
      if (!Hive.isAdapterRegistered(0)) {
        Hive.registerAdapter(SpeedTestResultAdapter());
      }

      _resultsBox = await Hive.openBox<SpeedTestResult>(boxName);
      logger.i('Hive initialisée avec ${_box.length} résultats');
    } catch (e) {
      logger.e('Erreur initialisation Hive: $e');
      rethrow;
    }
  }

  Box<SpeedTestResult> get _box {
    final box = _resultsBox;
    if (box == null || !box.isOpen) {
      throw StateError(
          'LocalStorageService doit être initialisé avant utilisation');
    }
    return box;
  }

  // Sauvegarder un résultat
  Future<void> saveResult(SpeedTestResult result) async {
    try {
      await _box.put(result.id, result);
      logger.i('Résultat sauvegardé: ${result.id}');
    } catch (e) {
      logger.e('Erreur sauvegarde résultat: $e');
      rethrow;
    }
  }

  // Récupérer un résultat
  SpeedTestResult? getResult(String id) {
    try {
      return _box.get(id);
    } catch (e) {
      logger.e('Erreur récupération résultat: $e');
      return null;
    }
  }

  // Récupérer tous les résultats
  List<SpeedTestResult> getAllResults() {
    try {
      return _box.values.toList();
    } catch (e) {
      logger.e('Erreur récupération résultats: $e');
      return [];
    }
  }

  // Récupérer les résultats triés par date (récent d'abord)
  List<SpeedTestResult> getResultsSorted() {
    try {
      List<SpeedTestResult> results = _box.values.toList();
      results.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return results;
    } catch (e) {
      logger.e('Erreur tri résultats: $e');
      return [];
    }
  }

  // Récupérer les résultats du dernier mois
  List<SpeedTestResult> getResultsLastMonth() {
    try {
      DateTime oneMonthAgo = DateTime.now().subtract(const Duration(days: 30));
      List<SpeedTestResult> results =
          _box.values.where((r) => r.timestamp.isAfter(oneMonthAgo)).toList();
      results.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return results;
    } catch (e) {
      logger.e('Erreur récupération dernier mois: $e');
      return [];
    }
  }

  // Chercher dans les résultats
  List<SpeedTestResult> searchResults(String query) {
    try {
      List<SpeedTestResult> results = _box.values.toList();
      return results
          .where((r) =>
              (r.location?.contains(query) ?? false) ||
              r.server.contains(query) ||
              (r.networkType?.contains(query) ?? false))
          .toList();
    } catch (e) {
      logger.e('Erreur recherche: $e');
      return [];
    }
  }

  // Supprimer un résultat
  Future<void> deleteResult(String id) async {
    try {
      await _box.delete(id);
      logger.i('Résultat supprimé: $id');
    } catch (e) {
      logger.e('Erreur suppression résultat: $e');
      rethrow;
    }
  }

  // Supprimer tous les résultats
  Future<void> clearAll() async {
    try {
      await _box.clear();
      logger.i('Tous les résultats ont été supprimés');
    } catch (e) {
      logger.e('Erreur suppression tout: $e');
      rethrow;
    }
  }

  // Statistiques
  Map<String, dynamic> getStatistics() {
    try {
      List<SpeedTestResult> results = getResultsSorted();
      if (results.isEmpty) {
        return {
          'totalTests': 0,
          'averageSpeed': 0,
          'bestSpeed': 0,
          'worstSpeed': 0,
        };
      }

      double avgSpeed =
          results.fold<double>(0.0, (sum, r) => sum + r.downloadSpeed) /
              results.length;
      double bestSpeed =
          results.map((r) => r.downloadSpeed).reduce((a, b) => a > b ? a : b);
      double worstSpeed =
          results.map((r) => r.downloadSpeed).reduce((a, b) => a < b ? a : b);

      return {
        'totalTests': results.length,
        'averageSpeed': avgSpeed,
        'bestSpeed': bestSpeed,
        'worstSpeed': worstSpeed,
        'lastTest': results.isNotEmpty ? results.first.timestamp : null,
      };
    } catch (e) {
      logger.e('Erreur calcul stats: $e');
      return {};
    }
  }

  int getTotalResults() => _box.length;
}
