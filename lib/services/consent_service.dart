import 'package:hive_flutter/hive_flutter.dart';
import 'package:logger/logger.dart';

/// IMP-14 — Acceptation des conditions d'utilisation au premier lancement.
///
/// Chaque test envoie au serveur la position GPS, l'adresse IP, l'opérateur
/// et le modèle de l'appareil : l'utilisateur doit en être averti et accepter
/// avant toute mesure (Google Play exige d'ailleurs une divulgation explicite
/// pour la localisation). Tant que [hasAccepted] est faux, l'app n'affiche
/// que l'écran des conditions.
class ConsentService {
  ConsentService._();

  static final ConsentService instance = ConsentService._();

  final logger = Logger();

  /// Version des conditions. L'incrémenter quand les données collectées ou
  /// les règles d'usage changent : l'accord est alors redemandé à tous.
  /// v2 (15/11/2026) : section collecte arrière-plan rewordée (suspendue),
  /// droits mis à jour (chemin du retrait + autorisations redemandées).
  static const int termsVersion = 2;

  static const String boxName = 'consent';
  static const String _versionKey = 'termsVersion';
  static const String _dateKey = 'acceptedAt';
  // Demande du 15/11/2026 : « Retirer mon accord » doit aussi faire
  // redemander les autorisations (localisation, réseau mobile,
  // notifications) au prochain accord — pas seulement les conditions.
  static const String _reconfirmKey = 'reconfirmPermissions';

  Box? _box;

  /// Ouvre la boîte Hive. Hive doit déjà être initialisé
  /// (LocalStorageService au démarrage, `Hive.init` dans les tests).
  Future<void> initialize() async {
    if (_box?.isOpen ?? false) return;
    _box = await Hive.openBox(boxName);
  }

  /// Vrai si l'utilisateur a accepté la version actuelle des conditions.
  /// Faux si le stockage est illisible : mieux vaut redemander l'accord que
  /// mesurer sans.
  bool get hasAccepted {
    try {
      return (_box?.get(_versionKey) as int? ?? 0) >= termsVersion;
    } catch (e) {
      logger.e('Lecture de l\'accord impossible : $e');
      return false;
    }
  }

  DateTime? get acceptedAt {
    final ms = _box?.get(_dateKey) as int?;
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> accept() async {
    await _box?.put(_versionKey, termsVersion);
    await _box?.put(_dateKey, DateTime.now().millisecondsSinceEpoch);
    logger.i('Conditions d\'utilisation acceptées (v$termsVersion)');
  }

  Future<void> withdraw() async {
    await _box?.delete(_versionKey);
    await _box?.delete(_dateKey);
    // Les conditions ET les autorisations seront de nouveau demandées :
    // le prochain accord repasse par la séquence complète de permissions
    // (ConsentScreen), comme un premier lancement.
    await _box?.put(_reconfirmKey, true);
    logger.i('Accord aux conditions retiré (permissions à reconfirmer)');
  }

  /// Vrai si le prochain accord doit redemander les autorisations
  /// (posé par [withdraw], consommé par ConsentScreen).
  bool get shouldReconfirmPermissions {
    try {
      return _box?.get(_reconfirmKey) as bool? ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Ferme la séquence de re-confirmation : le drapeau est consommé.
  Future<void> clearReconfirm() async {
    await _box?.delete(_reconfirmKey);
  }

  /// Ferme la boîte (tests).
  Future<void> dispose() async {
    await _box?.close();
    _box = null;
  }
}
