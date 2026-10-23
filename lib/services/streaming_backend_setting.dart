import 'package:hive_flutter/hive_flutter.dart';
import 'package:logger/logger.dart';

import '../constants/config.dart';

/// Surcharge à chaud du moteur du test de streaming.
///
/// Le drapeau [streamingBackend] de config.dart fixe le moteur à la
/// compilation ; ce réglage le remplace à l'exécution, sans recompiler l'APK.
/// La valeur vit dans une petite boîte Hive (`appSettings`) distincte des
/// résultats : elle survit au redémarrage de l'application et est appliquée
/// dès le test suivant. Sans surcharge, le moteur reste celui de la
/// configuration compilée — le drapeau reste donc la valeur d'usine.
class StreamingBackendSetting {
  final logger = Logger();

  static const String _boxName = 'appSettings';
  static const String _key = 'streamingBackend';

  /// Valeurs admises, alignées sur le sélecteur du drapeau de config.
  static const List<String> choices = ['youtube', 'hls'];

  static Box<String>? _box;

  /// Ouvre (une fois) la boîte de réglages. Appelée au démarrage de l'app ;
  /// inoffensif de la rappeler. Un échec n'est pas bloquant : les lectures
  /// retomberont sur le moteur compilé.
  Future<void> initialize() async {
    try {
      final box = _box;
      if (box != null && box.isOpen) return;
      _box = await Hive.openBox<String>(_boxName);
    } catch (e) {
      logger.e('Réglages indisponibles : $e');
    }
  }

  Box<String> get _settingsBox {
    final box = _box;
    if (box == null || !box.isOpen) {
      throw StateError(
          'StreamingBackendSetting doit être initialisé avant utilisation');
    }
    return box;
  }

  /// Surcharge persistée actuelle, ou null si le moteur compilé est utilisé.
  /// Une valeur stockée non reconnue (ancienne version, saisie manuelle)
  /// équivaut à l'absence de surcharge.
  String? get overrideValue {
    try {
      final override = _settingsBox.get(_key);
      if (override != null && choices.contains(override)) return override;
    } catch (_) {
      // Boîte absente ou fermée : pas de surcharge, valeur d'usine.
    }
    return null;
  }

  /// Vrai si une surcharge runtime est en place (affichage Réglages).
  bool get hasOverride => overrideValue != null;

  /// Moteur effectif pour le prochain test : la surcharge persistée si elle
  /// est valide, sinon le drapeau de configuration compilée. Ne jette jamais.
  String get effectiveBackend => overrideValue ?? streamingBackend;

  /// Change le moteur pour les prochains tests. Une valeur invalide est
  /// ignorée (repli silencieux sur le moteur compilé) plutôt que levée : un
  /// réglage de débogage ne doit jamais casser un test.
  Future<void> setBackend(String backend) async {
    if (!choices.contains(backend)) return;
    try {
      await _settingsBox.put(_key, backend);
      logger.i('Backend streaming : $backend (surcharge runtime)');
    } catch (e) {
      logger.e('Impossible d\'enregistrer le backend streaming : $e');
    }
  }

  /// Supprime la surcharge : le moteur redevient celui de la configuration
  /// compilée.
  Future<void> resetToDefault() async {
    try {
      await _settingsBox.delete(_key);
      logger.i('Backend streaming : retour au défaut compilé');
    } catch (e) {
      logger.e('Impossible de réinitialiser le backend streaming : $e');
    }
  }

  /// Ferme la boîte de réglages (tests, arrêt propre). Les lectures
  /// suivantes retombent sur le moteur compilé.
  Future<void> dispose() async {
    final box = _box;
    _box = null;
    try {
      await box?.close();
    } catch (_) {
      // Déjà fermée : rien à faire.
    }
  }
}
