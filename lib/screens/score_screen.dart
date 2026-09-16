import 'package:flutter/material.dart';

import '../models/speed_test_result.dart';
import '../services/dashboard_api_service.dart';
import '../services/local_storage_service.dart';
import '../services/speed_test_api_service.dart';
import '../theme/yele_theme.dart';
import '../widgets/export_sheet.dart';
import '../widgets/qoe_dialog.dart';
import '../widgets/streaming_table.dart';
import '../widgets/yele_scaffold.dart';

/// Écran "Score" — bilan d'un test, affiché AVANT le questionnaire QoE.
/// L'utilisateur consulte ses résultats, puis évalue la qualité ressentie ;
/// l'enregistrement local + envoi au serveur ont lieu à ce moment-là.
/// Choix « ne montrer que le mesurable » : note de qualité dérivée du débit,
/// pas de score en points arbitraire.
class ScoreScreen extends StatefulWidget {
  final SpeedTestResult result;
  const ScoreScreen({super.key, required this.result});

  @override
  State<ScoreScreen> createState() => _ScoreScreenState();
}

class _ScoreScreenState extends State<ScoreScreen> {
  final _api = SpeedTestApiService();
  final _storage = LocalStorageService();
  final _dashboard = DashboardApiService();
  BarometerResult? _barometer;
  bool _saved = false;
  bool _qoeDone = false;

  SpeedTestResult get r => widget.result;

  bool get _speedDone => r.downloadSpeed > 0 || r.uploadSpeed > 0;

  @override
  void initState() {
    super.initState();
    // IMP-11 — Baromètre : situe le résultat par rapport à la base dès
    // l'ouverture du bilan. Non bloquant : la carte n'apparaît que si
    // l'API répond (et seulement pour un test de débit).
    if (_speedDone) {
      _dashboard
          .fetchBarometer(r.downloadSpeed, r.uploadSpeed, r.ping)
          .then((v) {
        if (mounted && v != null) setState(() => _barometer = v);
      });
    }
  }

  Future<void> _finalize() async {
    if (_saved) return;
    _saved = true;
    try {
      await _storage.saveResult(r);
      r.isUploaded = await _api.uploadTestResult(r);
    } catch (_) {
      // Échec d'enregistrement non bloquant pour l'affichage.
    }
  }

  Future<void> _openQoe() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => QoeDialog(
        onCompleted: (rating, usage, satisfaction) {
          r.qoeRating = rating;
          r.qoeUsage = usage;
          r.qoeSatisfaction = satisfaction;
        },
      ),
    );
    await _finalize();
    if (!mounted) return;
    setState(() => _qoeDone = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Résultat enregistré ✓')),
    );
  }

  // ── Qualité dérivée du débit descendant (seuils documentés) ──
  ({String label, Color color}) get _quality {
    final d = r.downloadSpeed;
    if (d >= 50) return (label: 'Excellent', color: YeleColors.good);
    if (d >= 20) return (label: 'Très bon', color: YeleColors.testBot);
    if (d >= 10) return (label: 'Bon', color: YeleColors.warn);
    if (d >= 4) return (label: 'Moyen', color: YeleColors.g4);
    return (label: 'Faible', color: YeleColors.danger);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, _) => _finalize(),
      child: YeleScaffold(
        title: 'Résultat du test',
        route: '/full',
        body: Container(
          decoration: const BoxDecoration(gradient: YeleColors.testGradient),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  _serverBar(),
                  // N'affiche que les sections du/des test(s) réellement faits.
                  if (_speedDone) ...[_metrics(), _qualityBand()],
                  // IMP-11 — Baromètre de comparaison « mon résultat vs les autres ».
                  if (_speedDone) _barometerCard(),
                  // Affiché aussi en cas d'échec, pour en montrer la raison.
                  if (r.hasStreamingTest || r.streamingError != null)
                    _streamingCard(),
                  if (r.hasBrowsingTest) _browsingCard(),
                  _bottomInfo(),
                  _deviceBar(),
                  _actions(),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _serverBar() {
    final loc = (r.location?.isNotEmpty == true) ? r.location! : 'Ouagadougou';
    return Container(
      color: YeleColors.panel,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(width: 26, height: 20, color: const Color(0xFF16557E)),
          const SizedBox(width: 10),
          Expanded(
            child: Text('[BF] yele_serveur — $loc',
                style: const TextStyle(color: Color(0xFF33402A), fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _metrics() {
    Widget m(String label, String val, String unit, String sub) {
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          child: Column(
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF2C3650),
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(val,
                  style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: YeleColors.field,
                      height: 1.1)),
              Text(unit,
                  style: const TextStyle(fontSize: 13, color: YeleColors.field)),
              const SizedBox(height: 3),
              Text(sub,
                  style: TextStyle(fontSize: 11, color: YeleColors.surface.muted)),
            ],
          ),
        ),
      );
    }

    return Container(
      color: YeleColors.panel,
      child: Column(
        children: [
          Row(
            children: [
              m('▼ Download', r.downloadSpeed.toStringAsFixed(2), 'Mb/s', ''),
              m('▲ Upload', r.uploadSpeed.toStringAsFixed(2), 'Mb/s', ''),
              m('↔ Latence', r.ping.toStringAsFixed(0), 'ms',
                  'Gigue : ${r.jitter.toStringAsFixed(0)} ms'),
            ],
          ),
          // IMP-01 : données consommées par le test (Android ; « — » sur iOS).
          if (r.dataUsedKiB != null && r.dataUsedKiB! >= 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 10),
              child: Text(
                '📊 Données consommées : ${_formatData(r.dataUsedKiB!)}',
                style: const TextStyle(
                    color: Color(0xFF2C3650),
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
              ),
            ),
        ],
      ),
    );
  }

  /// IMP-01 : formatage lisible d'un volume en KiB (Mo au-delà de 1 Mo).
  String _formatData(int kib) {
    if (kib >= 1024) {
      return '${(kib / 1024).toStringAsFixed(1)} Mo';
    }
    return '$kib Ko';
  }

  // ── IMP-11 : baromètre de comparaison ─────────────────────────────────

  /// Carte « Baromètre » : position du résultat par rapport à toutes les
  /// mesures de la base. Silencieuse tant que l'API n'a pas répondu.
  Widget _barometerCard() {
    final b = _barometer;
    if (b == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('📊', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Text('Baromètre',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: YeleColors.surface.ink)),
              const Spacer(),
              Text('${b.sampleSize} mesures',
                  style: TextStyle(
                      fontSize: 12, color: YeleColors.surface.muted)),
            ],
          ),
          const SizedBox(height: 10),
          _barometerRow('▼ Download', b.downloadPercentile,
              'plus rapide que ${b.downloadPercentile.toStringAsFixed(0)} % des mesures'),
          _barometerRow('▲ Upload', b.uploadPercentile,
              'plus rapide que ${b.uploadPercentile.toStringAsFixed(0)} % des mesures'),
          _barometerRow('↔ Latence', b.pingPercentile,
              'meilleure que ${b.pingPercentile.toStringAsFixed(0)} % des mesures'),
        ],
      ),
    );
  }

  /// Une ligne du baromètre : métrique + mini-jauge de centile.
  Widget _barometerRow(String label, double percentile, String caption) {
    final color = percentile >= 75
        ? YeleColors.good
        : percentile >= 40
            ? YeleColors.warn
            : YeleColors.danger;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 92,
                child: Text(label,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: YeleColors.surface.ink)),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (percentile / 100).clamp(0.0, 1.0),
                    minHeight: 8,
                    backgroundColor: YeleColors.surface.line,
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                ),
              ),
              SizedBox(
                width: 46,
                child: Text('${percentile.toStringAsFixed(0)} %',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: color)),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(caption,
              style: TextStyle(fontSize: 11, color: YeleColors.surface.muted)),
        ],
      ),
    );
  }

  Widget _qualityBand() {
    final q = _quality;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1C2419), Color(0xFF10160D)],
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Container(
          width: 160,
          height: 160,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const RadialGradient(
              center: Alignment(0, -0.2),
              colors: [Color(0xFF1C2419), Color(0xFF0C1108)],
            ),
            border: Border.all(color: q.color, width: 7),
          ),
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('QUALITÉ',
                  style: TextStyle(
                      color: Colors.white70, fontSize: 12, letterSpacing: 0.5)),
              const SizedBox(height: 4),
              Text(q.label,
                  style: TextStyle(
                      color: q.color, fontSize: 26, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text('${r.downloadSpeed.toStringAsFixed(1)} Mb/s',
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  // Carte de résultat d'un test, avec en-tête coloré et lignes clé/valeur.
  Widget _resultCard(String icon, String title, Color color, double score,
      List<({String k, String v})> lines) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10)],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: color,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Text(icon, style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 8),
                Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
                const Spacer(),
                Text('${score.toStringAsFixed(0)}/100',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                for (final l in lines)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(l.k,
                            style: TextStyle(
                                color: YeleColors.surface.muted, fontSize: 13)),
                        Text(l.v,
                            style: TextStyle(
                                color: YeleColors.surface.ink,
                                fontSize: 13,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Streaming : tableau par qualité (720p/1080p/2160p), façon nPerf.
  /// Repli sur l'ancienne carte pour les résultats enregistrés avant ce test.
  Widget _streamingCard() {
    final rows = r.streamingQualities;
    final error = r.streamingError;
    if (rows.isEmpty && error != null) return _streamingError(error);
    if (rows.isEmpty) {
      return _resultCard('🎬', 'Streaming vidéo', YeleColors.g5,
          r.streamingScore ?? 0, [
        (k: 'Résolution max soutenue', v: r.streamingMaxResolution ?? '—'),
        (k: 'Démarrage', v: '${r.streamingStartupMs ?? 0} ms'),
        (k: 'Interruptions', v: '${r.streamingRebufferCount ?? 0}'),
      ]);
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
          child: Row(
            children: [
              const Text('🎬', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              const Text('Streaming vidéo',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
              const Spacer(),
              Text('${(r.streamingScore ?? 0).toStringAsFixed(0)}/100',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800)),
            ],
          ),
        ),
        StreamingTable(qualities: rows),
        if (error != null) _streamingError(error),
      ],
    );
  }

  /// Explique un test de streaming sans mesure : sans ce message, un échec
  /// technique ressemblerait à un réseau simplement trop faible.
  Widget _streamingError(String message) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: YeleColors.warn, width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: YeleColors.warn, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: TextStyle(fontSize: 13, color: YeleColors.surface.ink)),
          ),
        ],
      ),
    );
  }

  Widget _browsingCard() {
    return _resultCard('🌐', 'Navigation web', YeleColors.primary,
        r.browsingScore ?? 0, [
      (
        k: 'Temps de chargement moyen',
        v: '${((r.browsingAvgLoadMs ?? 0) / 1000).toStringAsFixed(1)} s'
      ),
      (
        k: 'Taux de réussite',
        v: '${((r.browsingSuccessRate ?? 0) * 100).toStringAsFixed(0)} %'
      ),
      (k: 'Pages testées', v: '${r.browsingPagesTested ?? 0}'),
    ]);
  }

  Widget _bottomInfo() {
    Widget c(String label, String value) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            border: Border(right: BorderSide(color: YeleColors.surface.line)),
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
      decoration: BoxDecoration(
        color: YeleColors.surface.panel,
        border: Border(top: BorderSide(color: YeleColors.primary, width: 2)),
      ),
      child: Row(
        children: [
          c('Connexion', r.networkType ?? '—'),
          c('FAI', r.operator ?? '—'),
          c('Réseau mobile', _mobileLabel),
        ],
      ),
    );
  }

  /// IMP-13 / retour produit : rappel de l'appareil sous le bandeau d'infos.
  Widget _deviceBar() {
    final device = r.deviceModel;
    final os = r.osVersion;
    final label = [
      if (device != null && device.isNotEmpty) device,
      if (os != null && os.isNotEmpty) os,
    ].join(' · ');
    if (label.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      color: YeleColors.surface.panel,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
      child: Text(label,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: YeleColors.surface.muted)),
    );
  }

  /// « 4G · Orange », « 4G », ou « — » selon les mesures disponibles.
  String get _mobileLabel {
    final tech = r.cellularTech;
    final sim = r.simOperator;
    if ((tech == null || tech.isEmpty) && (sim == null || sim.isEmpty)) {
      return '—';
    }
    if (sim != null && sim.isNotEmpty && tech != null && tech.isNotEmpty) {
      return '$tech · $sim';
    }
    return (tech != null && tech.isNotEmpty) ? tech : sim!;
  }

  Widget _actions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: Column(
        children: [
          // IMP-13 — Export de la mesure, façon nPerf : proposé dès le bilan
          // (l'export d'un résultat échoué reste possible : les champs mesurés
          // et la raison d'échec sont dans la mesure).
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                await _finalize();
                if (mounted) showExportSheet(context, r);
              },
              icon: const Icon(Icons.ios_share),
              label: const Text('Exporter la mesure'),
              style: OutlinedButton.styleFrom(
                foregroundColor: YeleColors.ink,
                backgroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _qoeDone ? null : _openQoe,
              icon: Icon(_qoeDone ? Icons.check_circle : Icons.rate_review),
              label: Text(_qoeDone
                  ? 'Évaluation enregistrée'
                  : 'Évaluer la qualité (QoE)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: YeleColors.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: YeleColors.good,
                disabledForegroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await _finalize();
                    if (mounted) Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Recommencer'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: YeleColors.ink,
                    backgroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await _finalize();
                    if (mounted) {
                      Navigator.of(context).pushReplacementNamed('/history');
                    }
                  },
                  icon: const Icon(Icons.history),
                  label: const Text('Historique'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: YeleColors.ink,
                    backgroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
