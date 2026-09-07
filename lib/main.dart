import 'package:flutter/material.dart';

import 'models/test_selection.dart';
import 'screens/coverage_screen.dart';
import 'screens/full_test_screen.dart';
import 'screens/history_screen.dart';
import 'screens/settings_screen.dart';
import 'services/local_storage_service.dart';
import 'services/settings_service.dart';
import 'theme/yele_theme.dart';
import 'widgets/app_localizations.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await LocalStorageService().initialize();
  } catch (_) {
    // Le stockage local n'est pas bloquant pour lancer un test.
  }
  try {
    await SettingsService.initialize();
  } catch (_) {
    // Les réglages non persistés ne bloquent pas le lancement de l'app :
    // les valeurs par défaut s'appliquent (ISS-12).
  }
  runApp(const YeleApp());
}

class YeleApp extends StatefulWidget {
  const YeleApp({super.key});

  @override
  State<YeleApp> createState() => _YeleAppState();
}

class _YeleAppState extends State<YeleApp> {
  final _settings = SettingsService();

  @override
  void initState() {
    super.initState();
    // ISS-12 : changer le style de fond OU la langue se voit immédiatement,
    // sans redémarrer l'application — le MaterialApp se reconstruit, ce qui
    // relit les réglages (thème, AppLocale) et reconstruit tous les écrans.
    SettingsService.appStyleNotifier.addListener(_onSettingChanged);
    SettingsService.languageNotifier.addListener(_onSettingChanged);
  }

  @override
  void dispose() {
    SettingsService.appStyleNotifier.removeListener(_onSettingChanged);
    SettingsService.languageNotifier.removeListener(_onSettingChanged);
    super.dispose();
  }

  void _onSettingChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Yélé',
      debugShowCheckedModeBanner: false,
      theme: buildYeleTheme(),
      darkTheme: buildYeleDarkTheme(),
      themeMode:
          _settings.appStyle == AppStyle.dark ? ThemeMode.dark : ThemeMode.light,
      // ISS-12 : la route initiale dépend du réglage « Test par défaut ».
      initialRoute: _settings.initialRoute,
      routes: {
        '/full': (_) => const FullTestScreen(
              selection: TestSelection.all(),
              title: 'Test complet',
              route: '/full',
              launchLabel: 'LANCER LE\nTEST COMPLET',
            ),
        '/speed': (_) => const FullTestScreen(
              selection: TestSelection(speed: true),
              title: 'Speed test',
              route: '/speed',
              launchLabel: 'LANCER LE\nSPEEDTEST',
            ),
        '/browsing': (_) => const FullTestScreen(
              selection: TestSelection(speed: false, browsing: true),
              title: 'Test de navigation',
              route: '/browsing',
              launchLabel: 'LANCER LE\nTEST NAVIGATION',
            ),
        '/streaming': (_) => const FullTestScreen(
              selection: TestSelection(speed: false, streaming: true),
              title: 'Test de streaming',
              route: '/streaming',
              launchLabel: 'LANCER LE\nTEST STREAMING',
            ),
        '/history': (_) => const HistoryScreen(),
        '/coverage': (_) => const CoverageScreen(),
        '/settings': (_) => const SettingsScreen(),
      },
      builder: (context, child) {
        // ISS-12 : langue minimale (Réglages + tiroir). L'i18n complète
        // reste le périmètre d'IMP-02. Lu depuis le notificateur pour que
        // le changement s'applique à la reconstruction immédiate.
        AppLocale.current = SettingsService.languageNotifier.value;
        return child ?? const SizedBox.shrink();
      },
    );
  }
}
