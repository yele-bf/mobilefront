import 'dart:async';
import 'dart:io' show ContentType, HttpServer, InternetAddress;
import 'dart:ui' show Color;

import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import '../constants/config.dart';
import 'streaming_test_service.dart';

/// Parties communes aux deux moteurs du test de streaming (YouTube IFrame et
/// HLS/DASH via hls.js) : hébergement local de la page du lecteur, construction
/// du contrôleur WebView, agrégation des mesures par qualité et calcul du
/// score. Les deux backends produisent le même [StreamingTestResult].
///
/// Agrège les mesures par qualité en indicateurs globaux (stockés dans
/// l'historique et envoyés au serveur).
///
/// Indicateur global affiché à la fin du test (règle nPerf) : la MOYENNE des
/// taux de performance des qualités réellement servies — chaque palier servi
/// pèse autant. 0 si aucune qualité n'a pu être lue.
StreamingTestResult aggregateStreamingResults(List<StreamingQualityResult> rows,
    {String? error}) {
  final reached = rows.where((r) => r.reached).toList();

  // Résolution maximale et score : basés sur la qualité réellement SERVIE
  // (servedHeight), pas sur ce qu'on a demandé. Demander 2160p sur un réseau
  // qui n'a tenu que 1440p ne doit pas rapporter les points du 4K.
  final bestHeight = reached.isEmpty
      ? 0
      : reached.map((r) => r.servedHeight).reduce((a, b) => a > b ? a : b);
  final startupMs =
      reached.isEmpty ? 0 : (reached.first.initialLoadingSec * 1000).round();
  final rebuffers = reached.fold<int>(0, (sum, r) => sum + r.rebufferCount);

  final buffering = reached.fold<double>(0, (sum, r) => sum + r.bufferingSec);
  final watched = reached.fold<double>(
      0, (sum, r) => sum + STREAMING_LEVEL_DURATION_SEC - r.bufferingSec);
  final measured = watched + buffering;
  final ratio = measured > 0 ? (buffering / measured).clamp(0.0, 1.0) : 0.0;

  // Performance globale : moyenne des taux de performance des paliers servis
  // (et non 0 pour les paliers manquants — un réseau qui ne tient pas le 4K
  // ne doit pas écraser la performance mesurée sur les paliers servis).
  final score = reached.isEmpty
      ? 0.0
      : reached.map((r) => r.performanceRate).reduce((a, b) => a + b) /
          reached.length;

  return StreamingTestResult(
    qualities: rows,
    startupMs: startupMs,
    rebufferCount: rebuffers,
    rebufferRatio: double.parse(ratio.toStringAsFixed(3)),
    maxResolution: bestHeight > 0 ? '${bestHeight}p' : 'inconnue',
    score: double.parse(score.toStringAsFixed(1)),
    error: error,
  );
}

/// Contrôleur WebView du test de streaming, partagé par les deux moteurs.
///
/// iOS : sans `allowsInlineMediaPlayback` la vidéo part en plein écran natif
/// et l'utilisateur perd de vue le test. Android : sans
/// `setMediaPlaybackRequiresUserGesture(false)`, `playVideo()` déclenché par
/// du JS est bloqué faute de geste utilisateur, et aucun palier ne démarrerait
/// jamais.
WebViewController buildStreamingWebViewController({
  required void Function(JavaScriptMessage message) onMessage,
}) {
  final params = WebViewPlatform.instance is WebKitWebViewPlatform
      ? WebKitWebViewControllerCreationParams(
          allowsInlineMediaPlayback: true,
          mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
        )
      : const PlatformWebViewControllerCreationParams();

  final controller = WebViewController.fromPlatformCreationParams(params)
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..setBackgroundColor(const Color(0xFF000000))
    ..addJavaScriptChannel('YeleStream', onMessageReceived: onMessage);

  final platform = controller.platform;
  if (platform is AndroidWebViewController) {
    platform.setMediaPlaybackRequiresUserGesture(false);
  }

  return controller;
}

/// Sert la page hôte du lecteur sur la boucle locale, le temps du test.
///
/// L'IFrame Player API de YouTube exige une origine HTTP réelle (échange
/// `postMessage` avant `onReady`) ; le backend HLS/DASH profite du même
/// mécanisme pour charger hls.js/dash.js depuis un CDN dans un contexte propre.
/// Le port 0 laisse le système en attribuer un libre, ce qui évite tout
/// conflit avec une autre application.
class PlayerHost {
  HttpServer? _server;

  /// Démarre le serveur et retourne l'URL à charger. [builder] reçoit
  /// l'origine effective, à recopier dans le playerVar `origin` côté YouTube.
  Future<Uri> start(String Function(String origin) builder) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;

    final origin = 'http://127.0.0.1:${server.port}';
    final html = builder(origin);

    server.listen((request) async {
      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.html
        ..headers.set('Cache-Control', 'no-store')
        ..write(html);
      await request.response.close();
    });

    return Uri.parse('$origin/');
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }
}
