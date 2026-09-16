import 'dart:async';

import 'package:flutter/material.dart';

import 'models/test_selection.dart';
import 'screens/coverage_screen.dart';
import 'screens/full_test_screen.dart';
import 'screens/history_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/usage_screen.dart';
import 'services/local_storage_service.dart';
import 'services/settings_service.dart';
import 'services/throughput_service.dart';
import 'services/usage_tracker_service.dart';
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
  try {
    await UsageTrackerService.initialize();
  } catch (_) {
    // Sans suivi de consommation, le reste de l'app fonctionne normalement.
  }
  runApp(const YeleApp());
}

class YeleApp extends StatefulWidget {
  const YeleApp({super.key});

  @override
  State<YeleApp> createState() => _YeleAppState();
}

class _YeleAppState extends State<YeleApp> with WidgetsBindingObserver {
  final _settings = SettingsService();

  @override
  void initState() {
    super.initState();
    // IMP-01c : observateur du cycle de vie pour relever les compteurs de
    // consommation au retour au premier plan (évite d'attribuer en bloc au
    // mauvais réseau le trafic accumulé pendant l'arrière-plan).
    WidgetsBinding.instance.addObserver(this);
    // IMP-01 : échantillonnage de la consommation data pendant que l'app est
    // au premier plan.
    UsageTrackerService.instance.startPolling();
    // IMP-01d : trafic de collecte accumulé pendant que l'app était fermée.
    UsageTrackerService.instance.collectBackgroundUsage();
    // IMP-01 : débit temps réel (barre d'état) si l'utilisateur l'a activé.
    // Si le service natif ne démarre pas (notification refusée, restriction
    // constructeur…), le réglage est remis à false : sans cela, l'app
    // retenterait — et échouerait — à chaque lancement.
    _restoreRealtimeSpeed();
    // ISS-12 : changer le style de fond OU la langue se voit immédiatement,
    // sans redémarrer l'application — le MaterialApp se reconstruit, ce qui
    // relit les réglages (thème, AppLocale) et reconstruit tous les écrans.
    SettingsService.appStyleNotifier.addListener(_onSettingChanged);
    SettingsService.languageNotifier.addListener(_onSettingChanged);
    SettingsService.realtimeSpeedNotifier.addListener(_onRealtimeSpeedChanged);
  }

  /// Reprise du débit temps réel après un redémarrage de l'app (réglage
  /// persisté). Silencieux en cas d'échec : le réglage est alors remis à
  /// false pour éviter une boucle de tentative-crash au lancement.
  Future<void> _restoreRealtimeSpeed() async {
    try {
      if (!_settings.realtimeSpeed) return;
      final ok = await ThroughputService.instance.applySetting(true);
      if (!ok) _settings.realtimeSpeed = false;
    } catch (_) {}
  }

  // IMP-01c — Relevé immédiat de la consommation au retour au premier plan.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      UsageTrackerService.instance.onResume();
      // IMP-01d : réintègre le trafic consommé par la collecte passive
      // pendant que l'app était en arrière-plan.
      UsageTrackerService.instance.collectBackgroundUsage();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SettingsService.appStyleNotifier.removeListener(_onSettingChanged);
    SettingsService.languageNotifier.removeListener(_onSettingChanged);
    SettingsService.realtimeSpeedNotifier.removeListener(_onRealtimeSpeedChanged);
    super.dispose();
  }

  void _onSettingChanged() {
    if (mounted) setState(() {});
  }

  void _onRealtimeSpeedChanged() {
    ThroughputService.instance.applySetting(SettingsService.realtimeSpeedNotifier.value);
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
        '/usage': (_) => const UsageScreen(),
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
