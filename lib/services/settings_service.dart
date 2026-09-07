import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:logger/logger.dart';

/// ISS-12 — Réglages fonctionnels et persistants.
///
/// Source de vérité unique des quatre réglages « Général » de l'écran
/// Réglages : langue, test lancé au démarrage, unité d'affichage des débits
/// et style de fond. Tout est stocké dans une box Hive dédiée
/// (`appSettings`), indépendante de l'historique des mesures.
///
/// Chaque réglage est exposé en lecture directe (valeur courante) et via
/// [ValueNotifier] pour que les écrans se mettent à jour sans redémarrage.

/// Langue de l'interface. `system` suit la locale du téléphone (repli
/// français si la locale du téléphone n'est pas gérée).
enum AppLanguage { system, fr, en }

/// Test lancé au démarrage de l'application — les quatre routes existantes
/// de `main.dart`.
enum DefaultTest { full, speed, streaming, browsing }

/// Unité d'affichage des débits. `auto` affiche en Mb/s au-dessus de 1 Mb/s
/// et bascule en Kb/s en dessous (comportement nPerf) ; les deux autres
/// modes forcent l'unité.
enum SpeedUnit { auto, mbps, kbps }

/// Style de fond de l'application.
enum AppStyle { green, dark }

class SettingsService {
  final logger = Logger();

  static const String boxName = 'appSettings';
  static Box? _box;

  /// Notificateurs mis à jour à chaque écriture — consommés par les écrans
  /// pour se rafraîchir en direct.
  static final ValueNotifier<AppLanguage> languageNotifier =
      ValueNotifier(AppLanguage.system);
  static final ValueNotifier<DefaultTest> defaultTestNotifier =
      ValueNotifier(DefaultTest.full);
  static final ValueNotifier<SpeedUnit> speedUnitNotifier =
      ValueNotifier(SpeedUnit.auto);
  static final ValueNotifier<AppStyle> appStyleNotifier =
      ValueNotifier(AppStyle.green);

  static Future<void> initialize() async {
    if (_box?.isOpen ?? false) return;
    _box = await Hive.openBox(boxName);
    // Recharger les notificateurs depuis le stockage à l'ouverture.
    languageNotifier.value = _readEnum(
        'language', AppLanguage.values, AppLanguage.system);
    defaultTestNotifier.value = _readEnum(
        'defaultTest', DefaultTest.values, DefaultTest.full);
    speedUnitNotifier.value =
        _readEnum('speedUnit', SpeedUnit.values, SpeedUnit.auto);
    appStyleNotifier.value =
        _readEnum('appStyle', AppStyle.values, AppStyle.green);
  }

  static T _readEnum<T extends Enum>(String key, List<T> values, T fallback) {
    final raw = _box?.get(key);
    if (raw is! String) return fallback;
    for (final v in values) {
      if (v.name == raw) return v;
    }
    return fallback;
  }

  Box get _b {
    final box = _box;
    if (box == null || !box.isOpen) {
      throw StateError(
          'SettingsService doit être initialisé avant utilisation');
    }
    return box;
  }

  void _set(String key, Object value) => _b.put(key, value);

  T _getEnum<T extends Enum>(String key, List<T> values, T fallback) =>
      _readEnum(key, values, fallback);

  // ── Langue ───────────────────────────────────────────────────────────────

  static const _kLanguage = 'language';

  AppLanguage get language =>
      _getEnum(_kLanguage, AppLanguage.values, AppLanguage.system);

  set language(AppLanguage v) {
    _set(_kLanguage, v.name);
    languageNotifier.value = v;
  }

  // ── Test par défaut ──────────────────────────────────────────────────────

  static const _kDefaultTest = 'defaultTest';

  DefaultTest get defaultTest =>
      _getEnum(_kDefaultTest, DefaultTest.values, DefaultTest.full);

  set defaultTest(DefaultTest v) {
    _set(_kDefaultTest, v.name);
    defaultTestNotifier.value = v;
  }

  /// Route à ouvrir au démarrage, d'après le réglage.
  String get initialRoute {
    switch (defaultTest) {
      case DefaultTest.full:
        return '/full';
      case DefaultTest.speed:
        return '/speed';
      case DefaultTest.streaming:
        return '/streaming';
      case DefaultTest.browsing:
        return '/browsing';
    }
  }

  // ── Unité de débit ───────────────────────────────────────────────────────

  static const _kSpeedUnit = 'speedUnit';

  SpeedUnit get speedUnit =>
      _getEnum(_kSpeedUnit, SpeedUnit.values, SpeedUnit.auto);

  set speedUnit(SpeedUnit v) {
    _set(_kSpeedUnit, v.name);
    speedUnitNotifier.value = v;
  }

  /// Formate un débit exprimé en Mb/s selon l'unité choisie.
  /// Retourne la chaîne prête à afficher, ex. « 12,40 Mb/s » ou « 850 Kb/s ».
  String formatSpeed(double mbps) {
    switch (speedUnit) {
      case SpeedUnit.mbps:
        return '${mbps.toStringAsFixed(2)} Mb/s';
      case SpeedUnit.kbps:
        final kbps = mbps * 1000;
        return '${kbps.toStringAsFixed(kbps >= 100 ? 0 : 1)} Kb/s';
      case SpeedUnit.auto:
        if (mbps >= 1) return '${mbps.toStringAsFixed(2)} Mb/s';
        final kbps = mbps * 1000;
        return '${kbps.toStringAsFixed(kbps >= 100 ? 0 : 1)} Kb/s';
    }
  }

  // ── Style de fond ────────────────────────────────────────────────────────

  static const _kAppStyle = 'appStyle';

  AppStyle get appStyle =>
      _getEnum(_kAppStyle, AppStyle.values, AppStyle.green);

  set appStyle(AppStyle v) {
    _set(_kAppStyle, v.name);
    appStyleNotifier.value = v;
  }
}
