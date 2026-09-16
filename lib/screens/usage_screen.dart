import 'package:flutter/material.dart';

import '../services/settings_service.dart';
import '../services/usage_tracker_service.dart' show DayUsage, UsageTrackerService, formatBytes, formatGb;
import '../theme/yele_theme.dart';
import '../widgets/yele_scaffold.dart';

/// IMP-01 — Écran « Consommation » : volumes de données transférés par
/// l'application, par jour / semaine / mois, avec répartition mobile vs Wi-Fi
/// et évolution jour par jour sur le mois courant.
///
/// Seules les données mobiles comptent pour le forfait : la répartition est
/// mise en avant, et l'alerte de seuil (Réglages) porte sur le mobile.
class UsageScreen extends StatefulWidget {
  const UsageScreen({super.key});

  @override
  State<UsageScreen> createState() => _UsageScreenState();
}

class _UsageScreenState extends State<UsageScreen> {
  /// IMP-01b — Jour touché sur le graphique (index dans la série, null = aucun).
  int? _selectedDay;

  @override
  void initState() {
    super.initState();
    SettingsService.monthlyLimitGbNotifier.addListener(_refresh);
    UsageTrackerService.monthlyUsageChanged.addListener(_refresh);
    UsageTrackerService.limitExceededNotifier.addListener(_refresh);
  }

  @override
  void dispose() {
    SettingsService.monthlyLimitGbNotifier.removeListener(_refresh);
    UsageTrackerService.monthlyUsageChanged.removeListener(_refresh);
    UsageTrackerService.limitExceededNotifier.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final tracker = UsageTrackerService.instance;

    if (!tracker.isSupported) {
      return YeleScaffold(
        title: 'Consommation',
        route: '/usage',
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              "Le suivi de consommation n'est disponible que sur Android "
              "(l'iOS n'expose pas les compteurs de trafic par application).",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: YeleColors.surface.muted),
            ),
          ),
        ),
      );
    }

    final today = tracker.today();
    final week = tracker.currentWeek();
    final month = tracker.currentMonth();
    final series = tracker.monthSeries();
    final limitGb = SettingsService().monthlyLimitGb;

    return YeleScaffold(
      title: 'Consommation',
      route: '/usage',
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _summaryCards(today, week, month),
          _mobileWifiSplit(month),
          if (limitGb > 0) _limitGauge(month, limitGb),
          if (UsageTrackerService.limitExceeded && limitGb > 0) _limitBanner(),
          _chart(series),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
            child: Text(
              "Volumes transférés par l'application Yélé (tests, cartes, "
              'collecte). Seules les données mobiles comptent pour votre '
              'forfait ; le Wi-Fi est indiqué à titre indicatif.',
              style: TextStyle(fontSize: 12.5, color: YeleColors.surface.muted),
            ),
          ),
        ],
      ),
    );
  }

  /// Bandeau d'alerte quand le seuil mensuel est franchi.
  Widget _limitBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 14, 18, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFEE2E2),
        border: Border.all(color: YeleColors.danger, width: 1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber, size: 18, color: YeleColors.danger),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Seuil mensuel dépassé : pensez à réduire votre consommation '
              'de données mobiles.',
              style: const TextStyle(
                  fontSize: 13,
                  color: YeleColors.danger,
                  fontWeight: FontWeight.w600,
                  height: 1.3),
            ),
          ),
        ],
      ),
    );
  }

  // ── Cartes jour / semaine / mois ──────────────────────────────────────────

  Widget _summaryCards(DayUsage today, DayUsage week, DayUsage month) {
    Widget card(String label, DayUsage u, {bool highlight = false}) {
      return Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 5),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: highlight
                ? YeleColors.primary.withValues(alpha: .08)
                : YeleColors.surface.panel,
            border: Border.all(
              color: highlight ? YeleColors.primary : YeleColors.surface.line,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 12.5, color: YeleColors.surface.muted)),
              const SizedBox(height: 6),
              Text(formatBytes(u.total),
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: YeleColors.surface.ink)),
              const SizedBox(height: 4),
              // IMP-01b — La carte active « Ce mois » garde un fond teinté
              // (primary à 8 %) ; le texte doit rester lisible dessus dans les
              // deux thèmes : libellé en encre pleine au lieu du muted, qui
              // disparaissait sur le fond sombre de la carte sélectionnée.
              Text('${formatBytes(u.mobile)} mobile',
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: highlight ? FontWeight.w600 : FontWeight.w400,
                      color: YeleColors.primary)),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(13, 14, 13, 4),
      child: Row(
        children: [
          card("Aujourd'hui", today),
          card('Cette semaine', week),
          card('Ce mois', month, highlight: true),
        ],
      ),
    );
  }

  // ── Répartition mobile vs Wi-Fi ───────────────────────────────────────────

  Widget _mobileWifiSplit(DayUsage month) {
    final total = month.total;
    Widget row(String label, int bytes, Color color) {
      final frac = total > 0 ? bytes / total : 0.0;
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
                Text('${formatBytes(bytes)}  (${(frac * 100).toStringAsFixed(0)} %)',
                    style: TextStyle(
                        fontSize: 13.5, color: YeleColors.surface.muted)),
              ],
            ),
            const SizedBox(height: 5),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: frac,
                minHeight: 6,
                backgroundColor: YeleColors.surface.line,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ],
        ),
      );
    }

    return _panel(
      'Répartition — mois en cours',
      Column(
        children: [
          row('Données mobiles (compte pour le forfait)', month.mobile,
              YeleColors.primary),
          row('Wi-Fi', month.wifi, const Color(0xFF6B7A90)),
        ],
      ),
    );
  }

  // ── Jauge du seuil mensuel ────────────────────────────────────────────────

  Widget _limitGauge(DayUsage month, double limitGb) {
    final limitBytes = (limitGb * 1024 * 1024 * 1024).round();
    final frac = limitBytes > 0 ? (month.total / limitBytes).clamp(0.0, 1.0) : 0.0;
    final over = month.total > limitBytes;
    final color = over ? YeleColors.danger : YeleColors.primary;

    return _panel(
      'Seuil mensuel',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: frac,
              minHeight: 12,
              backgroundColor: YeleColors.surface.line,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            over
                ? 'Seuil dépassé : ${formatBytes(month.total)} pour ${formatGb(limitGb)} Go autorisés.'
                : '${formatBytes(month.total)} sur ${formatGb(limitGb)} Go '
                    '(${(frac * 100).toStringAsFixed(0)} %)',
            style: TextStyle(
                fontSize: 13,
                color: over ? YeleColors.danger : YeleColors.surface.muted),
          ),
        ],
      ),
    );
  }

  // ── Graphique journalier du mois ──────────────────────────────────────────

  Widget _chart(List<DayUsage> series) {
    final maxBytes =
        series.fold<int>(0, (m, d) => d.total > m ? d.total : m);

    return _panel(
      'Évolution jour par jour — mois en cours',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // IMP-01b — Tooltip au toucher : un tap sur un jour affiche le
          // détail du volume dans un bandeau au-dessus du graphique.
          if (_selectedDay != null &&
              _selectedDay! >= 0 &&
              _selectedDay! < series.length)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: YeleColors.surface.panel2,
                border: Border.all(color: YeleColors.surface.line),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _dayTooltipLabel(series[_selectedDay!],
                          _selectedDay! + 1),
                      style: TextStyle(
                          fontSize: 12.5, color: YeleColors.surface.ink),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _selectedDay = null),
                    child: Icon(Icons.close,
                        size: 16, color: YeleColors.surface.muted),
                  ),
                ],
              ),
            ),
          SizedBox(
            height: 170,
            child: series.every((d) => d.total == 0)
                ? Center(
                    child: Text('Aucun transfert ce mois-ci',
                        style: TextStyle(
                            fontSize: 13, color: YeleColors.surface.muted)))
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // IMP-01b — Échelle Y : 3 graduations formatées pour
                      // donner du sens aux hauteurs de barres.
                      SizedBox(
                        width: 46,
                        child: _YAxisLabels(maxBytes),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Column(
                          children: [
                            Expanded(
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final selected =
                                      (_selectedDay != null &&
                                              _selectedDay! < series.length)
                                          ? _selectedDay
                                          : null;
                                  return GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTapUp: (details) {
                                      final slot = constraints.maxWidth /
                                          series.length;
                                      final idx =
                                          (details.localPosition.dx / slot)
                                              .floor()
                                              .clamp(0, series.length - 1);
                                      setState(() => _selectedDay = idx);
                                    },
                                    child: CustomPaint(
                                      size: Size(constraints.maxWidth,
                                          constraints.maxHeight),
                                      painter: _BarChartPainter(series,
                                          maxBytes, selected),
                                    ),
                                  );
                                },
                              ),
                            ),
                            // Axe X : 1er et dernier jour.
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('1',
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: YeleColors.surface.muted)),
                                  Text('${series.length}',
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: YeleColors.surface.muted)),
                                ],
                              ),
                            ),
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

  /// Libellé du tooltip d'un jour : « 12 sept : 45 Mo (38 Mo mobile) ».
  String _dayTooltipLabel(DayUsage u, int dayNumber) {
    const months = [
      'janv', 'févr', 'mars', 'avr', 'mai', 'juin',
      'juil', 'août', 'sept', 'oct', 'nov', 'déc',
    ];
    final now = DateTime.now();
    final date = '$dayNumber ${months[now.month - 1]}';
    if (u.mobile > 0 && u.mobile < u.total) {
      return '$date : ${formatBytes(u.total)} (${formatBytes(u.mobile)} mobile)';
    }
    return '$date : ${formatBytes(u.total)}';
  }

  Widget _panel(String title, Widget child) {
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 14, 18, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: YeleColors.surface.panel,
        border: Border.all(color: YeleColors.surface.line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(title,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: YeleColors.surface.ink)),
          ),
          child,
        ],
      ),
    );
  }
}

/// IMP-01b — Graduations de l'axe Y : 3 valeurs (haut, milieu, bas)
/// formatées lisible (« 500 Mo », « 1 Go »…).
class _YAxisLabels extends StatelessWidget {
  final int maxBytes;

  const _YAxisLabels(this.maxBytes);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final frac in const [1.0, 0.5, 0.0])
          Text(
            formatAxisBytes((maxBytes * frac).round()),
            style: TextStyle(fontSize: 9.5, color: YeleColors.surface.muted),
          ),
      ],
    );
  }
}

/// Formatage compact pour l'axe : arrondi au multiple lisible supérieur,
/// « 0 » en bas. Différent de [formatBytes] : ici on veut des repères ronds.
String formatAxisBytes(int bytes) {
  if (bytes <= 0) return '0';
  const kib = 1024;
  if (bytes < kib) return '${(bytes / kib * 10).ceil() / 10} Ko';
  if (bytes < kib * kib) {
    final mo = bytes / (kib * kib);
    return mo >= 10 ? '${mo.round()} Mo' : '${(mo * 10).ceil() / 10} Mo';
  }
  final go = bytes / (kib * kib * kib);
  return go >= 10 ? '${go.round()} Go' : '${(go * 10).ceil() / 10} Go';
}

/// Histogramme simple dessiné sans dépendance externe : une barre par jour,
/// part mobile en bas (couleur pleine), Wi-Fi empilé au-dessus (plus claire).
/// IMP-01b : le jour sélectionné (tooltip) est surligné.
class _BarChartPainter extends CustomPainter {
  final List<DayUsage> series;
  final int maxBytes;

  /// Index du jour sélectionné (tooltip), ou null.
  final int? selected;

  _BarChartPainter(this.series, this.maxBytes, [this.selected]);

  @override
  void paint(Canvas canvas, Size size) {
    if (maxBytes <= 0) return;
    final n = series.length;
    final slot = size.width / n;
    final barWidth = (slot * 0.6).clamp(1.5, 14.0);
    final mobilePaint = Paint()..color = YeleColors.primary;
    final wifiPaint = Paint()..color = YeleColors.primary.withValues(alpha: .25);

    for (var i = 0; i < n; i++) {
      final u = series[i];
      if (u.total <= 0) continue;
      final h = u.total / maxBytes * size.height;
      final x = i * slot + (slot - barWidth) / 2;
      final hm = u.mobile / maxBytes * size.height;
      final hw = h - hm;
      final isSel = selected == i;
      final wifi = isSel
          ? YeleColors.primary.withValues(alpha: .45)
          : wifiPaint.color;
      if (hw > 0) {
        canvas.drawRect(
            Rect.fromLTWH(x, size.height - hw, barWidth, hw),
            Paint()..color = wifi);
      }
      if (hm > 0) {
        canvas.drawRect(
            Rect.fromLTWH(x, size.height - h, barWidth, hm), mobilePaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BarChartPainter old) =>
      old.maxBytes != maxBytes ||
      old.series.length != series.length ||
      old.selected != selected;
}
