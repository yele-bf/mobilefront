import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:logger/logger.dart';
import 'package:web/web.dart' as web;

import '../constants/config.dart';
import 'streaming_test_service.dart';

// ── Appels vers les fonctions JavaScript injectées dans la page ─────────────

@JS('buildLevel')
external void _buildLevelJs(String q, int w, int h);

@JS('startLevel')
external void _startLevelJs(String q);

@JS('stopLevel')
external void _stopLevelJs();

/// Implémentation **web** (Chrome) du test de streaming.
///
/// Le lecteur YouTube est créé directement dans la page (IFrame Player API),
/// dans un `<div>` embarqué dans l'application via [ui_web.platformViewRegistry]
/// + `HtmlElementView`. Les mesures (démarrage, mise en tampon, qualité servie)
/// sont faites par le même script JavaScript que la version WebView, qui
/// remonte ses événements par `window.postMessage`.
class WebStreamingRunner extends StreamingRunner {
  final Logger logger = Logger();

  /// Préfixe des messages du lecteur, pour ne pas confondre avec les messages
  /// internes de l'API YouTube (qui passent aussi par `window.postMessage`).
  static const String _prefix = 'YeleStream::';

  static bool _baseJsInjected = false;
  static bool _apiScriptInjected = false;
  static bool _listenerInstalled = false;

  static const String _stageId = 'yele-stage';
  web.HTMLDivElement? _stage;

  @override
  Future<void> openPlayer(StreamingControllerCallback? onController) async {
    final stage = web.HTMLDivElement()..id = _stageId;
    _stage = stage;

    // Vue unique à ce test : chaque exécution a son propre élément.
    final viewType = 'yele-stream-${DateTime.now().microsecondsSinceEpoch}';
    ui_web.platformViewRegistry.registerViewFactory(
        viewType, (int viewId) => stage);

    _installBaseJs();
    _installApiScript();
    _installListener();

    // L'écran construit le HtmlElementView → le moteur attache `stage` au DOM.
    onController?.call(WebStreamingDisplay(viewType: viewType));
    await _waitForStageAttached();
  }

  @override
  Future<void> closePlayer() async {
    _stage = null;
  }

  @override
  Future<void> jsBuildLevel(String key, int width, int height) async {
    _buildLevelJs(key, width, height);
  }

  @override
  Future<void> jsStartLevel(String key) async {
    _startLevelJs(key);
  }

  @override
  Future<Map<String, dynamic>> jsStopLevel() async {
    try {
      _stopLevelJs();
      return await waitLevelReport();
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  /// Attends que l'élément créé par la factory soit réellement dans le DOM
  /// (l'écran doit avoir construit le `HtmlElementView`). Sans cela, le script
  /// du lecteur ne trouverait pas `#yele-stage`.
  Future<void> _waitForStageAttached() async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(deadline)) {
      if (_stage?.parentNode != null) return;
      await Future.delayed(const Duration(milliseconds: 100));
    }
    // Élément introuvable : le test ne pourra rien afficher ni mesurer.
    playerError ??= 'Lecteur vidéo non affiché. Relancez le test.';
    completeReady();
  }

  /// Injecte une seule fois le script de mesure dans la page.
  void _installBaseJs() {
    if (_baseJsInjected) return;
    _baseJsInjected = true;

    final script = web.HTMLScriptElement()..text = _baseJs;
    web.document.head?.append(script);
  }

  /// Charge le script de l'IFrame Player API (une seule fois par page).
  void _installApiScript() {
    if (_apiScriptInjected) return;
    _apiScriptInjected = true;

    final script = web.HTMLScriptElement()
      ..src = 'https://www.youtube.com/iframe_api';
    script.onerror = ((web.Event _) {
      playerError ??= 'API YouTube injoignable. Vérifiez la connexion.';
      completeReady();
    }).toJS;
    web.document.head?.append(script);
  }

  /// Écoute une seule fois les événements du lecteur remontés par la page.
  void _installListener() {
    if (_listenerInstalled) return;
    _listenerInstalled = true;

    web.window.addEventListener('message', ((web.MessageEvent e) {
      final raw = e.data?.toString();
      if (raw == null || !raw.startsWith(_prefix)) return;
      final payload = raw.substring(_prefix.length);
      try {
        handleEvent(Map<String, dynamic>.from(jsonDecode(payload) as Map));
      } catch (_) {
        // Message illisible : on ignore.
      }
    }).toJS);
  }

  /// Script de mesure, injecté dans la page (équivalent web de la page hôte
  /// servie par la version WebView). Les événements remontent par
  /// `window.postMessage` avec le préfixe [_prefix].
  ///
  /// ⚠️ Autoplay muet (`autoplay: 1, mute: 1`) : Chrome autorise toujours la
  /// lecture automatique sans le son, alors qu'une `playVideo()` avec le son
  /// peut être bloquée hors fenêtre de geste utilisateur. La qualité servie
  /// par YouTube ne dépend pas du son.
  String get _baseJs => '''
var player = null;
var stageW = 1920, stageH = 1080;
var t0 = 0, startupMs = -1, bufferMs = 0, bufferStart = 0;
var rebuffers = 0, started = false;

// Durée passée dans chaque qualité pendant la fenêtre mesurée. YouTube peut
// basculer en cours de lecture : sans ce suivi, on attribuerait à une qualité
// des chiffres qui en mélangent deux.
var qSegments = [], curQ = null, curQStart = 0;

function send(o) { window.postMessage('$_prefix' + JSON.stringify(o), '*'); }

// Chaîne le handler d'erreur existant (Flutter en installe un) au lieu de
// l'écraser : sinon les erreurs de l'application passeraient inaperçues.
var prevOnerror = window.onerror;
window.onerror = function (msg, src, line, col, err) {
  try { send({ e: 'jserror', msg: String(msg) }); } catch (e) {}
  if (prevOnerror) { try { return prevOnerror(msg, src, line, col, err); } catch (e) {} }
  return false;
};

// Le lecteur est RÉELLEMENT dimensionné en 1920x1080 puis réduit à l'échelle
// du conteneur. YouTube choisit sa qualité d'après la taille du lecteur :
// sans cette mise à l'échelle, un petit conteneur ne se verrait jamais servir
// de 1080p, encore moins de 2160p.
function initStage() {
  var stage = document.getElementById('$_stageId');
  if (!stage) return;
  stage.style.position = 'relative';
  stage.style.width = '100%';
  stage.style.height = '100%';
  stage.style.overflow = 'hidden';
  stage.style.background = '#000';
  stage.innerHTML = '<div id="yele-player-wrap" style="position:absolute;top:0;left:0;width:1920px;height:1080px;transform-origin:0 0"><div id="player"></div></div>';
  if (window.ResizeObserver) {
    try { new ResizeObserver(fitStage).observe(stage); } catch (e) {}
  } else {
    window.addEventListener('resize', fitStage);
  }
  fitStage();
}

function fitStage() {
  var stage = document.getElementById('$_stageId');
  if (!stage) return;
  var wrap = document.getElementById('yele-player-wrap');
  if (!wrap) return;
  var scale = (stage.clientWidth || stageW) / stageW;
  wrap.style.transform = 'scale(' + scale + ')';
}

function onYouTubeIframeAPIReady() { send({ e: 'ready' }); }

// Reconstruit un lecteur NEUF pour chaque qualité. Réutiliser le même lecteur
// laissait l'algorithme adaptatif de YouTube conserver son estimation de
// bande passante d'un palier à l'autre : les paliers se contaminaient.
function buildLevel(q, w, h) {
  if (player && player.destroy) { try { player.destroy(); } catch (e) {} }
  player = null;
  var wrap = document.getElementById('yele-player-wrap');
  if (!wrap) { initStage(); wrap = document.getElementById('yele-player-wrap'); }
  wrap.innerHTML = '<div id="player"></div>';
  stageW = w; stageH = h;
  fitStage();

  startupMs = -1; bufferMs = 0; bufferStart = 0; rebuffers = 0;
  started = false; qSegments = []; curQ = null; curQStart = 0;

  player = new YT.Player('player', {
    width: String(w),
    height: String(h),
    videoId: '$STREAMING_YOUTUBE_VIDEO_ID',
    playerVars: {
      autoplay: 1, controls: 0, disablekb: 1, fs: 0,
      modestbranding: 1, playsinline: 1, rel: 0, iv_load_policy: 3,
      enablejsapi: 1, mute: 1, vq: q
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
  // Fenêtre de mesure propre : on remet les compteurs à zéro au moment où le
  // palier démarre, même si la lecture (autoplay muet) a déjà commencé.
  qSegments = []; curQ = null; curQStart = Date.now();
  bufferMs = 0; bufferStart = 0; rebuffers = 0;
  started = true; startupMs = 0;
  try { markQuality(player.getPlaybackQuality()); } catch (e) {}
  if (player.getPlayerState && player.getPlayerState() === 1) {
    send({ e: 'start', startupMs: 0 });
  } else {
    player.playVideo();
  }
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

// API déjà chargée (test précédent dans la même page) : l'API n'appellera pas
// onYouTubeIframeAPIReady une seconde fois.
if (window.YT && YT.Player) { send({ e: 'ready' }); }
''';
}