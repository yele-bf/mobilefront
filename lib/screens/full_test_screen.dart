import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:webview_flutter/webview_flutter.dart';

import '../models/test_selection.dart';
import '../services/device_info_service.dart';
import '../services/location_service.dart';
import '../services/network_info_service.dart';
import '../services/speed_test_api_service.dart';
import '../services/streaming_test_service.dart';
import '../theme/yele_theme.dart';
import '../widgets/streaming_table.dart';
import '../widgets/yele_scaffold.dart';
import 'score_screen.dart';

/// Écran de test (complet / débit / navigation / streaming).
/// La jauge mesure le débit ; pendant le streaming la vidéo s'affiche, et
/// pendant la navigation les pages web s'affichent réellement (WebView).
class FullTestScreen extends StatefulWidget {
  final TestSelection selection;
  final String title;
  final String route;
  final String launchLabel; // texte au centre de la jauge
  const FullTestScreen({
    super.key,
    this.selection = const TestSelection.all(),
    this.title = 'Test complet',
    this.route = '/full',
    this.launchLabel = 'LANCER LE\nTEST COMPLET',
  });

  @override
  State<FullTestScreen> createState() => _FullTestScreenState();
}

enum _Stage { idle, running }

class _FullTestScreenState extends State<FullTestScreen>
    with SingleTickerProviderStateMixin {
  final _api = SpeedTestApiService();
  final _location = LocationService();
  final _device = DeviceInfoService();
  final _net = NetworkInfoService();

  /// Pilote l'animation de la jauge : à chaque image, l'aiguille et le chiffre
  /// se rapprochent de leur cible. Un tween relancé à chaque mesure ne
  /// convenait pas — les mesures arrivent plus vite qu'il ne se termine, si
  /// bien qu'il repartait sans cesse de zéro et n'atteignait jamais sa cible.
  late final Ticker _ticker;

  /// Fraction de l'arc : `_arc` est ce qu'on affiche, `_arcTarget` ce qu'on vise.
  double _arc = 0;
  double _arcTarget = 0;

  /// Idem pour le chiffre au centre, qui doit défiler et non sauter.
  double _coreValue = 0;
  double _coreTarget = 0;

  _Stage _stage = _Stage.idle;
  String _phaseLabel = '';
  String _metricUnit = 'Mb/s';
  double _phaseProgress = 0; // avancement de la phase en cours (0-1)

  double _download = 0, _upload = 0, _ping = 0;

  String _connection = '—'; // WiFi / Mobile (par où passe Internet)
  String _fai = '—'; // FAI de connexion (déduit de l'IP)
  String _mobileNet = '—'; // Réseau mobile SIM : « 4G · Orange »

  WebViewController? _stream; // test de streaming (lecteur YouTube visible)
  WebViewController? _web; // test de navigation (pages visibles)

  // Tableau des mesures de streaming, rempli qualité par qualité pendant le test.
  List<StreamingQualityResult> _streamRows = const [];
  String? _activeQuality;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    _loadContext();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  /// Lissage exponentiel : on comble 12 % de l'écart restant à chaque image,
  /// soit une convergence en ~0,4 s quelle que soit l'ampleur du saut. On ne
  /// reconstruit l'écran que s'il y a réellement du mouvement.
  void _onTick(Duration _) {
    const k = 0.12;
    final arc = _arc + (_arcTarget - _arc) * k;
    final core = _coreValue + (_coreTarget - _coreValue) * k;
    if ((arc - _arc).abs() < 0.0002 && (core - _coreValue).abs() < 0.005) {
      return;
    }
    setState(() {
      _arc = arc;
      _coreValue = core;
    });
  }

  Future<void> _loadContext() async {
    final status = await _net.getStatus();
    final loc = await _location.getCurrentLocation();
    if (!mounted) return;
    setState(() {
      _connection = status.connectionType;
      _fai = loc?.operator.isNotEmpty == true ? loc!.operator : '—';
      _mobileNet = _formatMobile(status);
    });
  }

  /// « 4G · Orange », « 4G », ou « — » selon ce qui est disponible.
  String _formatMobile(NetworkStatus s) {
    final tech = s.cellularTech;
    final sim = s.simOperator;
    if (tech == null && (sim == null || sim.isEmpty)) return '—';
    if (sim != null && sim.isNotEmpty && tech != null) return '$tech · $sim';
    return tech ?? sim ?? '—';
  }

  /// Fixe la cible ; le Ticker se charge d'y amener l'aiguille.
  void _animateArcTo(double fraction) => _arcTarget = fraction.clamp(0.0, 1.0);

  double _fracFor(double value, double scaleMax) {
    if (value <= 0) return 0;
    if (value <= scaleMax) return value / scaleMax;
    return 1.0;
  }

  /// Garde-fou ISS-09 : ne lance le test que si la localisation est utilisable
  /// (GPS système activé + permission accordée). Retourne false si le test doit
  /// rester bloqué, après avoir montré le dialogue approprié.
  ///
  /// Sur le web (Chrome), il n'y a pas de GPS système : la vérification renvoie
  /// toujours « ok » et le test se lance comme avant (repli IP conservé).
  Future<bool> _ensureGpsAllowed() async {
    final gate = await _location.ensureGpsForTest();
    if (gate == GpsGateResult.ok) return true;

    if (!mounted) return false;

    final gpsOff = gate == GpsGateResult.gpsDisabled;
    final action = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Localisation requise'),
        content: Text(
          gpsOff
              ? 'Le GPS de votre téléphone est désactivé. Activez la localisation '
                    'pour lancer le test de mesure.'
              : 'L\'accès à la localisation est refusé. Autorisez Yélé à accéder '
                    'à votre position pour lancer le test de mesure.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('cancel'),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(gpsOff ? 'settings' : 'app'),
            child: Text(gpsOff ? 'Ouvrir les paramètres' : 'Autoriser'),
          ),
        ],
      ),
    );

    if (action == 'settings') {
      await _location.openLocationSettings();
    } else if (action == 'app') {
      await _location.openAppSettings();
    }
    // Quoi qu'il arrive, on ne démarre pas automatiquement après le retour :
    // l'utilisateur relance le test lui-même une fois le GPS activé.
    return false;
  }

  Future<void> _start() async {
    if (_stage == _Stage.running) return;
    // ISS-09 : blocage du test tant que la localisation n'est pas disponible.
    if (!await _ensureGpsAllowed()) return;
    setState(() {
      _stage = _Stage.running;
      _phaseLabel = 'Initialisation…';
      _download = _upload = _ping = 0;
      _coreValue = _coreTarget = 0;
      _arc = _arcTarget = 0;
      _phaseProgress = 0;
      _streamRows = const [];
      _activeQuality = null;
    });

    try {
      final gps = await _location.requestGpsPosition();
      final ipLoc = await _location.getCurrentLocation();
      final status = await _net.getStatus();
      final deviceModel = await _device.getDeviceModel();
      final osVersion = await _device.getOSVersion();

      if (mounted) {
        setState(() {
          _connection = status.connectionType;
          _fai = ipLoc?.operator.isNotEmpty == true ? ipLoc!.operator : _fai;
          _mobileNet = _formatMobile(status);
        });
      }

      final result = await _api.runSpeedTest(
        latitude: gps?.latitude ?? ipLoc?.latitude,
        longitude: gps?.longitude ?? ipLoc?.longitude,
        location: ipLoc != null ? '${ipLoc.city}, ${ipLoc.countryName}' : null,
        networkType: status.networkBadge,
        operator: ipLoc?.operator,
        simOperator: status.simOperator,
        cellularTech: status.cellularTech,
        deviceModel: deviceModel,
        osVersion: osVersion,
        selection: widget.selection,
        onProgress: _onProgress,
        onStreamingController: (c) {
          if (mounted) setState(() => _stream = c);
        },
        onStreamingRows: (rows) {
          if (mounted) setState(() => _streamRows = rows);
        },
        onBrowsingController: (c) {
          if (mounted) setState(() => _web = c);
        },
        // On affiche le bilan AVANT le QoE : pas d'envoi automatique ici.
        autoUpload: false,
      );

      if (!mounted) return;
      setState(() {
        _stage = _Stage.idle;
        _phaseLabel = '';
        _coreTarget = _download;
        _metricUnit = 'Mb/s';
        _phaseProgress = 1;
      });
      _animateArcTo(_fracFor(_download, 100));

      // Bilan d'abord ; le QoE et l'enregistrement se font depuis l'écran Score.
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ScoreScreen(result: result)),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.idle;
        _phaseLabel = 'Échec du test. Vérifiez la connexion.';
      });
    }
  }

  void _onProgress(SpeedTestProgress p) {
    if (!mounted) return;
    setState(() {
      _phaseLabel = p.message;
      _phaseProgress = p.phaseProgress;
      if (p.downloadSpeed != null) _download = p.downloadSpeed!;
      if (p.uploadSpeed != null) _upload = p.uploadSpeed!;
      if (p.ping != null) _ping = p.ping!;

      switch (p.phase) {
        case SpeedTestPhase.download:
          _metricUnit = 'Mb/s';
          _coreTarget = _download;
          _animateArcTo(_fracFor(_download, 100));
          break;
        case SpeedTestPhase.ping:
          _metricUnit = 'ms';
          _coreTarget = _ping;
          _animateArcTo(_fracFor(_ping, 500));
          break;
        case SpeedTestPhase.upload:
          _metricUnit = 'Mb/s';
          _coreTarget = _upload;
          _animateArcTo(_fracFor(_upload, 100));
          break;
        case SpeedTestPhase.streaming:
          // Le service annonce la qualité en cours dans son message
          // (« Lecture en 1080p… ») : on s'en sert pour surligner la colonne.
          _activeQuality =
              RegExp(r'\d{3,4}p').firstMatch(p.message)?.group(0);
          break;
        default:
          break;
      }
    });
  }

  bool get _showVideo => _stream != null;
  bool get _showWeb => _web != null;

  @override
  Widget build(BuildContext context) {
    return YeleScaffold(
      title: widget.title,
      route: widget.route,
      body: Container(
        decoration: const BoxDecoration(gradient: YeleColors.testGradient),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              children: [
                if (_stage == _Stage.running && _phaseLabel.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 0, 0),
                      child: Text(_phaseLabel.toUpperCase(),
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1,
                              fontSize: 14)),
                    ),
                  ),
                _centerArea(),
                if (_streamRows.isNotEmpty)
                  StreamingTable(
                    qualities: _streamRows,
                    activeLabel: _activeQuality,
                  ),
                _serverBar(),
                _metrics(),
                _bottomInfo(),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _centerArea() {
    if (_showVideo) return _videoCard();
    if (_showWeb) return _webCard();
    // Tests streaming / navigation : bouton START simple (façon nPerf),
    // pas de compteur de vitesse (qui n'a de sens que pour le débit).
    if (!widget.selection.speed) return _startButton();
    return _gauge();
  }

  Widget _startButton() {
    final running = _stage == _Stage.running;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Center(
        child: GestureDetector(
          onTap: running ? null : _start,
          child: Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                center: Alignment(0, -0.3),
                colors: [Color(0xFF3A4636), Color(0xFF1C2419)],
              ),
              border: Border.all(color: YeleColors.testBot, width: 6),
              boxShadow: const [
                BoxShadow(color: Colors.black38, blurRadius: 16, offset: Offset(0, 8)),
              ],
            ),
            alignment: Alignment.center,
            child: running
                ? const CircularProgressIndicator(color: Colors.white)
                : Text(widget.launchLabel,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        height: 1.15)),
          ),
        ),
      ),
    );
  }

  /// Lecteur YouTube pendant le test de streaming (16:9, comme nPerf).
  Widget _videoCard() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            children: [
              Container(color: Colors.black),
              WebViewWidget(controller: _stream!),
              _badge('● TEST STREAMING'
                  '${_activeQuality != null ? ' $_activeQuality' : ''}'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _webCard() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: 360,
          width: double.infinity,
          child: Stack(
            children: [
              WebViewWidget(controller: _web!),
              _badge('● TEST NAVIGATION WEB'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _badge(String text) {
    return Positioned(
      top: 8,
      left: 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(text,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _gauge() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
      child: SizedBox(
        width: 320,
        height: 320,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: const Size(320, 320),
              painter: _GaugePainter(_arc),
            ),
            GestureDetector(
              onTap: _stage == _Stage.idle ? _start : null,
              child: Container(
                width: 165,
                height: 165,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const RadialGradient(
                    center: Alignment(0, -0.3),
                    colors: [Color(0xFF3A4636), Color(0xFF1C2419)],
                  ),
                  border: Border.all(color: const Color(0xFF5B6B4D), width: 6),
                ),
                alignment: Alignment.center,
                child: _coreContent(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _coreContent() {
    if (_stage == _Stage.idle) {
      return Text(widget.launchLabel,
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 18,
              height: 1.15));
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(_coreValue.toStringAsFixed(_metricUnit == 'ms' ? 0 : 2),
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w800, fontSize: 34)),
        Text(_metricUnit,
            style: const TextStyle(color: Colors.white70, fontSize: 13)),
        if (_phaseProgress > 0) ...[
          const SizedBox(height: 6),
          Text('${(_phaseProgress * 100).round()} %',
              style: const TextStyle(
                  color: YeleColors.testTop,
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
        ],
      ],
    );
  }

  Widget _serverBar() {
    return Container(
      color: const Color(0xFFEEF1EE),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Container(width: 26, height: 20, color: const Color(0xFF5A6B3A)),
          const SizedBox(width: 10),
          const Expanded(
            child: Text('[BF] yele_serveur — Ouagadougou',
                style: TextStyle(color: Color(0xFF33402A), fontSize: 13)),
          ),
          const Text('🇧🇫', style: TextStyle(fontSize: 18)),
        ],
      ),
    );
  }

  Widget _metrics() {
    Widget cell(String label, double value, String unit, Color color) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          decoration: const BoxDecoration(
            border: Border(right: BorderSide(color: Color(0xFFD7DDCF))),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF33402A),
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              SizedBox(height: 30, child: _miniBar(value, color)),
              const SizedBox(height: 4),
              Text(
                  value > 0
                      ? '${value.toStringAsFixed(unit == 'ms' ? 0 : 1)} $unit'
                      : '—',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: YeleColors.ink)),
            ],
          ),
        ),
      );
    }

    return Container(
      color: const Color(0xFFEEF1EE),
      child: Row(
        children: [
          cell('▼ Download', _download, 'Mb/s', YeleColors.accent),
          cell('▲ Upload', _upload, 'Mb/s', YeleColors.good),
          cell('↔ Latence', _ping, 'ms', YeleColors.muted),
        ],
      ),
    );
  }

  Widget _miniBar(double value, Color color) {
    final frac = _fracFor(value, value > 100 ? value : 100);
    return Align(
      alignment: Alignment.bottomLeft,
      child: FractionallySizedBox(
        widthFactor: 1,
        heightFactor: value > 0 ? (0.25 + 0.75 * frac) : 0.06,
        child: Container(
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ),
    );
  }

  Widget _bottomInfo() {
    Widget c(String label, String value) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: const BoxDecoration(
            border: Border(right: BorderSide(color: YeleColors.line)),
          ),
          child: Column(
            children: [
              Text(label,
                  style: const TextStyle(
                      color: YeleColors.field,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(value,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF2C3650), fontSize: 12)),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: const BoxDecoration(
        color: YeleColors.panel,
        border: Border(top: BorderSide(color: YeleColors.primary, width: 2)),
      ),
      child: Row(
        children: [
          c('Connexion', _connection),
          c('FAI', _fai),
          c('Réseau mobile', _mobileNet),
        ],
      ),
    );
  }
}

/// Peint l'arc de la jauge (270°, dégradé cyan→lime) et les graduations.
class _GaugePainter extends CustomPainter {
  final double fraction;
  _GaugePainter(this.fraction);

  static const double _startDeg = 135;
  static const double _sweepDeg = 270;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 30;
    const stroke = 40.0;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final startRad = _startDeg * math.pi / 180;
    final sweepRad = _sweepDeg * math.pi / 180;

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = const Color(0xFF2B3520).withValues(alpha: 0.55);
    canvas.drawArc(rect, startRad, sweepRad, false, track);

    final tick = Paint()
      ..color = const Color(0xFFC9D97F)
      ..strokeWidth = 2;
    for (int i = 0; i <= 60; i++) {
      final a = (_startDeg + i * (_sweepDeg / 60)) * math.pi / 180;
      final p1 = center + Offset(math.cos(a), math.sin(a)) * (radius - 22);
      final p2 = center + Offset(math.cos(a), math.sin(a)) * (radius - 12);
      canvas.drawLine(p1, p2, tick);
    }

    if (fraction > 0) {
      final arc = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = const SweepGradient(
          startAngle: 0,
          endAngle: math.pi * 2,
          colors: [YeleColors.accent, YeleColors.testBot],
          transform: GradientRotation(_startDeg * math.pi / 180),
        ).createShader(rect);
      canvas.drawArc(rect, startRad, sweepRad * fraction, false, arc);
    }
  }

  @override
  bool shouldRepaint(_GaugePainter old) => old.fraction != fraction;
}
