import 'package:flutter/material.dart';

import '../constants/config.dart';
import '../models/speed_test_result.dart';
import '../services/dashboard_api_service.dart';
import '../services/device_identity_service.dart';
import '../services/local_storage_service.dart';
import '../services/packet_loss_service.dart';
import '../services/speed_test_api_service.dart';
import '../services/streaming_test_service.dart';
import '../services/yele_scoring_engine.dart';
import '../theme/yele_theme.dart';
import '../widgets/export_sheet.dart';
import '../widgets/navigation_explanation_sheet.dart';
import '../widgets/qoe_dialog.dart';
import '../widgets/score_explanation_sheet.dart';
import '../widgets/streaming_explanation_sheet.dart';
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

  /// Segment de comparaison transmis au serveur (« wifi »/« mobile »),
  /// pour libeller l'échantillon (« mesures Wi-Fi », « mesures mobiles »).
  String? _barometerNetType;
  bool _saved = false;
  bool _qoeDone = false;

  SpeedTestResult get r => widget.result;

  bool get _speedDone => r.downloadSpeed > 0 || r.uploadSpeed > 0;

  @override
  void initState() {
    super.initState();
    // IMP-09 — Baromètre : situe le résultat par rapport à la base dès
    // l'ouverture du bilan. Non bloquant : la carte n'apparaît que si
    // l'API répond (et seulement pour un test de débit).
    if (_speedDone) {
      _fetchBarometer();
    }
  }

  /// IMP-09 — Situe le résultat dans le baromètre, comparé aux mesures de
  /// la même connexion (Wi-Fi ou mobile) et, si disponibles, aux sous-
  /// groupes opérateur × techno, de zone (~10 km) et à la tendance des 5
  /// derniers tests du même appareil.
  Future<void> _fetchBarometer() async {
    final wifi = (r.networkType ?? '').toUpperCase().contains('WIFI');
    // Comparaison à égale connexion : un test Wi-Fi n'est pas comparé à des
    // mesures 4G. Type de connexion inconnu = comparaison nationale.
    _barometerNetType =
        (r.networkType ?? '').trim().isEmpty ? null : (wifi ? 'wifi' : 'mobile');
    // Techno radio du testeur, pour le sous-groupe opérateur × techno.
    String? tech;
    if (!wifi) {
      final t = ((r.technology ?? r.cellularTech) ?? '').trim();
      tech = RegExp(r'^[2-5]G$', caseSensitive: false).hasMatch(t) ? t : null;
    }
    final uuid = await DeviceIdentityService.instance.getUuid();
    final v = await _dashboard.fetchBarometer(
      r.downloadSpeed,
      r.uploadSpeed,
      r.ping,
      operator: barometerOperatorOf(r),
      netType: _barometerNetType,
      tech: tech,
      lat: (r.latitude ?? 0) != 0 ? r.latitude : null,
      lng: (r.longitude ?? 0) != 0 ? r.longitude : null,
      streaming: r.hasStreamingTest ? r.streamingScore : null,
      browsing: r.hasBrowsingTest ? r.browsingScore : null,
      deviceId: uuid,
    );
    if (mounted && v != null) setState(() => _barometer = v);
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
                  // IMP-12 — même score qu'en historique : la valeur en points
                  // est la seule valeur de référence (docs/echelle-score.md).
                  if (r.scoringVersion != null) _scoreCard(),
                  // IMP-09 — Baromètre de comparaison « mon résultat vs les autres ».
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
    return Container(
      color: YeleColors.panel,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          const Icon(Icons.dns_outlined,
              size: 20, color: Color(0xFF16557E)),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Serveur de test : $serverRichLabel',
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
              m('↔ Latence', r.ping.toStringAsFixed(0), 'ms', [
                'Gigue : ${r.jitter.toStringAsFixed(0)} ms',
                // IMP-07 : perte de paquets, à côté du ping et de la gigue
                // comme sur nPerf.
                if (r.packetLoss != null)
                  'Perte : ${formatPacketLoss(r.packetLoss!)}',
              ].join('\n')),
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
          // ISS-06 : min / moy / max des débits et de la latence.
          _minMeanMaxTable(r),
        ],
      ),
    );
  }

  /// ISS-06 — Tableau Min / Moy / Max, une ligne par métrique mesurée.
  /// Masqué si aucune métrique n'a de min et de max (ancien résultat, test
  /// sans phase de débit).
  Widget _minMeanMaxTable(SpeedTestResult r) {
    final rows = <(String, MinMeanMax, String, int)>[
      if (r.downloadStats != null) ('▼ Download', r.downloadStats!, 'Mb/s', 2),
      if (r.uploadStats != null) ('▲ Upload', r.uploadStats!, 'Mb/s', 2),
      if (r.pingStats != null) ('↔ Latence', r.pingStats!, 'ms', 0),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();

    const head = TextStyle(
        fontSize: 11, color: Color(0xFF2C3650), fontWeight: FontWeight.w700);
    const cell = TextStyle(
        fontSize: 13, color: YeleColors.field, fontWeight: FontWeight.w700);
    Widget c(String t, TextStyle s, {TextAlign a = TextAlign.right}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
          child: Text(t, style: s, textAlign: a),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: Table(
        columnWidths: const {0: FlexColumnWidth(1.4)},
        children: [
          TableRow(children: [
            c('', head, a: TextAlign.left),
            c('Min', head),
            c('Moy', head),
            c('Max', head),
          ]),
          for (final (label, s, unit, digits) in rows)
            TableRow(children: [
              c(label, head, a: TextAlign.left),
              c(s.min.toStringAsFixed(digits), cell),
              c(s.mean.toStringAsFixed(digits), cell),
              c('${s.max.toStringAsFixed(digits)} $unit', cell),
            ]),
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

  // ── IMP-09 : baromètre de comparaison ─────────────────────────────────

  /// Carte « Baromètre » : position du résultat par rapport aux mesures de
  /// la même connexion. Silencieuse tant que l'API n'a pas répondu.
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
              Text(_sampleLabel, style: TextStyle(
                  fontSize: 12, color: YeleColors.surface.muted)),
            ],
          ),
          const SizedBox(height: 10),
          _barometerRow('▼ Download', b.downloadPercentile,
              _metricCaption(b.downloadRank, _medianOf(b.medianDownload, 'Mb/s'))),
          _barometerRow('▲ Upload', b.uploadPercentile,
              _metricCaption(b.uploadRank, _medianOf(b.medianUpload, 'Mb/s'))),
          _barometerRow('↔ Latence', b.pingPercentile,
              _metricCaption(b.pingRank, _medianOf(b.medianPing, 'ms', decimals: 0))),
          // IMP-09 v2 : les cinq indicateurs — le centile n'est demandé au
          // serveur que si le testeur a fait l'usage.
          if (r.hasStreamingTest)
            _barometerRow('▶ Streaming', b.streamingPercentile,
                'meilleur que ${b.streamingPercentile.toStringAsFixed(0)} % des tests de streaming'),
          if (r.hasBrowsingTest)
            _barometerRow('🌐 Navigation', b.browsingPercentile,
                'meilleur que ${b.browsingPercentile.toStringAsFixed(0)} % des tests de navigation'),
          // IMP-09 : même lecture, parmi les seuls clients de l'opérateur.
          if (b.hasOperatorComparison) ..._operatorBarometer(b),
          // IMP-09 v2 : comparaison de proximité, si l'échantillon suffit.
          if (b.hasZoneComparison) ..._zoneBarometer(b),
          if (b.hasTrend) _trendLine(b),
        ],
      ),
    );
  }

  /// Libellé de l'échantillon comparé, segmenté par type de connexion —
  /// seulement si le serveur confirme le filtrage ([BarometerResult.
  /// networkType]) : sinon « N mesures », sans prétendre à un segment.
  String get _sampleLabel {
    final b = _barometer!;
    switch (b.networkType) {
      case 'wifi':
        return '${b.sampleSize} mesures Wi-Fi';
      case 'mobile':
        return '${b.sampleSize} mesures mobiles';
    }
    return '${b.sampleSize} mesures';
  }

  /// « 12ᵉ sur 56 » : rang du résultat (1 = le plus rapide) sur l'échantillon.
  String _rankOf(int rank) {
    final b = _barometer!;
    if (rank <= 0 || b.sampleSize <= 1) return '';
    return '$rankᵉ sur ${b.sampleSize}';
  }

  /// « médiane 12,3 Mb/s » : valeur centrale du groupe comparé, à situer
  /// sur la barre.
  String _medianOf(double median, String unit, {int decimals = 1}) {
    if (median <= 0) return '';
    return 'médiane ${median.toStringAsFixed(decimals)} $unit';
  }

  /// Légende d'une ligne de baromètre : rang + médiane du groupe comparé.
  String _metricCaption(int rank, String medianLabel) {
    final parts = [
      _rankOf(rank),
      medianLabel,
    ].where((s) => s.isNotEmpty).toList();
    return parts.join(' · ');
  }

  /// IMP-09 — Bloc « Parmi les clients de l'opérateur », restreint à la
  /// même techno quand l'échantillon le permet, et débits moyens.
  List<Widget> _operatorBarometer(BarometerResult b) {
    final op = b.operator!;
    final muted = TextStyle(fontSize: 12, color: YeleColors.surface.muted);
    // IMP-09 v2 : sous-groupe plus fin (opérateur × techno) si l'échantillon
    // atteint minSubgroupSample — sinon le groupe opérateur entier.
    final techOk = b.hasOperatorTechComparison;
    final groupe = techOk
        ? 'les clients $op en ${b.operatorTech}'
        : 'les clients $op';
    final dl = techOk
        ? b.operatorTechDownloadPercentile
        : b.operatorDownloadPercentile;
    final ul =
        techOk ? b.operatorTechUploadPercentile : b.operatorUploadPercentile;
    final pg = techOk ? b.operatorTechPingPercentile : b.operatorPingPercentile;
    final n = techOk ? b.operatorTechSampleSize : b.operatorSampleSize;
    return [
      const Divider(height: 22),
      Row(
        children: [
          Expanded(
            child: Text(
                techOk
                    ? 'Parmi les clients $op en ${b.operatorTech}'
                    : 'Parmi les clients $op',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: YeleColors.surface.ink)),
          ),
          Text('$n mesures', style: muted),
        ],
      ),
      const SizedBox(height: 4),
      _barometerRow('▼ Download', dl,
          'plus rapide que ${dl.toStringAsFixed(0)} % de $groupe'),
      _barometerRow('▲ Upload', ul,
          'plus rapide que ${ul.toStringAsFixed(0)} % de $groupe'),
      _barometerRow('↔ Latence', pg,
          'meilleure que ${pg.toStringAsFixed(0)} % de $groupe'),
      const SizedBox(height: 6),
      Text(
        'Débit moyen ▼ : vous ${r.downloadSpeed.toStringAsFixed(1)} Mb/s · '
        '$op ${b.operatorAvgDownload.toStringAsFixed(1)} Mb/s · '
        'toutes mesures ${b.nationalAvgDownload.toStringAsFixed(1)} Mb/s',
        style: muted,
      ),
    ];
  }

  /// IMP-09 v2 — Bloc « Dans votre zone » : mesures à 10 km ou moins du
  /// test, même lecture que le bloc opérateur.
  List<Widget> _zoneBarometer(BarometerResult b) {
    final muted = TextStyle(fontSize: 12, color: YeleColors.surface.muted);
    return [
      const Divider(height: 22),
      Row(
        children: [
          Expanded(
            child: Text('Dans votre zone (10 km)',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: YeleColors.surface.ink)),
          ),
          Text('${b.zoneSampleSize} mesures', style: muted),
        ],
      ),
      const SizedBox(height: 4),
      _barometerRow('▼ Download', b.zoneDownloadPercentile,
          'plus rapide que ${b.zoneDownloadPercentile.toStringAsFixed(0)} % des mesures de votre zone'),
      _barometerRow('▲ Upload', b.zoneUploadPercentile,
          'plus rapide que ${b.zoneUploadPercentile.toStringAsFixed(0)} % des mesures de votre zone'),
      _barometerRow('↔ Latence', b.zonePingPercentile,
          'meilleure que ${b.zonePingPercentile.toStringAsFixed(0)} % des mesures de votre zone'),
    ];
  }

  /// IMP-09 v2 — Tendance personnelle : les derniers tests du même appareil,
  /// du plus ancien au plus récent, avec le sens d'évolution.
  Widget _trendLine(BarometerResult b) {
    final values = b.recentDownloads.reversed.toList();
    const eps = 0.1;
    final sens = values.last > values.first + eps
        ? 'en hausse'
        : values.last < values.first - eps
            ? 'en baisse'
            : 'stable';
    final seq = values.map((v) => v.toStringAsFixed(1)).join(' → ');
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        'Vos ${values.length} derniers tests ▼ : $seq Mb/s ($sens)',
        style: TextStyle(fontSize: 12, color: YeleColors.surface.muted),
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
  // [onInfo] : pastille ⓘ optionnelle à droite du score, comme sur la carte
  // Score YÉLÉ — ouvre le panneau explicatif du test en cours.
  Widget _resultCard(String icon, String title, Color color, double score,
      List<({String k, String v})> lines,
      {VoidCallback? onInfo}) {
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
                if (onInfo != null) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: "Comment c'est calculé",
                    icon: const Icon(Icons.info_outline,
                        color: Colors.white, size: 20),
                    onPressed: onInfo,
                  ),
                ],
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
    // Le JSON stocké porte le moteur qui a produit la mesure ; les résultats
    // antérieurs (sans champ engine) viennent forcément de YouTube.
    final engine = StreamingTestResult.decodeEngine(r.streamingQualitiesJson) ??
        'youtube';
    if (rows.isEmpty && error != null) return _streamingError(error);
    if (rows.isEmpty) {
      return _resultCard('🎬', 'Streaming vidéo', YeleColors.g5,
          r.streamingScore ?? 0, [
        (k: 'Résolution max soutenue', v: r.streamingMaxResolution ?? '—'),
        (k: 'Démarrage', v: '${r.streamingStartupMs ?? 0} ms'),
        (k: 'Interruptions', v: '${r.streamingRebufferCount ?? 0}'),
      ], onInfo: () => showStreamingExplanationSheet(context, r));
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
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: "Comment c'est calculé",
                  icon: const Icon(Icons.info_outline,
                      color: Colors.white, size: 20),
                  onPressed: () => showStreamingExplanationSheet(context, r),
                ),
              ],
            ),
          ),
        StreamingTable(qualities: rows, videoEngine: engine),
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

  /// IMP-12 — score YELE en points, identique à la colonne « Score » de
  /// l'historique. La définition de l'échelle fait autorité dans
  /// `docs/echelle-score.md` (IMP-05) : unité en points, échelle ouverte,
  /// jamais de score global sur 100.
  ///
  /// Résultat complet → score global ; incomplet → sous-total des composantes
  /// réellement mesurées, sans points fictifs ; un résultat antérieur au
  /// scoring n'affiche pas de carte (aucune version attribuée).
  Widget _scoreCard() {
    final version = r.scoringVersion;
    if (version == null) return const SizedBox.shrink();
    final global = r.scoreGlobal;
    final sousTotal = r.scoreMeasuredSubtotal;
    String pts(double v) => v.toStringAsFixed(0);
    final lignes = <({String k, String v})>[
      if (r.scoreDownload != null)
        (k: 'Download', v: '${pts(r.scoreDownload!)} pts'),
      if (r.scoreUpload != null)
        (k: 'Upload', v: '${pts(r.scoreUpload!)} pts'),
      if (r.scorePingJitter != null)
        (k: 'Latence', v: '${pts(r.scorePingJitter!)} pts'),
      if (r.scoreBrowsing != null)
        (k: 'Navigation', v: '${pts(r.scoreBrowsing!)} pts'),
      if (r.scoreStreaming != null)
        (k: 'Streaming', v: '${pts(r.scoreStreaming!)} pts'),
      (k: 'Référentiel', v: version),
    ];
    final String legende;
    if (global != null) {
      legende = YeleScoringEngine.classify(global).label;
    } else if (sousTotal == null) {
      legende = 'Score global non calculé : aucune composante mesurée';
    } else {
      legende = 'Score global non calculé : ${pts(sousTotal)} pts mesurés, '
          'composantes absentes exclues';
    }
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
              color: YeleColors.primary,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                const Text('🏅', style: TextStyle(fontSize: 20)),
                const SizedBox(width: 8),
                const Text('Score YELE',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
                const Spacer(),
                Text(
                  global != null ? '${pts(global)} pts' : 'incomplet',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800),
                ),
                const SizedBox(width: 4),
                // IMP-05 / IMP-12 — explique le calcul du score, au global
                // comme par composante, pour le test en cours.
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Comment le score est calculé',
                  icon: const Icon(Icons.info_outline,
                      color: Colors.white, size: 20),
                  onPressed: () => showScoreExplanationSheet(context, r),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                for (final l in lignes)
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
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(legende,
                      style: TextStyle(
                          fontSize: 12, color: YeleColors.surface.muted)),
                ),
              ],
            ),
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
    ], onInfo: () => showNavigationExplanationSheet(context, r));
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
          // Règle produit : en test SIM le FAI (déduit de l'IP sur le réseau
          // mobile) ne s'affiche pas ; il est « — » même si le champ en
          // enregistre un pour le backend. En Wi-Fi il reste pertinent.
          c('FAI',
              (r.networkType ?? '').toUpperCase().contains('WIFI')
                  ? (r.operator ?? '—')
                  : '—'),
          c(
              'SSID Wi-Fi',
              (r.wifiSsid != null && r.wifiSsid!.trim().isNotEmpty &&
                      r.wifiSsid!.trim() != '<unknown ssid>')
                  ? r.wifiSsid!.trim()
                  : '—'),
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

  /// Règle produit : seul le nom de l'opérateur, sans la techno (déjà
  /// indiquée par « Connexion ») ni le numéro de SIM. « — » en Wi-Fi.
  String get _mobileLabel {
    if ((r.networkType ?? '').toUpperCase().contains('WIFI')) return '—';
    final sim = r.simOperator;
    return (sim != null && sim.isNotEmpty) ? sim : '—';
  }

  Widget _actions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: Column(
        children: [
          // IMP-11 — Export de la mesure, façon nPerf : proposé dès le bilan
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
