import 'streaming_test_service.dart';

/// Remplace [WebStreamingRunner] lors des compilations non-web. Jamais
/// instancié : la façade ne l'utilise que lorsque `kIsWeb` est vrai, auquel
/// cas la vraie implémentation est importée à la place.
class WebStreamingRunner extends StreamingRunner {
  @override
  Future<void> openPlayer(StreamingControllerCallback? onController) {
    throw UnsupportedError(
        'WebStreamingRunner n\'est disponible que sur le web.');
  }

  @override
  Future<void> closePlayer() async {}

  @override
  Future<void> jsBuildLevel(String key, int width, int height) async {}

  @override
  Future<void> jsStartLevel(String key) async {}

  @override
  Future<Map<String, dynamic>> jsStopLevel() async => <String, dynamic>{};
}