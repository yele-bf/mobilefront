import 'streaming_test_service.dart';

/// Version web du moteur HLS.
///
/// Le lecteur HLS s'appuie sur une WebView native et un serveur HTTP local
/// (`dart:io`) : il n'existe pas sur le web. Cette implémentation permet à
/// l'application web de compiler sans importer les dépendances natives ; elle
/// remonte un résultat vide avec un message explicite si le moteur est choisi.
class StreamingTestServiceHls {
  Future<StreamingTestResult> runTest({
    StreamingControllerCallback? onController,
    StreamingProgressCallback? onProgress,
    StreamingRowsCallback? onRows,
  }) async {
    return const StreamingTestResult(
      qualities: [],
      startupMs: 0,
      rebufferCount: 0,
      rebufferRatio: 0,
      maxResolution: 'inconnue',
      score: 0,
      error: 'Le moteur HLS est indisponible sur le web.',
      engine: 'hls',
    );
  }
}
