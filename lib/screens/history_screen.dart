import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../models/speed_test_result.dart';
import '../services/local_storage_service.dart';
import '../theme/yele_theme.dart';
import '../widgets/export_sheet.dart';
import '../widgets/yele_scaffold.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _storage = LocalStorageService();
  final _date = DateFormat('dd/MM/yy');
  final _time = DateFormat('HH:mm:ss');

  List<SpeedTestResult> _all = [];
  int _tab = 0; // 0 = Test complet, 1 = Speed test
  String? _expandedId;

  @override
  void initState() {
    super.initState();
    _all = _storage.getResultsSorted();
  }

  bool _isComplet(SpeedTestResult r) =>
      r.hasStreamingTest || r.hasBrowsingTest;

  /// Note de qualité /100 dérivée des mesures réelles (transparente) :
  /// 60 pts max pour le download, 20 pour l'upload, 20 pour la latence.
  int _score(SpeedTestResult r) {
    final dl = (r.downloadSpeed / 50 * 60).clamp(0, 60);
    final ul = (r.uploadSpeed / 25 * 20).clamp(0, 20);
    final lat = r.ping <= 20
        ? 20.0
        : r.ping >= 300
            ? 0.0
            : (300 - r.ping) / 280 * 20;
    return (dl + ul + lat).round().clamp(0, 100);
  }

  List<SpeedTestResult> get _filtered =>
      _all.where((r) => _tab == 0 ? _isComplet(r) : !_isComplet(r)).toList();

  @override
  Widget build(BuildContext context) {
    final pts = _all
        .where((r) => (r.latitude ?? 0) != 0 && (r.longitude ?? 0) != 0)
        .toList();
    final list = _filtered;
    return YeleScaffold(
      title: 'Historique',
      route: '/history',
      body: Column(
        children: [
          SizedBox(height: 200, child: _map(pts)),
          _tabs(),
          _header(),
          Expanded(
            child: list.isEmpty
                ? const Center(
                    child: Text('Aucun test pour cet onglet.',
                        style: TextStyle(color: Color(0xFF6B7689))))
                : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (_, i) => _row(list[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _map(List<SpeedTestResult> pts) {
    final center = pts.isNotEmpty
        ? LatLng(pts.first.latitude!, pts.first.longitude!)
        : const LatLng(12.366, -1.527);
    return FlutterMap(
      options: MapOptions(initialCenter: center, initialZoom: 12),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.yele',
        ),
        MarkerLayer(
          markers: [
            for (final r in pts)
              Marker(
                point: LatLng(r.latitude!, r.longitude!),
                width: 32,
                height: 32,
                child: const Icon(Icons.location_on,
                    color: Color(0xFF16557E), size: 28),
              ),
          ],
        ),
      ],
    );
  }

  Widget _tabs() {
    Widget tab(String label, int index) {
      final active = _tab == index;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() {
            _tab = index;
            _expandedId = null;
          }),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 15),
            decoration: BoxDecoration(
              color: YeleColors.panel2,
              border: Border(
                bottom: BorderSide(
                  color: active ? YeleColors.primary : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
            child: Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    letterSpacing: 0.5,
                    color: active ? YeleColors.ink : const Color(0xFF5A6577))),
          ),
        ),
      );
    }

    return Row(children: [tab('TEST COMPLET', 0), tab('SPEED TEST', 1)]);
  }

  Widget _header() {
    Widget h(IconData icon, String label, int flex) {
      return Expanded(
        flex: flex,
        child: Column(
          children: [
            Icon(icon, size: 18, color: YeleColors.field),
            const SizedBox(height: 2),
            Text(label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 12,
                    color: YeleColors.field,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        color: YeleColors.surface.panel,
        border: Border(bottom: BorderSide(color: YeleColors.surface.line)),
      ),
      child: Row(
        children: [
          h(Icons.network_check, 'Type', 12),
          h(Icons.public, 'ISP / Réseau', 20),
          h(Icons.calendar_today, 'Date', 13),
          h(Icons.hourglass_bottom, 'Débits', 14),
          h(Icons.workspace_premium, 'Score', 12),
        ],
      ),
    );
  }

  Color _typeColor(String? net) {
    final n = (net ?? '').toUpperCase();
    if (n.contains('WIFI') || n.contains('WI-FI')) return YeleColors.primary;
    if (n.contains('5G')) return YeleColors.g5;
    if (n.contains('4G')) return YeleColors.g4;
    if (n.contains('3G')) return YeleColors.g3;
    if (n.contains('2G')) return YeleColors.g2;
    return YeleColors.muted; // Inconnu / défaut
  }

  /// Icône reflétant le type de connexion réellement utilisé pour le test.
  IconData _typeIcon(String? net) {
    final n = (net ?? '').toUpperCase();
    if (n.contains('WIFI') || n.contains('WI-FI')) return Icons.wifi;
    if (n.contains('2G') ||
        n.contains('3G') ||
        n.contains('4G') ||
        n.contains('5G')) {
      return Icons.signal_cellular_alt;
    }
    return Icons.network_check;
  }

  Widget _row(SpeedTestResult r) {
    final expanded = _expandedId == r.id;
    final net = r.networkType ?? '—';
    return Column(
      children: [
        InkWell(
          onTap: () => setState(() => _expandedId = expanded ? null : r.id),
          child: Container(
            decoration: const BoxDecoration(
              color: Color(0xFF10161F),
              border: Border(bottom: BorderSide(color: YeleColors.testBot)),
            ),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Type
                Expanded(
                  flex: 12,
                  child: Column(
                    children: [
                      Icon(_typeIcon(net),
                          size: 16, color: const Color(0xFFCFD6E0)),
                      const SizedBox(height: 2),
                      Text(net,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Color(0xFFCFD6E0), fontSize: 11)),
                      const SizedBox(height: 3),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: _typeColor(net),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(net.length > 5 ? net.substring(0, 5) : net,
                            style: const TextStyle(
                                color: Color(0xFF11210B),
                                fontSize: 9,
                                fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ),
                // ISP / Réseau
                Expanded(
                  flex: 20,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.operator ?? '—',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Color(0xFFCFD6E0), fontSize: 12)),
                      Text(r.location ?? '—',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Color(0xFF8FA0B8), fontSize: 11)),
                    ],
                  ),
                ),
                // Date
                Expanded(
                  flex: 13,
                  child: Column(
                    children: [
                      Text(_date.format(r.timestamp),
                          style: const TextStyle(
                              color: Color(0xFFCFD6E0), fontSize: 11)),
                      Text(_time.format(r.timestamp),
                          style: const TextStyle(
                              color: Color(0xFF8FA0B8), fontSize: 10)),
                    ],
                  ),
                ),
                // Débits
                Expanded(
                  flex: 14,
                  child: Column(
                    children: [
                      Text('${r.downloadSpeed.toStringAsFixed(2)} Mb/s',
                          style: const TextStyle(
                              color: Color(0xFFCFD6E0), fontSize: 11)),
                      Text('${r.uploadSpeed.toStringAsFixed(2)} Mb/s',
                          style: const TextStyle(
                              color: Color(0xFF8FA0B8), fontSize: 10)),
                    ],
                  ),
                ),
                // Score /100 + bouton d'expansion
                Expanded(
                  flex: 12,
                  child: Column(
                    children: [
                      Text('${_score(r)}',
                          style: const TextStyle(
                              color: Color(0xFFCFD6E0),
                              fontSize: 16,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 3),
                      Container(
                        width: 22,
                        height: 22,
                        decoration: const BoxDecoration(
                          color: YeleColors.testBot,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(expanded ? Icons.remove : Icons.add,
                            size: 16, color: const Color(0xFF11210B)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (expanded) _detail(r),
      ],
    );
  }

  Widget _detail(SpeedTestResult r) {
    Widget line(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('$k :',
                  style: const TextStyle(color: Color(0xFF1F3A00), fontSize: 12)),
              Flexible(
                child: Text(v,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        color: Color(0xFF1F3A00),
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        );

    return Container(
      width: double.infinity,
      color: YeleColors.testMid,
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          line('Serveur', r.server),
          line('FAI', r.operator ?? '—'),
          if ((r.simOperator ?? '').isNotEmpty || (r.cellularTech ?? '').isNotEmpty)
            line(
                'Réseau mobile',
                [r.cellularTech, r.simOperator]
                    .where((e) => (e ?? '').isNotEmpty)
                    .join(' · ')),
          line('Réseau', r.location ?? '—'),
          if ((r.deviceModel ?? '').isNotEmpty) line('Appareil', r.deviceModel!),
          line('Latence', '${r.ping.toStringAsFixed(0)} ms'),
          line('Gigue', '${r.jitter.toStringAsFixed(0)} ms'),
          if (r.hasStreamingTest)
            line('Streaming',
                '${r.streamingMaxResolution ?? '—'} · ${r.streamingScore!.toStringAsFixed(0)}/100'),
          if (r.hasBrowsingTest)
            line('Navigation',
                '${(r.browsingAvgLoadMs! / 1000).toStringAsFixed(1)} s · ${r.browsingScore!.toStringAsFixed(0)}/100'),
          if ((r.latitude ?? 0) != 0)
            line('Coord.',
                '${r.latitude!.toStringAsFixed(4)}, ${r.longitude!.toStringAsFixed(4)}'),
          if (r.qoeRating != null && r.qoeRating! > 0)
            line('QoE', '${r.qoeRating}/5'),
          // IMP-13 — Export de cette mesure (CSV / Excel / PDF / PNG).
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => showExportSheet(context, r),
              icon: const Icon(Icons.ios_share, size: 18),
              label: const Text('Exporter la mesure'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: YeleColors.ink,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
