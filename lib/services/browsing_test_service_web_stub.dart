import 'browsing_test_service.dart';

/// Remplace [WebBrowsingRunner] lors des compilations non-web. Jamais
/// instancié : la façade ne l'utilise que lorsque `kIsWeb` est vrai, auquel
/// cas la vraie implémentation est importée à la place.
class WebBrowsingRunner implements BrowsingRunner {
  Future<BrowsingTestResult> runTest({
    required List<String> pages,
    BrowsingControllerCallback? onController,
    BrowsingProgressCallback? onProgress,
  }) {
    throw UnsupportedError(
        'WebBrowsingRunner n\'est disponible que sur le web.');
  }
}