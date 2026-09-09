import 'dart:async';
import 'dart:js_interop';

import 'package:logger/logger.dart';
import 'package:web/web.dart' as web;

import 'browsing_test_service.dart';

/// Implémentation **web** (Chrome) du test de navigation.
///
/// La plupart des sites de référence (Google, Facebook, YouTube, Bing…)
/// interdisent l'encadrement en iframe (X-Frame-Options / CSP frame-ancestors)
/// et n'envoient pas d'en-têtes CORS : impossible de les charger réellement
/// depuis une page web. On sonde donc chaque site par une requête réseau
/// (`fetch` en mode `no-cors`, opaque mais mesurable), qui reflète le temps de
/// réponse du site — la composante dominante de la navigation sur un réseau
/// mobile. Critère ARCEP conservé : réussi si réponse en moins de 10 s.
class WebBrowsingRunner implements BrowsingRunner {
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

    // Affiche la carte « navigation en cours » pendant le test.
    onController?.call(const WebBrowsingDisplay());

    try {
      for (int i = 0; i < pages.length; i++) {
        final url = pages[i];
        onProgress?.call(i / pages.length, 'Chargement de ${_hostOf(url)}');

        final stopwatch = Stopwatch()..start();
        final ok = await _probe(url);
        stopwatch.stop();

        final ms = stopwatch.elapsedMilliseconds.toDouble();
        if (ok) {
          loadTimes.add(ms);
          if (ms < _successThresholdMs) successes++;
          logger.i('Browsing ${_hostOf(url)}: ${ms.toStringAsFixed(0)} ms');
        } else {
          logger.w('Browsing ${_hostOf(url)}: échec/timeout');
        }

        // Même rythme que la version WebView.
        await Future.delayed(const Duration(milliseconds: 600));
      }
    } finally {
      onController?.call(null); // retire la carte de l'écran
    }

    onProgress?.call(1.0, 'Test de navigation terminé');

    final successRate = pages.isEmpty ? 0.0 : successes / pages.length;
    final avgLoadMs = loadTimes.isEmpty
        ? 0.0
        : loadTimes.reduce((a, b) => a + b) / loadTimes.length;

    final result = BrowsingTestResult(
      avgLoadMs: double.parse(avgLoadMs.toStringAsFixed(0)),
      successRate: double.parse(successRate.toStringAsFixed(2)),
      pagesTested: pages.length,
      score:
          double.parse(_computeScore(successRate, avgLoadMs).toStringAsFixed(1)),
    );
    logger.i(result.toString());
    return result;
  }

  /// Sonde un site : `fetch` en mode `no-cors` (réponse opaque) — la promesse
  /// se résout quand la réponse arrive, sans se faire bloquer par CORS.
  Future<bool> _probe(String url) async {
    try {
      await web.window
          .fetch(url.toJS, web.RequestInit(mode: 'no-cors'))
          .toDart
          .timeout(const Duration(milliseconds: _hardTimeoutMs));
      return true;
    } catch (_) {
      return false;
    }
  }

  double _computeScore(double successRate, double avgLoadMs) {
    double score = 100 * successRate;
    // Pénalité de lenteur : -1 point par 100 ms au-delà de 2 s
    if (avgLoadMs > 2000) score -= (avgLoadMs - 2000) / 100;
    return score.clamp(0, 100);
  }

  String _hostOf(String url) => Uri.tryParse(url)?.host ?? url;
}