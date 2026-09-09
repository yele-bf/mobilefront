import 'dart:async';

import 'package:logger/logger.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'browsing_test_service.dart';

/// Implémentation native (Android, iOS, macOS) du test de navigation web :
/// chaque page de référence est chargée dans une vraie [WebViewController]
/// affichée à l'écran, et on mesure le temps écoulé entre le début du
/// chargement et la fin du rendu ([NavigationDelegate.onPageFinished]).
/// Contrairement à une simple requête HTTP, cela inclut le téléchargement des
/// sous-ressources (CSS, JS, images) et le rendu — la mesure reflète
/// l'expérience réelle de navigation.
class NativeBrowsingRunner implements BrowsingRunner {
  final Logger logger = Logger();

  // Au-delà : la page compte comme un échec (critère ARCEP)
  static const int _successThresholdMs = 10000;
  // Sécurité absolue par page (réseaux très lents) avant de passer à la suivante
  static const int _hardTimeoutMs = 20000;

  Future<BrowsingTestResult> runTest({
    required List<String> pages,
    BrowsingControllerCallback? onController,
    BrowsingProgressCallback? onProgress,
  }) async {
    final loadTimes = <double>[];
    int successes = 0;

    // Complète à chaque fin de chargement (ou erreur) de la page courante.
    Completer<void>? pageCompleter;
    bool currentPageFailed = false;

    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (pageCompleter != null && !pageCompleter!.isCompleted) {
              pageCompleter!.complete();
            }
          },
          onWebResourceError: (error) {
            // On n'échoue que sur l'erreur du document principal, pas sur une
            // sous-ressource secondaire (pub, tracker bloqué, etc.).
            if (error.isForMainFrame == true &&
                pageCompleter != null &&
                !pageCompleter!.isCompleted) {
              currentPageFailed = true;
              pageCompleter!.complete();
            }
          },
        ),
      );

    onController?.call(NativeBrowsingDisplay(controller: controller));

    try {
      for (int i = 0; i < pages.length; i++) {
        final url = pages[i];
        onProgress?.call(i / pages.length, 'Chargement de ${_hostOf(url)}');

        pageCompleter = Completer<void>();
        currentPageFailed = false;
        final stopwatch = Stopwatch()..start();

        await controller.loadRequest(Uri.parse(url));

        try {
          await pageCompleter!.future
              .timeout(const Duration(milliseconds: _hardTimeoutMs));
        } on TimeoutException {
          currentPageFailed = true;
        }
        stopwatch.stop();

        final ms = stopwatch.elapsedMilliseconds.toDouble();
        if (!currentPageFailed) {
          loadTimes.add(ms);
          if (ms < _successThresholdMs) successes++;
          logger.i('Browsing ${_hostOf(url)}: ${ms.toStringAsFixed(0)} ms');
        } else {
          logger.w('Browsing ${_hostOf(url)}: échec/timeout');
        }

        // Laisse la page visible un court instant avant la suivante
        await Future.delayed(const Duration(milliseconds: 600));
      }
    } finally {
      onController?.call(null); // retire le navigateur de l'écran
    }

    onProgress?.call(1.0, 'Test de navigation terminé');

    return _buildResult(loadTimes, successes, pages.length);
  }

  /// Consolide les mesures en résultat (partagé avec la version web).
  BrowsingTestResult _buildResult(
      List<double> loadTimes, int successes, int total) {
    final successRate = total == 0 ? 0.0 : successes / total;
    final avgLoadMs = loadTimes.isEmpty
        ? 0.0
        : loadTimes.reduce((a, b) => a + b) / loadTimes.length;

    final result = BrowsingTestResult(
      avgLoadMs: double.parse(avgLoadMs.toStringAsFixed(0)),
      successRate: double.parse(successRate.toStringAsFixed(2)),
      pagesTested: total,
      score: double.parse(_computeScore(successRate, avgLoadMs).toStringAsFixed(1)),
    );
    logger.i(result.toString());
    return result;
  }

  double _computeScore(double successRate, double avgLoadMs) {
    double score = 100 * successRate;
    // Pénalité de lenteur : -1 point par 100 ms au-delà de 2 s
    if (avgLoadMs > 2000) score -= (avgLoadMs - 2000) / 100;
    return score.clamp(0, 100);
  }

  String _hostOf(String url) => Uri.tryParse(url)?.host ?? url;
}