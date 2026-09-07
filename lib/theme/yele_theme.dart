import 'package:flutter/material.dart';

import '../services/settings_service.dart';

/// Palette et styles repris de la maquette interactive Yélé.
///
/// ISS-12 — Les cinq couleurs de surface (panel, panel2, line, ink, muted)
/// sont désormais **dynamiques** : elles suivent le réglage « Style de fond »
/// (Blanc / Sombre). Elles restent accessibles sous forme de constantes
/// (`const YeleColors.panel`) pour tout usage hors widget — dans un widget,
/// utiliser les getters (`YeleColors.surface.panel`) qui rendent le thème
/// réactif.
class YeleColors {
  // Fonds & navigation (thème sombre)
  static const bg = Color(0xFF0E1726);
  static const header = Color(0xFF16213A);
  static const header2 = Color(0xFF1D2A47);
  static const drawerBg = Color(0xFF1B2030);

  // Marque
  static const primary = Color(0xFF0BB89C); // teal Yélé
  static const primaryDk = Color(0xFF089A83);
  static const accent = Color(0xFF19C3FF); // cyan data
  static const field = Color(0xFF0FA3DF); // bleu valeurs

  // Statuts
  static const good = Color(0xFF2BB673);
  static const warn = Color(0xFFF5A623);
  static const danger = Color(0xFFE0464B);

  // Écran de test (fond vert dégradé)
  static const testTop = Color(0xFFCFE86B);
  static const testMid = Color(0xFFA9DD3B);
  static const testBot = Color(0xFF7FC91F);
  static const scoreRing = Color(0xFF9AD11F);

  // Couleurs par technologie réseau
  static const g2 = Color(0xFF1F7AE0);
  static const g3 = Color(0xFF7AC943);
  static const g4 = Color(0xFFF5921E);
  static const g4p = Color(0xFFD2353A);
  static const g5 = Color(0xFF8A3FFC);

  static const testGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [testTop, testMid, testBot],
  );

  // ── Surfaces dynamiques (Blanc / Sombre) ──────────────────────────────────

  /// Palette de surface courante, selon le réglage « Style de fond ».
  /// Les getters ci-dessous la relisent à chaque build : changer le style
  /// reconstruit l'application (voir main.dart) et les écrans suivent.
  static YeleSurface get surface =>
      SettingsService.appStyleNotifier.value == AppStyle.dark
          ? YeleSurface.dark
          : YeleSurface.light;

  /// Fond des panneaux de contenu (cartes, lignes de liste…).
  static Color get panel => surface.panel;

  /// Fond secondaire (lignes alternées, puces…).
  static Color get panel2 => surface.panel2;

  /// Bordures et séparateurs.
  static Color get line => surface.line;

  /// Couleur du texte principal.
  static Color get ink => surface.ink;

  /// Couleur du texte secondaire.
  static Color get muted => surface.muted;

  // Constantes claires d'origine — utilisées hors widget (exports PDF/PNG,
  // valeurs par défaut) et par YeleSurface.light.
  static const panelLight = Color(0xFFF3F5F7);
  static const panel2Light = Color(0xFFE7EBEF);
  static const lineLight = Color(0xFFDDE3EA);
  static const inkLight = Color(0xFF1B2333);
  static const mutedLight = Color(0xFF7C8AA0);
}

/// Jeu de couleurs de surface, clair ou sombre.
class YeleSurface {
  final Color panel;
  final Color panel2;
  final Color line;
  final Color ink;
  final Color muted;

  const YeleSurface({
    required this.panel,
    required this.panel2,
    required this.line,
    required this.ink,
    required this.muted,
  });

  /// Thème « Blanc » d'origine (maquette Yélé).
  static const light = YeleSurface(
    panel: Color(0xFFF3F5F7),
    panel2: Color(0xFFE7EBEF),
    line: Color(0xFFDDE3EA),
    ink: Color(0xFF1B2333),
    muted: Color(0xFF7C8AA0),
  );

  /// Thème « Sombre » — surfaces bleu nuit profond, textes clairs ; les
  /// accents de marque (teal, cyan, statuts) restent identiques.
  static const dark = YeleSurface(
    panel: Color(0xFF131C2E),
    panel2: Color(0xFF1B2538),
    line: Color(0xFF26324A),
    ink: Color(0xFFE7ECF4),
    muted: Color(0xFF8B99B0),
  );
}

ThemeData buildYeleTheme() {
  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: YeleColors.bg,
    colorScheme: ColorScheme.fromSeed(
      seedColor: YeleColors.primary,
      primary: YeleColors.primary,
      brightness: Brightness.light,
    ),
    fontFamily: 'Roboto',
  );
}

/// ISS-12 — Variante sombre du thème : mêmes accents de marque
/// (teal / cyan), surfaces et textes inversés.
ThemeData buildYeleDarkTheme() {
  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: YeleSurface.dark.panel,
    colorScheme: ColorScheme.fromSeed(
      seedColor: YeleColors.primary,
      primary: YeleColors.primary,
      brightness: Brightness.dark,
    ),
    fontFamily: 'Roboto',
  );
}
