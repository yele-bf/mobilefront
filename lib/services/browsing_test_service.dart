import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:webview_flutter/webview_flutter.dart';

import '../constants/config.dart';
import 'browsing_test_service_native.dart' as native_impl;
import 'browsing_test_service_web.dart'
    if (dart.library.io) 'browsing_test_service_web_stub.dart' as web_impl;

/// Résultat du test de navigation web.
class BrowsingTestResult {
  final double avgLoadMs; // temps de chargement moyen des pages réussies
  final double successRate; // part des pages chargées en < 10 s (0-1)
  final int pagesTested;
  final double score; // score synthétique 0-100

  const BrowsingTestResult({
    required this.avgLoadMs,
    required this.successRate,
    required this.pagesTested,
    required this.score,
  });

  @override
  String toString() =>
      'Browsing: ${avgLoadMs.toStringAsFixed(0)} ms en moyenne, '
      '${(successRate * 100).toStringAsFixed(0)}% de réussite sur $pagesTested pages, '
      'score ${score.toStringAsFixed(1)}';
}

typedef BrowsingProgressCallback = void Function(double progress, String message);

/// Callback fournissant l'affichage du test de navigation à l'interface,
/// puis null quand le test est terminé.
typedef BrowsingControllerCallback = void Function(BrowsingDisplay? display);

/// Ce que l'interface doit afficher pendant le test de navigation.
sealed class BrowsingDisplay {
  const BrowsingDisplay();
}

/// Pages chargées dans une vraie WebView (Android, iOS, macOS).
class NativeBrowsingDisplay extends BrowsingDisplay {
  final WebViewController controller;
  const NativeBrowsingDisplay({required this.controller});
}

/// Web : les pages sont sondées par requêtes réseau, pas d'affichage réel —
/// la plupart des sites de référence bloquent l'encadrement (X-Frame-Options).
class WebBrowsingDisplay extends BrowsingDisplay {
  const WebBrowsingDisplay();
}

/// Interface commune des deux implémentations (native WebView / web fetch).
abstract class BrowsingRunner {
  Future<BrowsingTestResult> runTest({
    required List<String> pages,
    BrowsingControllerCallback? onController,
    BrowsingProgressCallback? onProgress,
  });
}

/// Test de navigation web **réel et visible**.
///
/// Sur Android/iOS/macOS, chaque page de référence est chargée dans une vraie
/// WebView affichée à l'écran, et on mesure le temps entre le début du
/// chargement et la fin du rendu. Sur le web (Chrome), les pages sont sondées
/// par requêtes réseau (les sites de référence interdisent l'encadrement en
/// iframe) : on mesure le temps de réponse, proxy de l'expérience de
/// navigation sur réseau mobile.
///
/// Critère ARCEP : une page est "réussie" si elle se charge en moins de 10 s.
class BrowsingTestService {
  Future<BrowsingTestResult> runTest({
    List<String> pages = BROWSING_REFERENCE_PAGES,
    BrowsingControllerCallback? onController,
    BrowsingProgressCallback? onProgress,
  }) {
    final runner = kIsWeb
        ? web_impl.WebBrowsingRunner()
        : native_impl.NativeBrowsingRunner();
    return runner.runTest(
      pages: pages,
      onController: onController,
      onProgress: onProgress,
    );
  }
}