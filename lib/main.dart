import 'package:flutter/material.dart';

import 'models/test_selection.dart';
import 'screens/coverage_screen.dart';
import 'screens/full_test_screen.dart';
import 'screens/history_screen.dart';
import 'screens/settings_screen.dart';
import 'services/local_storage_service.dart';
import 'services/streaming_backend_setting.dart';
import 'theme/yele_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await LocalStorageService().initialize();
    await StreamingBackendSetting().initialize();
  } catch (_) {
    // Le stockage local n'est pas bloquant pour lancer un test.
  }
  runApp(const YeleApp());
}

class YeleApp extends StatelessWidget {
  const YeleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Yélé',
      debugShowCheckedModeBanner: false,
      theme: buildYeleTheme(),
      initialRoute: '/full',
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
    );
  }
}
