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
import '../widgets/result_explanation_sheets.dart';
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
    // l'API répond (test de débit, ou usage seul — streaming/navigation).
    if (_speedDone || r.hasStreamingTest || r.hasBrowsingTest) {
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
          // Fond « bilan » des croquis validés (soft #F2F5F1, cartes
          // blanches, héros sombre). L'ancien gradient lime de l'écran de
          // test exposait de grandes plages vertes sous la nouvelle mise en
          // page — écart au design corrigé le 17/11.
          color: const Color(0xFFF2F5F1),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 12),
                  // Héros unique — fusion de l'ancien cercle QUALITÉ et de la
                  // carte « Score YELE » : un seul verdict en haut de page,
                  // les 5 composantes en mini-barres (échelle points IMP-12).
                  _heroSection(),
                  // Données consommées en deuxième (validation du 18/11) :
                  // le verdict d'abord, le volume consommé ensuite.
                  _dataUsedChip(),
                  // N'affiche que les sections du/des test(s) réellement faits.
                  if (_speedDone) ...[
                    _metricsTiles(),
                    _minMeanMaxCard(),
                    _sectionTitle('📊 Comparaison'),
                    // IMP-09 — Baromètre « mon résultat vs les autres ».
                    _barometerCard(),
                    _sectionTitle('🎬 Usages'),
                  ],
                  // Affiché aussi en cas d'échec, pour en montrer la raison.
                  if (r.hasStreamingTest || r.streamingError != null)
                    _streamingCard(),
                  if (r.hasBrowsingTest) _browsingCard(),
                  if (!_speedDone) ...[
                    // Usage seul : la comparaison porte sur l'usage testé, et
                    // un rappel discret invite à refaire un test complet.
                    if (r.hasStreamingTest || r.hasBrowsingTest) ...[
                      _sectionTitle('📊 Comparaison'),
                      _barometerCard(),
                    ],
                    _untestedReminder(),
                  ],
                  _sectionTitle('Infos'),
                  _infoCard(),
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

  // ── Refonte visuelle (croquis validés du 16-17/11) ───────────────────────

  /// Titre de section, en petites capitales espacées (« Comparaison »,
  /// « Usages », « Infos ») : donne le rythme de lecture du bilan.
  Widget _sectionTitle(String titre) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 16, 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(titre.toUpperCase(),
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                // Muted des croquis validés : lisible sur le fond pâle.
                color: Color(0xFF6B7565))),
      ),
    );
  }

  /// IMP-01 — Données consommées par le test : une ligne discrète en tête
  /// de page, avant tout verdict (Android ; masquée si inconnu).
  Widget _dataUsedChip() {
    final kib = r.dataUsedKiB;
    if (kib == null || kib < 0) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)],
      ),
      child: Text('📦 Données consommées : ${_formatData(kib)}',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: YeleColors.surface.muted)),
    );
  }

  /// Rappel discret quand seul un usage a été testé : les composantes non
  /// mesurées restent grisées dans le héros, on invite à refaire un test
  /// complet pour les situer dans le baromètre.
  Widget _untestedReminder() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Text.rich(
        TextSpan(
          style: TextStyle(fontSize: 12, color: YeleColors.surface.muted),
          children: const [
            TextSpan(
                text: 'Débit, latence et '
                    'usages non testés cette fois — refaites un '),
            TextSpan(
                text: 'test complet',
                style: TextStyle(
                    color: YeleColors.primary, fontWeight: FontWeight.w600)),
            TextSpan(text: ' pour les situer dans le baromètre.'),
          ],
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  /// « 35 950 » : points formatés avec un espace millier, façon française.
  String _ptsFmt(double v) {
    final s = v.round().toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
      b.write(s[i]);
    }
    return b.toString();
  }

  /// Décimales françaises : la virgule remplace le point de
  /// [double.toStringAsFixed] (Dart ne localise pas).
  String _fr(num v, int digits) =>
      v.toStringAsFixed(digits).replaceAll('.', ',');

  /// Couleur de l'anneau et du verdict, même lecture que [classify].
  Color _scoreColor(double score) {
    if (score <= 30000) return YeleColors.danger;
    if (score <= 70000) return YeleColors.warn;
    if (score <= 110000) return YeleColors.g4;
    return YeleColors.good;
  }

  /// Héros unique : le cercle affiche l'indice du test (score global en
  /// points, ou sous-total des composantes mesurées — échelle ouverte
  /// IMP-12, jamais ramené sur 100), le verdict en clair dessous, puis les
  /// 5 composantes en mini-barres avec leur allocation de référence.
  /// Résultat antérieur au scoring : lecture débit seule, comme avant.
  Widget _heroSection() {
    final version = r.scoringVersion;
    final global = r.scoreGlobal;
    final sousTotal = r.scoreMeasuredSubtotal;
    final heroScore = global ?? sousTotal;
    final partiel = global == null && sousTotal != null;

    final cercle = Container(
      width: 150,
      height: 150,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          center: Alignment(0, -0.2),
          colors: [Color(0xFF24301F), Color(0xFF0C1108)],
        ),
        border: Border.all(
            color: heroScore == null
                ? _quality.color
                : _scoreColor(heroScore),
            width: 6),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (heroScore == null) ...[
            Text(_quality.label,
                style: TextStyle(
                    color: _quality.color,
                    fontSize: 24,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text('${_fr(r.downloadSpeed, 1)} Mb/s',
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ] else ...[
            Text(_ptsFmt(heroScore),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    height: 1.1)),
            const Text('pts YELE',
                style: TextStyle(color: Colors.white70, fontSize: 11)),
          ],
        ],
      ),
    );

    final verdict = heroScore == null
        ? 'Qualité du débit'
        : YeleScoringEngine.classify(heroScore).label;
    final nbComposantes = [
      r.scoreDownload,
      r.scoreUpload,
      r.scorePingJitter,
      r.scoreStreaming,
      r.scoreBrowsing,
    ].where((s) => s != null).length;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1C2419), Color(0xFF10160D)],
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          cercle,
          const SizedBox(height: 10),
          Text(verdict,
              style: TextStyle(
                  color: heroScore == null
                      ? _quality.color
                      : _scoreColor(heroScore),
                  fontSize: 17,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 3),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                partiel
                    ? 'Score partiel · $nbComposantes composantes testées'
                    : (version == null ? 'Qualité dérivée du débit' : 'Score YELE'),
                style: const TextStyle(
                    color: Color(0xFF9AA79A), fontSize: 10),
              ),
              if (version != null) ...[
                const SizedBox(width: 6),
                Text('· $version',
                    style: const TextStyle(
                        color: Color(0xFF9AA79A), fontSize: 10)),
                const SizedBox(width: 2),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Comment le score est calculé',
                  icon: const Icon(Icons.info_outline,
                      color: Color(0xFF9AA79A), size: 16),
                  onPressed: () => showScoreExplanationSheet(context, r),
                ),
              ],
            ],
          ),
          // Les 5 composantes, avec leur allocation de référence comme
          // plafond ; les composantes non testées restent visibles, grisées
          // avec un tiret — on voit ce qui manque.
          if (version != null) ...[
            const SizedBox(height: 6),
            _heroBar('▼ Download', r.scoreDownload,
                YeleScoringEngine.maxDownload),
            _heroBar('▲ Upload', r.scoreUpload,
                YeleScoringEngine.maxUpload),
            _heroBar('↔ Latence', r.scorePingJitter,
                YeleScoringEngine.maxPingJitter),
            _heroBar('▶ Streaming', r.scoreStreaming,
                YeleScoringEngine.maxStreaming),
            _heroBar('🌐 Navigation', r.scoreBrowsing,
                YeleScoringEngine.maxBrowsing),
          ],
        ],
      ),
    );
  }

  /// Une mini-barre du héros : nom, jauge (score / allocation de référence),
  /// points affichés « 7 200 / 17 500 » — ou tiret grisée si non testée.
  Widget _heroBar(String label, double? score, double max) {
    final teste = score != null;
    final pts = score ?? 0;
    final rowColor = teste ? Colors.white : Colors.white38;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 3, 28, 3),
      child: Row(
        children: [
          SizedBox(
              width: 92,
              child: Text(label,
                  style: TextStyle(fontSize: 11, color: rowColor))),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: teste ? (pts / max).clamp(0.0, 1.0) : 0,
                minHeight: 5,
                backgroundColor: const Color(0xFF2A3526),
                valueColor: AlwaysStoppedAnimation(
                    teste ? const Color(0xFF4E9E63) : const Color(0xFF2A3526)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 96,
            child: Text(
              teste ? '${_ptsFmt(pts)} / ${_ptsFmt(max)}' : '—',
              textAlign: TextAlign.right,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: teste ? Colors.white : Colors.white38),
            ),
          ),
        ],
      ),
    );
  }

  /// Trois tuiles chiffres clés (Download, Upload, Latence), chacune avec
  /// son filet de couleur ; la gigue et la perte vivent sous la latence,
  /// une information par ligne.
  Widget _metricsTiles() {
    Widget tuile(String label, String val, String unit,
        {Color accent = YeleColors.primary, List<String> subs = const []}) {
      return Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)],
          ),
          child: Column(
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 10,
                      color: YeleColors.surface.muted,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(val,
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: YeleColors.field,
                      height: 1.1)),
              Text(unit,
                  style: TextStyle(
                      fontSize: 10, color: YeleColors.surface.muted)),
              for (final s in subs) ...[
                const SizedBox(height: 3),
                Text(s,
                    style: TextStyle(
                        fontSize: 10, color: YeleColors.surface.muted)),
              ],
              const SizedBox(height: 6),
              Container(height: 3, width: double.infinity, color: accent),
            ],
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      // IntrinsicHeight : indispensable. Un Row avec `stretch` dans un
      // SingleChildScrollView exigerait une hauteur infinie (crash de layout
      // constaté le 17/11 — frame corrompue en release, contenu sous les
      // tuiles jamais peint). IntrinsicHeight borne la ligne et garde les
      // tuiles de même hauteur.
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            tuile('▼ DOWNLOAD', _fr(r.downloadSpeed, 2), 'Mb/s'),
            tuile('▲ UPLOAD', _fr(r.uploadSpeed, 2), 'Mb/s',
                accent: YeleColors.good),
            tuile('↔ LATENCE', r.ping.toStringAsFixed(0), 'ms',
                accent: YeleColors.warn, subs: [
              'Gigue : ${r.jitter.toStringAsFixed(0)} ms',
              // IMP-07 : perte de paquets, à côté de la gigue.
              if (r.packetLoss != null)
                'Perte : ${formatPacketLoss(r.packetLoss!)}',
            ]),
          ],
        ),
      ),
    );
  }

  /// ISS-06 — Carte « Min / Moy / Max » : un titre de section puis le
  /// tableau, une ligne par métrique mesurée. Absente si aucune métrique
  /// n'a de min et de max (ancien résultat, test sans phase de débit).
  Widget _minMeanMaxCard() {
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

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text('MIN / MOY / MAX',
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                        color: YeleColors.surface.muted)),
              ),
              const Spacer(),
              // ⓘ — explique la lecture de min / moyenne / max (18/11).
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Comment lire Min / Moy / Max',
                icon: const Icon(Icons.info_outline, size: 18),
                color: YeleColors.primary,
                onPressed: () => showMinMeanMaxExplanationSheet(context),
              ),
            ],
          ),
          Table(
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
                  c(_fr(s.min, digits), cell),
                  c(_fr(s.mean, digits), cell),
                  c('${_fr(s.max, digits)} $unit', cell),
                ]),
            ],
          ),
        ],
      ),
    );
  }

  /// IMP-01 : formatage lisible d'un volume en KiB (Mo au-delà de 1 Mo).
  String _formatData(int kib) {
    if (kib >= 1024) {
      return '${_fr(kib / 1024, 1)} Mo';
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
              // ⓘ — explique rangs, centiles, médianes et sous-groupes
              // (validation du 18/11).
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Comment lire le baromètre',
                icon: const Icon(Icons.info_outline, size: 18),
                color: YeleColors.primary,
                onPressed: () => showBarometerExplanationSheet(context),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Lignes de débit seulement si la phase de débit a eu lieu : un
          // test d'usage seul n'affiche que ses propres indicateurs.
          if (_speedDone) ...[
            _barometerRow('▼ Download', b.downloadPercentile,
                _metricCaption(b.downloadRank, _medianOf(b.medianDownload, 'Mb/s'))),
            _barometerRow('▲ Upload', b.uploadPercentile,
                _metricCaption(b.uploadRank, _medianOf(b.medianUpload, 'Mb/s'))),
            _barometerRow('↔ Latence', b.pingPercentile,
                _metricCaption(b.pingRank, _medianOf(b.medianPing, 'ms', decimals: 0))),
          ],
          // IMP-09 v2 : les cinq indicateurs — le centile n'est demandé au
          // serveur que si le testeur a fait l'usage.
          if (r.hasStreamingTest)
            _barometerRow('▶ Streaming', b.streamingPercentile,
                'meilleur que ${b.streamingPercentile.toStringAsFixed(0)} % des tests de streaming'),
          if (r.hasBrowsingTest)
            _barometerRow('🌐 Navigation', b.browsingPercentile,
                'meilleur que ${b.browsingPercentile.toStringAsFixed(0)} % des tests de navigation'),
          // IMP-09 : même lecture, parmi les seuls clients de l'opérateur.
          if (_speedDone && b.hasOperatorComparison) ..._operatorBarometer(b),
          // IMP-09 v2 : comparaison de proximité, si l'échantillon suffit.
          if (_speedDone && b.hasZoneComparison) ..._zoneBarometer(b),
          if (_speedDone && b.hasTrend) _trendLine(b),
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
    return 'médiane ${_fr(median, decimals)} $unit';
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
        'Débit moyen ▼ : vous ${_fr(r.downloadSpeed, 1)} Mb/s · '
        '$op ${_fr(b.operatorAvgDownload, 1)} Mb/s · '
        'toutes mesures ${_fr(b.nationalAvgDownload, 1)} Mb/s',
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
    final seq = values.map((v) => _fr(v, 1)).join(' → ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 22),
        Text('📈 Vos ${values.length} derniers tests ▼',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: YeleColors.surface.muted)),
        const SizedBox(height: 2),
        Text('$seq Mb/s ($sens)',
            style: TextStyle(fontSize: 12, color: YeleColors.surface.muted)),
      ],
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

  /// Coque d'usage unifiée (croquis validés) : carte blanche, en-tête avec
  /// icône + titre, pastille ⓘ et badge de score coloré. [child] porte le
  /// détail (tableau des qualités, tableau des sites) ; [synthese] la
  /// ligne de lecture rapide sous l'en-tête.
  Widget _usageCard(String icon, String title, Color color, double score,
      {required String synthese, Widget? child, VoidCallback? onInfo}) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 0),
            child: Row(
              children: [
                Text(icon, style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Text(title,
                    style: TextStyle(
                        color: YeleColors.surface.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
                const Spacer(),
                if (onInfo != null)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: "Comment c'est calculé",
                    icon: const Icon(Icons.info_outline, size: 18),
                    color: YeleColors.primary,
                    onPressed: onInfo,
                  ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text('${score.toStringAsFixed(0)}/100',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 6),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
            child: Text(synthese,
                style: TextStyle(
                    fontSize: 12, color: YeleColors.surface.muted)),
          ),
          ?child,
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  /// Une ligne clé/valeur d'une fiche d'usage (repli de l'ancienne carte
  /// quand le tableau détaillé n'est pas disponible).
  Widget _usageLine(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(k,
              style: TextStyle(
                  color: YeleColors.surface.muted, fontSize: 13)),
          Text(v,
              style: TextStyle(
                  color: YeleColors.surface.ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
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
      return _usageCard('🎬', 'Streaming vidéo', YeleColors.g5,
          r.streamingScore ?? 0,
          synthese: 'Démarrage ${r.streamingStartupMs ?? 0} ms · '
              '${r.streamingRebufferCount ?? 0} interruption(s) · '
              'résolution max : ${r.streamingMaxResolution ?? '—'}',
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
            child: Column(
              children: [
                _usageLine('Résolution max soutenue',
                    r.streamingMaxResolution ?? '—'),
                _usageLine('Démarrage', '${r.streamingStartupMs ?? 0} ms'),
                _usageLine('Interruptions', '${r.streamingRebufferCount ?? 0}'),
              ],
            ),
          ),
          onInfo: () => showStreamingExplanationSheet(context, r));
    }
    final interruptions =
        rows.fold<int>(0, (n, q) => n + q.rebufferCount);
    final demarrages = rows
        .where((q) => q.reached)
        .map((q) => q.initialLoadingSec)
        .toList();
    final demarrageMoyen = demarrages.isEmpty
        ? 0.0
        : demarrages.reduce((a, b) => a + b) / demarrages.length;
    return Column(
      children: [
        _usageCard('🎬', 'Streaming vidéo', YeleColors.g5,
            r.streamingScore ?? 0,
            synthese: 'Moteur : ${_engineLabel(engine)} · '
                'démarrage moyen ${_fr(demarrageMoyen, 1)} s · '
                '$interruptions interruption(s) · '
                'résolution max : ${r.streamingMaxResolution ?? '—'}',
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: StreamingTable(qualities: rows, videoEngine: engine),
            ),
            onInfo: () => showStreamingExplanationSheet(context, r)),
        if (error != null) _streamingError(error),
      ],
    );
  }

  /// Libellé lisible du moteur du test de streaming (le JSON stocké porte
  /// « youtube » ou « hls »).
  String _engineLabel(String engine) =>
      engine == 'hls' ? 'HLS (Big Buck Bunny)' : 'YouTube';

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
    final pages = r.browsingPages;
    return _usageCard('🌐', 'Navigation web', YeleColors.primary,
        r.browsingScore ?? 0,
        synthese: 'Chargement moyen '
            '${_fr((r.browsingAvgLoadMs ?? 0) / 1000, 1)} s · '
            'taux de réussite '
            '${((r.browsingSuccessRate ?? 0) * 100).toStringAsFixed(0)} % · '
            '${r.browsingPagesTested ?? 0} pages testées',
        // Tableau des 6 sites (croquis ⑥, validation du 18/11) — seulement
        // quand le détail par site a été conservé (mesures récentes).
        child: pages.isEmpty
            ? null
            : Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 2),
                child: _browsingPagesTable(pages),
              ),
        onInfo: () => showNavigationExplanationSheet(context, r));
  }

  /// Tableau Site / Chargement / Résultat du test de navigation : une ligne
  /// par page de référence, barre colorée proportionnelle au temps mesuré,
  /// plus rapide et plus lent surlignés.
  Widget _browsingPagesTable(
      List<({String label, double loadMs, bool success})> pages) {
    final maxMs =
        pages.fold<double>(0, (m, p) => p.loadMs > m ? p.loadMs : m);
    // Plus rapide / plus lent : parmi les pages réellement chargées.
    final reussies = pages.where((p) => p.success && p.loadMs > 0).toList();
    String? plusRapide;
    String? plusLent;
    if (reussies.length >= 2) {
      plusRapide = reussies
          .reduce((a, b) => a.loadMs <= b.loadMs ? a : b)
          .label;
      plusLent = reussies.reduce((a, b) => a.loadMs >= b.loadMs ? a : b).label;
    }

    Widget ligne(({String label, double loadMs, bool success}) p) {
      final echec = !p.success;
      final couleur = echec ? YeleColors.warn : YeleColors.primary;
      final estRapide = p.label == plusRapide;
      final estLent = p.label == plusLent;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Text(
                p.label + (estRapide ? ' ★' : (estLent ? ' · lent' : '')),
                style: TextStyle(
                  color: YeleColors.surface.ink,
                  fontSize: 12,
                  fontWeight:
                      (estRapide || estLent) ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            Expanded(
              flex: 5,
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: echec
                            ? const Color(0x22FF6B5E)
                            : const Color(0x22000000),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor:
                            maxMs <= 0 ? 0 : (p.loadMs / maxMs).clamp(0.05, 1.0),
                        child: Container(
                          decoration: BoxDecoration(
                            color: couleur,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('${_fr(p.loadMs / 1000, 1)} s',
                      style: TextStyle(
                          color: YeleColors.surface.ink,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                echec ? 'Échec ✗' : 'Chargée ✓',
                textAlign: TextAlign.right,
                style: TextStyle(
                    color: couleur, fontSize: 11.5, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        for (final p in pages) ligne(p),
        if (plusRapide != null && plusLent != null && plusRapide != plusLent)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 2),
            child: Text('★ plus rapide : $plusRapide · plus lent : $plusLent',
                style: TextStyle(
                    color: YeleColors.surface.muted, fontSize: 11)),
          ),
      ],
    );
  }

  /// Section « Infos » : les quatre colonnes de connexion (titre au-dessus
  /// de la valeur), puis le serveur de test et l'appareil, chacun sur sa
  /// propre ligne — regroupés en une seule carte discrète en bas de page.
  Widget _infoCard() {
    Widget c(String label, String value) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          decoration: const BoxDecoration(
            border: Border(
              right: BorderSide(color: Color(0x11000000)),
            ),
          ),
          child: Column(
            children: [
              Text(label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: YeleColors.surface.muted,
                      fontSize: 10,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(value,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: YeleColors.surface.ink,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      );
    }

    final device = r.deviceModel;
    final os = r.osVersion;
    final appareil = [
      if (device != null && device.isNotEmpty) device,
      if (os != null && os.isNotEmpty) os,
    ].join(' · ');

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)],
      ),
      child: Column(
        children: [
          Row(
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
                  'SSID',
                  (r.wifiSsid != null &&
                          r.wifiSsid!.trim().isNotEmpty &&
                          r.wifiSsid!.trim() != '<unknown ssid>')
                      ? r.wifiSsid!.trim()
                      : '—'),
              c('Réseau mobile', _mobileLabel),
            ],
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            child: Text('Serveur de test : $serverRichLabel',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 11, color: YeleColors.surface.muted)),
          ),
          if (appareil.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Text(appareil,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 11, color: YeleColors.surface.muted)),
            ),
        ],
      ),
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
          // Question QoE d'abord (le parcours attendu), puis l'export.
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _qoeDone ? null : _openQoe,
              icon: Icon(_qoeDone ? Icons.check_circle : Icons.rate_review),
              label: Text(_qoeDone
                  ? 'Évaluation enregistrée'
                  : 'Évaluer la qualité (QoE)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _qoeDone ? YeleColors.good : YeleColors.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: YeleColors.good,
                disabledForegroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 12),
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
