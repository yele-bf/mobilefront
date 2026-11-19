import 'package:hive_flutter/hive_flutter.dart';

/// Mémorise le profil déclaré (âge, genre, ancienneté) pour pré-remplir le
/// questionnaire du test suivant. Aucun autre réglage n'est stocké ici.
///
/// La box est ouverte à la demande et toutes les erreurs sont absorbées :
/// le questionnaire doit rester utilisable même si le stockage est
/// indisponible (tests widget, première ouverture).
class QoeProfileStore {
  static const String boxName = 'qoeProfile';
  static const String _key = 'last';

  static Map<String, dynamic>? _memory;

  static Future<Map<String, dynamic>?> load() async {
    if (_memory != null) return _memory;
    try {
      final box = await Hive.openBox(boxName);
      final raw = box.get(_key);
      if (raw is Map) {
        _memory = Map<String, dynamic>.from(raw);
        return _memory;
      }
    } catch (_) {
      // Stockage indisponible : pas de pré-remplissage.
    }
    return null;
  }

  static Future<void> save(Map<String, dynamic> profile) async {
    _memory = Map<String, dynamic>.from(profile);
    try {
      final box = await Hive.openBox(boxName);
      await box.put(_key, _memory);
    } catch (_) {
      // L'échec d'écriture ne doit jamais bloquer l'enregistrement du test.
    }
  }
}
