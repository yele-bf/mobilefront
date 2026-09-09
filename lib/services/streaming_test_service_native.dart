import 'dart:async';
import 'dart:convert';
import 'dart:io' show ContentType, HttpServer, InternetAddress;
import 'dart:ui' show Color;

import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import '../constants/config.dart';
import 'streaming_test_service.dart';

/// Implémentation native (Android, iOS, macOS) du test de streaming : le
/// lecteur YouTube tourne dans une [WebViewController] visible à l'écran.
///
/// La page hôte est servie par un petit serveur HTTP local ([_PlayerHost]) :
/// l'IFrame API valide l'origine de la page hôte par un échange `postMessage`
/// avant d'émettre `onReady`. Une page injectée via `loadHtmlString` — même
/// avec un `baseUrl` pointant sur youtube.com — n'a pas d'origine réelle : la
/// validation échoue silencieusement, le lecteur reste noir et `onReady`
/// n'arrive jamais. D'où le serveur local, qui fournit une vraie origine HTTP.
class NativeStreamingRunner extends StreamingRunner {
  WebViewController? _controller;
  _PlayerHost? _host;

  @override
  Future<void> openPlayer(StreamingControllerCallback? onController) async {
    final controller = _buildController();
    _controller = controller;

    final host = _PlayerHost();
    _host = host;

    final uri = await host.start(_playerHtml);
    await controller.loadRequest(uri);
    onController?.call(NativeStreamingDisplay(controller: controller));
  }

  @override
  Future<void> closePlayer() async {
    await _host?.stop();
    _host = null;
    _controller = null;
  }

  @override
  Future<void> jsBuildLevel(String key, int width, int height) =>
      _controller!.runJavaScript('buildLevel("$key", $width, $height)');

  @override
  Future<void> jsStartLevel(String key) =>
      _controller!.runJavaScript('startLevel("$key")');

  @override
  Future<Map<String, dynamic>> jsStopLevel() async {
    try {
      await _controller!.runJavaScript('stopLevel()');
      return await waitLevelReport();
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  WebViewController _buildController() {
    // iOS : sans `allowsInlineMediaPlayback` la vidéo part en plein écran natif
    // et l'utilisateur perd de vue le test.
    final params = WebViewPlatform.instance is WebKitWebViewPlatform
        ? WebKitWebViewControllerCreationParams(
            allowsInlineMediaPlayback: true,
            mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
          )
        : const PlatformWebViewControllerCreationParams();

    final controller = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF000000))
      ..addJavaScriptChannel('YeleStream', onMessageReceived: _onJsMessage);

    // Android : sans ceci, `playVideo()` déclenché par du JS est bloqué faute
    // de geste utilisateur, et aucun palier ne démarrerait jamais.
    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      platform.setMediaPlaybackRequiresUserGesture(false);
    }

    return controller;
  }

  void _onJsMessage(JavaScriptMessage message) {
    Map<String, dynamic> event;
    try {
      event = Map<String, dynamic>.from(jsonDecode(message.message) as Map);
    } catch (_) {
      return;
    }
    handleEvent(event);
  }

  /// Page hôte du lecteur YouTube, servie par [_PlayerHost] depuis
  /// `http://127.0.0.1:<port>`.
  String _playerHtml(String origin) => '''
<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1, user-scalable=no">
<style>
  html,body{margin:0;padding:0;background:#000;overflow:hidden;height:100%}
  /* Le lecteur est RÉELLEMENT dimensionné en 1920x1080, puis réduit
     visuellement par une transformation. YouTube choisit sa qualité d'après
     la taille du lecteur : une zone de quelques centaines de pixels de large
     ne se voit jamais servir de 1080p, encore moins de 2160p. Sans cette
     mise à l'échelle, le test plafonnerait à 360p quelle que soit la
     qualité demandée, et les colonnes resteraient vides. */
  #stage{position:absolute;top:0;left:0;width:1920px;height:1080px;
         transform-origin:0 0}
  #player{width:100%;height:100%}
</style>
</head>
<body>
<div id="stage"><div id="player"></div></div>
<script>
var player = null;
var stageW = 1920, stageH = 1080;
var t0 = 0, startupMs = -1, bufferMs = 0, bufferStart = 0;
var rebuffers = 0, started = false;

// Durée passée dans chaque qualité pendant la fenêtre mesurée. YouTube peut
// basculer en cours de lecture : sans ce suivi, on attribuerait à une qualité
// des chiffres qui en mélangent deux.
var qSegments = [], curQ = null, curQStart = 0;

function send(o) { YeleStream.postMessage(JSON.stringify(o)); }

// Sans ceci, un échec de chargement du script de l'API serait indiscernable
// d'un simple dépassement de délai.
window.onerror = function (msg) { send({ e: 'jserror', msg: String(msg) }); };

// La taille du lecteur pilote le choix de qualité de YouTube : un lecteur
// 1280x720 obtient du 720p, un lecteur 3840x2160 rend le 4K envisageable.
// La scène garde ses dimensions réelles et n'est réduite qu'à l'affichage.
function setStage(w, h) {
  stageW = w; stageH = h;
  var stage = document.getElementById('stage');
  stage.style.width = w + 'px';
  stage.style.height = h + 'px';
  fitStage();
}

function fitStage() {
  document.getElementById('stage').style.transform =
    'scale(' + (window.innerWidth / stageW) + ')';
}
window.addEventListener('resize', fitStage);

function onYouTubeIframeAPIReady() { send({ e: 'ready' }); }

// Reconstruit un lecteur NEUF pour chaque qualité. Réutiliser le même lecteur
// laissait l'algorithme adaptatif de YouTube conserver son estimation de
// bande passante d'un palier à l'autre : après un palier en 4K il restait
// haut, et inversement. Les paliers se contaminaient, d'où des résultats
// différents d'un test à l'autre.
function buildLevel(q, w, h) {
  if (player && player.destroy) { try { player.destroy(); } catch (e) {} }
  player = null;
  document.getElementById('stage').innerHTML = '<div id="player"></div>';
  setStage(w, h);

  startupMs = -1; bufferMs = 0; bufferStart = 0; rebuffers = 0;
  started = false; qSegments = []; curQ = null; curQStart = 0;

  player = new YT.Player('player', {
    width: String(w),
    height: String(h),
    videoId: '$STREAMING_YOUTUBE_VIDEO_ID',
    playerVars: {
      autoplay: 0, controls: 0, disablekb: 1, fs: 0,
      modestbranding: 1, playsinline: 1, rel: 0, iv_load_policy: 3,
      enablejsapi: 1, origin: '$origin', vq: q
    },
    events: {
      onReady: function () { send({ e: 'levelready' }); },
      onStateChange: onState,
      onPlaybackQualityChange: function (ev) { markQuality(ev.data); },
      onError: function (ev) { send({ e: 'error', code: ev.data }); }
    }
  });
}

function markQuality(q) {
  var now = Date.now();
  if (curQ !== null) {
    var ms = now - curQStart;
    for (var i = 0; i < qSegments.length; i++) {
      if (qSegments[i].q === curQ) { qSegments[i].ms += ms; curQ = null; break; }
    }
    if (curQ !== null) qSegments.push({ q: curQ, ms: ms });
  }
  curQ = q; curQStart = now;
}

// Qualité ayant duré le plus longtemps sur la fenêtre mesurée.
function dominantQuality() {
  var best = null;
  for (var i = 0; i < qSegments.length; i++) {
    if (!best || qSegments[i].ms > best.ms) best = qSegments[i];
  }
  return best ? best.q : 'unknown';
}

function onState(ev) {
  var s = ev.data;
  if (s === YT.PlayerState.PLAYING) {
    if (startupMs < 0) {
      startupMs = Date.now() - t0;
      started = true;
      try { markQuality(player.getPlaybackQuality()); } catch (e) {}
      send({ e: 'start', startupMs: startupMs });
    }
    // Sortie de mise en tampon : on referme le chrono.
    if (bufferStart > 0) { bufferMs += Date.now() - bufferStart; bufferStart = 0; }
  } else if (s === YT.PlayerState.BUFFERING) {
    // Le buffering d'amorçage fait partie du « chargement initial », pas des
    // interruptions : on ne compte que ce qui survient après la 1re image.
    if (started && bufferStart === 0) { bufferStart = Date.now(); rebuffers++; }
  }
}

function startLevel(q) {
  t0 = Date.now();
  try { player.setPlaybackQualityRange(q, q); } catch (e) {}
  try { player.setPlaybackQuality(q); } catch (e) {}
  player.playVideo();
}

function stopLevel() {
  if (!player) { send({ e: 'level', q: 'unknown', segments: 0 }); return; }
  if (bufferStart > 0) { bufferMs += Date.now() - bufferStart; bufferStart = 0; }
  markQuality(null); // referme le segment en cours

  var avail = '';
  try { avail = player.getAvailableQualityLevels().join(','); } catch (e) {}
  try { player.pauseVideo(); } catch (e) {}

  send({
    e: 'level', startupMs: startupMs < 0 ? 0 : startupMs,
    bufferMs: bufferMs, rebuffers: rebuffers,
    q: dominantQuality(), segments: qSegments.length, avail: avail
  });
}
</script>
<script src="https://www.youtube.com/iframe_api"></script>
</body>
</html>
''';
}

/// Sert la page hôte du lecteur sur la boucle locale, le temps du test.
///
/// L'unique raison d'être de ce serveur est de donner à la page une **origine
/// HTTP réelle** : l'IFrame Player API la vérifie avant d'initialiser le
/// lecteur, et rejette les pages injectées sans origine.
class _PlayerHost {
  HttpServer? _server;

  /// Démarre le serveur et retourne l'URL à charger. [builder] reçoit
  /// l'origine effective, à recopier dans le playerVar `origin`.
  Future<Uri> start(String Function(String origin) builder) async {
    // Port 0 : le système en attribue un libre, ce qui évite tout conflit
    // avec une autre application.
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