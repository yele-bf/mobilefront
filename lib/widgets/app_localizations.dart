import 'dart:ui';

import '../services/settings_service.dart';

/// ISS-12 — Localisation minimale (Réglages + tiroir de navigation).
///
/// Le choix « Langue » des réglages (`system` / `fr` / `en`) pilote les
/// libellés de ces deux zones. L'i18n complète de toute l'application reste
/// le périmètre d'IMP-02.
class AppLocale {
  static AppLanguage _current = AppLanguage.system;

  static set current(AppLanguage v) => _current = v;

  /// Résout `system` via la locale du téléphone (repli : français).
  static bool get isEnglish {
    switch (_current) {
      case AppLanguage.en:
        return true;
      case AppLanguage.fr:
        return false;
      case AppLanguage.system:
        final lang = PlatformDispatcher.instance.locale.languageCode;
        return lang == 'en';
    }
  }

  static String t(String fr, String en) => isEnglish ? en : fr;
}
