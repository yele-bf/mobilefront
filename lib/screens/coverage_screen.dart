import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../services/dashboard_api_service.dart';
import '../theme/yele_theme.dart';
import '../widgets/yele_scaffold.dart';

class CoverageScreen extends StatefulWidget {
  const CoverageScreen({super.key});

  @override
  State<CoverageScreen> createState() => _CoverageScreenState();
}

class _CoverageScreenState extends State<CoverageScreen> {
  final _api = DashboardApiService();
  List<CoveragePoint> _points = [];
  bool _loading = true;
  String _operator = 'Tous';

  static const _operators = ['Tous', 'Orange', 'Telecel', 'Moov Africa'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final pts = await _api.fetchCoveragePoints();
    if (!mounted) return;
    setState(() {
      _points = pts;
      _loading = false;
    });
  }

  Color _colorFor(String net) {
    final n = net.toUpperCase();
    if (n.contains('5G')) return YeleColors.g5;
    if (n.contains('4G+') || n.contains('LTE+')) return YeleColors.g4p;
    if (n.contains('4G') || n.contains('LTE')) return YeleColors.g4;
    if (n.contains('3G')) return YeleColors.g3;
    if (n.contains('2G')) return YeleColors.g2;
    if (n.contains('WIFI')) return YeleColors.primary;
    return YeleColors.muted;
  }

  List<CoveragePoint> get _filtered => _operator == 'Tous'
      ? _points
      : _points
          .where((p) =>
              p.operator.toLowerCase().contains(_operator.toLowerCase()))
          .toList();

  @override
  Widget build(BuildContext context) {
    return YeleScaffold(
      title: 'Cartes de couverture',
      route: '/coverage',
      body: Column(
        children: [
          Expanded(child: _map()),
          _legend(),
          _operatorBar(),
        ],
      ),
    );
  }

  Widget _map() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: YeleColors.primary));
    }
    final pts = _filtered;
    return Stack(
      children: [
        FlutterMap(
          options: const MapOptions(
            initialCenter: LatLng(12.2, -1.5), // Burkina Faso
            initialZoom: 6,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.yele',
            ),
            MarkerLayer(
              markers: [
                for (final p in pts)
                  Marker(
                    point: LatLng(p.lat, p.lng),
                    width: 14,
                    height: 14,
                    child: Container(
                      decoration: BoxDecoration(
                        color: _colorFor(p.networkType).withValues(alpha: 0.75),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
        if (pts.isEmpty)
          Positioned(
            left: 0,
            right: 0,
            bottom: 16,
            child: Center(
              child: Text('Aucune donnée de couverture pour ce filtre.',
                  style: TextStyle(color: YeleColors.surface.ink, fontSize: 13)),
            ),
          ),
      ],
    );
  }

  Widget _legend() {
    Widget t(String label, Color c) => Container(
          width: 30,
          height: 30,
          margin: const EdgeInsets.only(left: 6),
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Text(label,
              style: const TextStyle(
                  color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
        );

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Text('${_filtered.length} mesures',
              style: TextStyle(
                  color: YeleColors.surface.ink,
                  fontSize: 12,
                  fontWeight: FontWeight.w700)),
          const Spacer(),
          t('2G', YeleColors.g2),
          t('3G', YeleColors.g3),
          t('4G', YeleColors.g4),
          t('4G+', YeleColors.g4p),
          t('5G', YeleColors.g5),
        ],
      ),
    );
  }

  Widget _operatorBar() {
    return Container(
      color: YeleColors.field,
      child: Row(
        children: [
          Container(
            width: 54,
            height: 48,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              border: Border(right: BorderSide(color: Colors.white24)),
            ),
            child: const Text('BF',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _operator,
                  isExpanded: true,
                  dropdownColor: YeleColors.field,
                  iconEnabledColor: Colors.white,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  items: _operators
                      .map((o) =>
                          DropdownMenuItem(value: o, child: Text('$o Mobile')))
                      .toList(),
                  onChanged: (v) => setState(() => _operator = v ?? 'Tous'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
