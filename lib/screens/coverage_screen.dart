import 'dart:math' show Point;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../models/speed_test_result.dart';
import '../services/local_storage_service.dart';
import '../services/location_service.dart';
import '../theme/yele_theme.dart';
import '../widgets/yele_scaffold.dart';
import 'burkina_outline.dart';
import 'coverage_map_data.dart';

/// Bornes du Burkina Faso (limites de la carte : impossible de sortir du pays,
/// comme sur le dashboard). Calculées une fois à partir du contour OSM.
final LatLngBounds kBurkinaBounds = LatLngBounds.fromPoints(kBurkinaOutline);

/// IMP-10 / ISS-11 — Onglet « Carte » de l'application.
///
/// Portage fidèle de l'onglet Carte du dashboard (yele-observatoire, js/map.js
/// + js/quality.js) avec UNE différence assumée : la source des données est
/// l'ONGLET HISTORIQUE DU TÉLÉPHONE (mesures de l'utilisateur local), alors
/// que le dashboard affiche toutes les mesures de la base.
class CoverageScreen extends StatefulWidget {
  const CoverageScreen({super.key});

  @override
  State<CoverageScreen> createState() => _CoverageScreenState();
}

class _CoverageScreenState extends State<CoverageScreen> {
  final _mapController = MapController();
  final _location = LocationService();
  final LocalStorageService _storage = LocalStorageService();

  List<MapPoint> _all = [];
  bool _loaded = false;
  bool _mapReady = false;

  // ── État du portage (même sémantique que state de map.js) ──
  String _mapType = 'global'; // global|coverage|dl|ul|ping|streaming|browsing
  String _netType = 'mobile'; // mobile|fixe
  String _operator = ''; // '' = Tous (l'opérateur est obligatoire côté web)
  String _tech = ''; // techno: '' = toutes (mobile seulement)
  String _lieu = ''; // ville: '' = tous
  String _mode = 'points'; // points|heatmap
  String _base = 'plan'; // plan|satellite
  final Map<String, Set<String>> _periodValues = {}; // grain -> clés actives

  // ISS-11 — Position de l'utilisateur (pin bleu + recentrage).
  Position? _userPosition;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    _loadLocalResults();
  }

  /// Source des données : historique local du téléphone.
  void _loadLocalResults() {
    List<SpeedTestResult> results;
    try {
      results = _storage.getAllResults();
    } catch (_) {
      results = const [];
    }
    if (!mounted) return;
    setState(() {
      _all = [for (final r in results) if (r.latitude != 0 || r.longitude != 0) MapPoint.fromResult(r)];
      _loaded = true;
    });
  }

  List<MapPoint> get _visible {
    var pts = _all.where((p) => _netType == 'mobile'
        ? p.cellular
        : !p.cellular);
    pts = pts.where((p) => p.lat != 0 || p.lng != 0);
    if (_operator.isNotEmpty) {
      pts = pts.where((p) => p.operatorName == _operator);
    }
    if (_netType == 'mobile' && _tech.isNotEmpty) {
      pts = pts.where((p) => p.networkType == _tech);
    }
    if (_lieu.isNotEmpty) {
      pts = pts.where((p) => p.city == _lieu);
    }
    for (final e in _periodValues.entries) {
      if (e.value.isEmpty) continue;
      pts = pts.where((p) => e.value.contains(periodKeyOf(p.timestamp, e.key)));
    }
    return pts.toList();
  }

  List<String> get _operatorChoices {
    // Filtre limité aux 3 opérateurs mobiles officiels (référentiel ARCEP),
    // normalisés ; les variantes (« Orange Burkina Faso »…) pointent dessus.
    final present = {for (final p in _all) p.operatorName};
    return kMobileOperators.where(present.contains).toList();
  }

  List<String> get _techChoices {
    final ranks = <String, int>{};
    for (final p in _all.where((p) => p.cellular)) {
      ranks[p.networkType] = netRank(p.networkType);
    }
    final list = ranks.keys.where((t) => netRank(t) > 0).toList();
    list.sort((a, b) => netRank(b) - netRank(a));
    return list;
  }

  List<String> get _lieuChoices {
    final s = {for (final p in _visible) p.city};
    return (s.toList()..sort()).where((e) => e.isNotEmpty).toList();
  }

  Map<String, List<String>> get _periodBuckets {
    final out = <String, List<String>>{};
    for (final grain in kGrainLabels.keys) {
      if (grain == 'all') continue;
      final keys = {for (final p in _visible) periodKeyOf(p.timestamp, grain)}.toList()..sort();
      out[grain] = keys;
    }
    return {for (final e in out.entries) e.key: e.value};
  }

  // ── ISS-11 : Localisez-moi ──
  Future<void> _locateMe() async {
    if (_locating) return;
    setState(() => _locating = true);
    final pos = await _location.requestGpsPosition();
    if (!mounted) return;
    setState(() {
      _locating = false;
      _userPosition = pos;
    });
    if (pos == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Localisation indisponible (GPS ou permission).'),
        backgroundColor: Colors.red,
      ));
      return;
    }
    _mapController.move(LatLng(pos.latitude, pos.longitude), 14);
  }

  void _resetFilters() {
    setState(() {
      _mapType = 'global';
      _netType = 'mobile';
      _operator = '';
      _tech = '';
      _lieu = '';
      _mode = 'points';
      _base = 'plan';
      _periodValues.clear();
    });
    _fitBounds();
  }

  void _fitBounds() {
    final pts = _visible;
    if (pts.isEmpty) return;
    final bounds = LatLngBounds.fromPoints([for (final p in pts) LatLng(p.lat, p.lng)]);
    if (bounds.west == bounds.east && bounds.south == bounds.north) {
      _mapController.move(LatLng(pts.first.lat, pts.first.lng), 14);
      return;
    }
    _mapController.fitCamera(
      CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(40)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return YeleScaffold(
      title: 'Carte',
      route: '/coverage',
      body: Column(
        children: [
          _modeBar(),
          _viewBar(),
          _filterBar(),
          Expanded(child: _mapStack()),
        ],
      ),
    );
  }

  // ── Barre des 7 types de carte ──
  Widget _modeBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: SizedBox(
        height: 32,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          children: [
            for (final entry in kMapTypeLabels.entries)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(entry.value,
                      style: TextStyle(
                          fontSize: 12,
                          color: _mapType == entry.key
                              ? Colors.white
                              : YeleColors.surface.ink)),
                  selected: _mapType == entry.key,
                  selectedColor: YeleColors.primary,
                  showCheckmark: false,
                  labelPadding: const EdgeInsets.symmetric(horizontal: 8),
                  onSelected: (_) => setState(() => _mapType = entry.key),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Affichage : points/heat + plan/satellite + reset ──
  Widget _viewBar() {
    Widget seg(List<(String, String)> items, String value, void Function(String) onSet) {
      return Container(
        decoration: BoxDecoration(
          color: YeleColors.field,
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.all(2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (v, label) in items)
              GestureDetector(
                onTap: () => onSet(v),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: value == v ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(label,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: value == v ? YeleColors.primary : Colors.white)),
                ),
              ),
          ],
        ),
      );
    }

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          seg(
            const [('points', 'Points'), ('heatmap', 'Chaleur')],
            _mode,
            (v) => setState(() => _mode = v),
          ),
          const SizedBox(width: 8),
          seg(
            const [('plan', 'Plan'), ('satellite', 'Satellite')],
            _base,
            (v) => setState(() => _base = v),
          ),
          const Spacer(),
          // Compteur de tests affichés (filtres appliqués), ex-barre du bas.
          Text('${_visible.length} tests',
              key: const ValueKey('coverage-test-count'),
              style: TextStyle(
                  color: YeleColors.surface.ink,
                  fontSize: 12,
                  fontWeight: FontWeight.w700)),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Réinitialiser les filtres',
            iconSize: 20,
            color: YeleColors.muted,
            onPressed: _resetFilters,
            icon: const Icon(Icons.restart_alt),
          ),
        ],
      ),
    );
  }

  // ── Filtres : réseau / opérateur / techno / lieu / période ──
  Widget _filterBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.only(bottom: 4),
      child: SizedBox(
        height: 36,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          children: [
            // Réseau : mobile / fixe
            _pillToggle('Mobile', Icons.smartphone, _netType == 'mobile',
                () => setState(() => _netType = 'mobile')),
            _pillToggle('Fixe', Icons.home, _netType == 'fixe',
                () => setState(() => _netType = 'fixe')),
            const VerticalDivider(width: 10),
            _dropDown('Opérateur',
                ['', ..._operatorChoices],
                _operator,
                (v) => setState(() => _operator = v ?? ''),
                (v) => v.isEmpty ? 'Tous les opérateurs' : v),
            if (_netType == 'mobile')
              _dropDown('Technologie',
                  ['', ..._techChoices],
                  _tech,
                  (v) => setState(() => _tech = v ?? ''),
                  (v) => v.isEmpty ? 'Techno : Toutes' : 'Techno : $v'),
            _dropDown('Lieu',
                ['', ..._lieuChoices],
                _lieu,
                (v) => setState(() => _lieu = v ?? ''),
                (v) => v.isEmpty ? 'Tous les lieux' : v),
            _sheetButton('Période', Icons.schedule, count: _activePeriodCount),
          ],
        ),
      ),
    );
  }

  int get _activePeriodCount =>
      _periodValues.values.fold(0, (n, s) => n + s.length);

  Widget _pillToggle(String label, IconData icon, bool active, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: active ? YeleColors.primary : YeleColors.field,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(children: [
            Icon(icon, size: 14, color: Colors.white),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
          ]),
        ),
      ),
    );
  }

  Widget _dropDown(String hint, List<String> choices, String value,
      void Function(String?) onChanged, String Function(String) labelOf) {
    return Container(
      height: 32,
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: YeleColors.field,
        borderRadius: BorderRadius.circular(18),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: choices.contains(value) ? value : '',
          isDense: true,
          dropdownColor: YeleColors.field,
          iconEnabledColor: Colors.white,
          hint: Text(hint, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          style: const TextStyle(color: Colors.white, fontSize: 12),
          items: [
            for (final c in choices)
              DropdownMenuItem(value: c, child: Text(labelOf(c)))
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _sheetButton(String label, IconData icon, {int count = 0}) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: _openPeriodSheet,
      child: Container(
        height: 32,
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: count > 0 ? YeleColors.primary : YeleColors.field,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 4),
          Text('$label${count > 0 ? ' ($count)' : ''}',
              style: const TextStyle(color: Colors.white, fontSize: 12)),
        ]),
      ),
    );
  }

  // ── Feuille de période (grain + clés multisélection, cumulables) ──
  Future<void> _openPeriodSheet() async {
    final buckets = _periodBuckets;
    final selected = {
      for (final e in _periodValues.entries) e.key: {...e.value},
    };
    String grain = selected.keys.isNotEmpty ? selected.keys.first : 'week';

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (sheetCtx) {
        return StatefulBuilder(builder: (sheetCtx, setSheetState) {
          final keys = grain == 'all' ? <String>[] : (buckets[grain] ?? []);
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('🕓 Filtre de période',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final g in kGrainLabels.keys)
                        FilterChip(
                          label: Text(kGrainLabels[g]!, style: const TextStyle(fontSize: 12)),
                          selected: grain == g,
                          onSelected: (_) => setSheetState(() => grain = g),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (grain == 'all')
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                          '« Tout » : toutes les dates. Choisis un grain pour restreindre.',
                          style: TextStyle(fontSize: 12, color: YeleColors.muted)),
                    )
                  else if (keys.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text('Aucune date dans cette granularité.',
                          style: TextStyle(fontSize: 12, color: YeleColors.muted)),
                    )
                  else
                    SizedBox(
                      height: 150,
                      child: SingleChildScrollView(
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            for (final k in keys)
                              FilterChip(
                                label: Text(_periodLabel(grain, k),
                                    style: const TextStyle(fontSize: 12)),
                                selected: selected[grain]?.contains(k) ?? false,
                                onSelected: (sel) => setSheetState(() {
                                  final set = selected.putIfAbsent(grain, () => {});
                                  if (sel) {
                                    set.add(k);
                                  } else {
                                    set.remove(k);
                                  }
                                }),
                              ),
                          ],
                        ),
                      ),
                    ),
                  Row(children: [
                    TextButton(
                      onPressed: () {
                        selected.clear();
                        Navigator.pop(sheetCtx);
                      },
                      child: const Text('Réinitialiser'),
                    ),
                    const Spacer(),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: YeleColors.primary),
                      onPressed: () {
                        setState(() {
                          _periodValues
                            ..clear()
                            ..addAll({
                              for (final e in selected.entries)
                                if (e.value.isNotEmpty) e.key: {...e.value},
                            });
                        });
                        Navigator.pop(sheetCtx);
                      },
                      child: const Text('Filtrer',
                          style: TextStyle(color: Colors.white)),
                    ),
                  ]),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  String _periodLabel(String grain, String key) {
    switch (grain) {
      case 'year':
        return key;
      case 'month':
        final p = key.split('-');
        return p.length == 2 ? '${p[1]}/${p[0]}' : key;
      case 'week':
        final p = key.split('-');
        return p.length == 3 ? 'Sem. du ${p[2]}/${p[1]}' : key;
      case 'day':
        final p = key.split('-');
        return p.length == 3 ? '${p[2]}/${p[1]}/${p[0]}' : key;
      case 'hour':
        return '${key}h';
      default:
        return key;
    }
  }

  // ── Carte ──
  Widget _mapStack() {
    if (!_loaded) {
      return const Center(
          child: CircularProgressIndicator(color: YeleColors.primary));
    }
    final pts = _visible;
    return Stack(
      children: [
        _mapWidget(pts),
        if (pts.isEmpty)
          Positioned(
            left: 0,
            right: 0,
            top: 10,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(_emptyMessage(),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: YeleColors.surface.ink, fontSize: 12.5)),
              ),
            ),
          ),
        // ISS-11 — Bouton « Localisez-moi » : pin + recentrage sur la position.
        Positioned(
          right: 12,
          bottom: 16,
          child: _locating
              ? const SizedBox(
                  width: 40,
                  height: 40,
                  child: CircularProgressIndicator(color: YeleColors.primary))
              : FloatingActionButton.extended(
                  heroTag: 'coverage-locate',
                  backgroundColor: Colors.white,
                  foregroundColor: YeleColors.primary,
                  icon: const Icon(Icons.my_location, size: 20),
                  label: const Text('Localisez-moi',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  onPressed: _locateMe,
                ),
        ),
        // ── Attribution des tuiles (obligation des fournisseurs) :
        // OpenStreetMap en Plan, Esri World Imagery en Satellite.
        Positioned(
          left: 8,
          bottom: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              _base == 'satellite'
                  ? '© Esri, Maxar, Earthstar Geographics'
                  : '© OpenStreetMap contributors',
              style: TextStyle(
                  color: YeleColors.surface.ink.withValues(alpha: 0.75),
                  fontSize: 9),
            ),
          ),
        ),
        // ── Légende flottante façon dashboard : carte blanche juste
        // au-dessus du bouton « Localisez-moi », contenu selon la chip.
        if (!_locating)
          Positioned(
            right: 12,
            bottom: 84,
            child: _floatingLegend(),
          ),
      ],
    );
  }

  String _emptyMessage() {
    if (_all.isEmpty) {
      return "Aucune mesure dans l'historique de ce téléphone.\nFais un test puis reviens ici.";
    }
    if (_operator.isEmpty && _netType == 'mobile') {
      final cell = _all.where((p) => p.cellular).length;
      if (cell == 0) {
        return 'Toutes tes mesures sont en WiFi : passe le filtre sur « Fixe »\nou fais un test en données mobiles.';
      }
    }
    return 'Aucune mesure pour ces filtres. Réinitialise la vue.';
  }

  Widget _mapWidget(List<MapPoint> pts) {
    MapOptions buildOptions() {
      final p = _visible;
      final geo = [for (final x in p) LatLng(x.lat, x.lng)];
      return MapOptions(
        // Bornes du Burkina (comme le web) : impossible de sortir du pays.
        cameraConstraint: CameraConstraint.contain(bounds: kBurkinaBounds),
        initialCameraFit: geo.length <= 1
            ? const CameraFit.coordinates(
                coordinates: [LatLng(12.3714, -1.5197)], // Ouagadougou
                maxZoom: 11,
              )
            : CameraFit.bounds(
                bounds: LatLngBounds.fromPoints(geo),
                padding: const EdgeInsets.all(40),
              ),
        onMapReady: () => setState(() => _mapReady = true),
        onPositionChanged: (_, _) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() {}); // re-regroupe les zones à chaque zoom
          });
        },
        onTap: (_, _) => FocusScope.of(context).unfocus(),
      );
    }

    String urlTemplate;
    if (_base == 'satellite') {
      // Esri World Imagery : gratuit, tuiles au format {z}/{y}/{x}.
      urlTemplate =
          'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
    } else {
      // Plan : tuiles OSM standard (libellés français).
      urlTemplate = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
    }

    return FlutterMap(
      mapController: _mapController,
      options: buildOptions(),
      children: [
        TileLayer(
          urlTemplate: urlTemplate,
          userAgentPackageName: 'com.yele',
        ),
        PolygonLayer(
          polygons: [
            // IMP-10 — Masque extérieur du pays (monde troué à la forme du BF).
            Polygon(
              points: const [
                LatLng(-84, -180),
                LatLng(84, -180),
                LatLng(84, 180),
                LatLng(-84, 180),
              ],
              holePointsList: [kBurkinaOutline],
              color: _base == 'satellite'
                  ? const Color(0xC9F4F6FA) // quasi opaque hors du pays
                  : const Color(0x99F4F6FA),
              borderColor: YeleColors.primary,
              borderStrokeWidth: 1.5,
            ),
          ],
        ),
        if (_mode == 'heatmap')
          MarkerLayer(markers: [for (final z in _zonesOf(pts)) _heatMarker(z)])
        else
          MarkerLayer(markers: [for (final z in _zonesOf(pts)) _zoneMarker(z)]),
        // ISS-11 — Pin bleu de la position de l'utilisateur.
        if (_userPosition != null)
          MarkerLayer(
            markers: [
              Marker(
                point: LatLng(_userPosition!.latitude, _userPosition!.longitude),
                width: 20,
                height: 20,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  // ── Regroupement en zones (rayon fixe à l'écran, CLUSTER_PX = 34) ──
  static const double _clusterPx = 34;

  List<_Zone> _zonesOf(List<MapPoint> pts) {
    if (!_mapReady || pts.isEmpty) return [];
    try {
      final camera = _mapController.camera;
      final screen = <Point<double>>[];
      for (final p in pts) {
        screen.add(camera.latLngToScreenPoint(LatLng(p.lat, p.lng)));
      }
      final assigned = List<bool>.filled(pts.length, false);
      final zones = <_Zone>[];
      for (var i = 0; i < pts.length; i++) {
        if (assigned[i]) continue;
        assigned[i] = true;
        final group = [pts[i]];
        var sx = screen[i].x, sy = screen[i].y;
        for (var j = i + 1; j < pts.length; j++) {
          if (assigned[j]) continue;
          final d = Point<double>(
                  screen[j].x - screen[i].x, screen[j].y - screen[i].y)
              .magnitude;
          if (d <= _clusterPx) {
            assigned[j] = true;
            group.add(pts[j]);
            sx += screen[j].x;
            sy += screen[j].y;
          }
        }
        // Centroïde géographique (approx. équirectangulaire suffisante ici).
        final lat = group.map((p) => p.lat).reduce((a, b) => a + b) / group.length;
        final lng = group.map((p) => p.lng).reduce((a, b) => a + b) / group.length;
        zones.add(_Zone(
          lat: lat,
          lng: lng,
          points: group,
          screen: Point<double>(sx / group.length, sy / group.length),
        ));
      }
      return zones;
    } catch (_) {
      return [];
    }
  }

  double _zoneRadius(int count, {bool heat = false}) {
    final base = count == 1
        ? 7.0
        : count <= 3
            ? 11.0
            : count <= 8
                ? 15.0
                : 19.0;
    return heat ? base * 2.3 : base;
  }

  Color _zoneColor(List<MapPoint> group) {
    if (_mapType == 'coverage') {
      final best = bestTechOf(group);
      return best != null ? coverageColor(best) : YeleColors.muted;
    }
    final levels = [for (final p in group) levelOf(p, _mapType)];
    if (levels.isEmpty) return YeleColors.muted;
    final avg = levels.reduce((a, b) => a + b) / levels.length;
    return levelColor(avg.round());
  }

  Marker _zoneMarker(_Zone z) {
    final radius = _zoneRadius(z.points.length);
    final color = _zoneColor(z.points);
    return Marker(
      point: LatLng(z.lat, z.lng),
      width: radius * 2,
      height: radius * 2,
      child: GestureDetector(
        onTap: () => _openZoneSheet(z),
        child: Container(
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.85),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 1.5),
            boxShadow: const [
              BoxShadow(color: Colors.black26, blurRadius: 3, offset: Offset(0, 1)),
            ],
          ),
          alignment: Alignment.center,
          child: z.points.length > 1
              ? Text('${z.points.length}',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700))
              : null,
        ),
      ),
    );
  }

  /// Chaleur : densité (fixe) ou taches colorées par niveau (mobile).
  /// Les listes de couleurs et d'arrêts doivent TOUJOURS être de même
  /// longueur (sinon RadialGradient lève une exception et rien n'est peint).
  Marker _heatMarker(_Zone z) {
    final radius = _zoneRadius(z.points.length, heat: true);
    final List<Color> colors;
    final List<double> stops;
    if (_netType == 'fixe') {
      // Chaleur Fixe : densité seule (toutes les mesures intensité 1,
      // sémantique du web) — teinte bleu nuit du dashboard.
      colors = const [Color(0x802F6BFF), Color(0x002F6BFF)];
      stops = const [0.0, 1.0];
    } else {
      final c = _zoneColor(z.points);
      colors = [
        c.withValues(alpha: 0.55),
        c.withValues(alpha: 0.28),
        c.withValues(alpha: 0.0),
      ];
      stops = const [0.0, 0.55, 1.0];
    }
    return Marker(
      point: LatLng(z.lat, z.lng),
      width: radius * 2,
      height: radius * 2,
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: colors, stops: stops),
        ),
      ),
    );
  }

  // ── Popup d'une zone (comme les popups du web, ventilés sur l'historique) ──
  void _openZoneSheet(_Zone z) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _ZoneSheet(zone: z, mapType: _mapType, netType: _netType),
    );
  }

  // ── Légende flottante façon dashboard (carte blanche en bas à droite,
  // juste au-dessus de « Localisez-moi ») : titre gras + pastille + libellé
  // court + fourchette, contenu selon la chip active (kMapTypeLabels).
  Widget _floatingLegend() {
    final entries = <(Color, String, String)>[
      if (_mapType == 'coverage')
        ...[
          for (final t in ['2G', '3G', '4G', '4G+', '5G'])
            (coverageColor(t), t, ''),
          (YeleColors.muted, 'Non précisé', ''),
        ]
      else
        for (final (lvl, label, range) in legendFloatEntriesOf(_mapType))
          (lvl == 0 ? YeleColors.muted : levelColor(lvl), label, range),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(legendFloatTitleOf(_mapType),
              style: TextStyle(
                  color: YeleColors.surface.ink,
                  fontSize: 12,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          for (final (color, label, range) in entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1.5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 11,
                    height: 11,
                    decoration: BoxDecoration(
                        color: color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Text(label,
                      style: TextStyle(
                          color: YeleColors.surface.ink,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600)),
                  if (range.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(range,
                        style: TextStyle(
                            color: YeleColors.muted, fontSize: 10)),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// ── Zone regroupée sur la carte ──
class _Zone {
  final double lat, lng;
  final List<MapPoint> points;
  final Point<double> screen;
  _Zone({required this.lat, required this.lng, required this.points, required this.screen});
}

/// ── Feuille de détails d'une zone (popup façon dashboard) ──
class _ZoneSheet extends StatelessWidget {
  final _Zone zone;
  final String mapType;
  final String netType;

  const _ZoneSheet({required this.zone, required this.mapType, required this.netType});

  static String _d1(double v) => v.toStringAsFixed(1).replaceAll('.', ',');
  static String _sec(double ms) => '${(ms / 1000).toStringAsFixed(1).replaceAll('.', ',')} s';

  @override
  Widget build(BuildContext context) {
    final pts = zone.points;
    final cell = pts.where((p) => p.cellular).length;
    final fixe = pts.length - cell;
    final best = bestTechOf(pts);
    final dl = pts.map((p) => p.download).reduce((a, b) => a + b) / pts.length;
    final ul = pts.map((p) => p.upload).reduce((a, b) => a + b) / pts.length;
    final ping = pts.map((p) => p.ping).reduce((a, b) => a + b) / pts.length;
    final strs = pts.where((p) => p.streamingScore != null).toList();
    final brs = pts.where((p) => p.browsingLoadMs != null).toList();
    final streamAvg = strs.isEmpty
        ? null
        : strs.map((p) => p.streamingScore ?? 0.0).reduce((a, b) => a + b) / strs.length;
    final browseAvg = brs.isEmpty
        ? null
        : brs.map((p) => p.browsingLoadMs ?? 0.0).reduce((a, b) => a + b) / brs.length;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(zone.points.first.city.isNotEmpty ? zone.points.first.city : 'Zone de tests',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            ),
            Text('${pts.length} test${pts.length > 1 ? 's' : ''}',
                style: TextStyle(color: YeleColors.muted, fontSize: 12)),
          ]),
          const SizedBox(height: 4),
          Wrap(spacing: 6, runSpacing: 4, children: [
            _badge(
                fixe > 0 && cell > 0
                    ? '$fixe fixe · $cell mobile'
                    : fixe > 0
                        ? 'Réseau fixe (WiFi)'
                        : 'Réseau mobile',
                color: YeleColors.primary),
            if (best != null) _badge('Couverture dominante : $best', color: coverageColor(best)),
            _badge('Zones regroupées · source : historique du téléphone', color: YeleColors.muted),
          ]),
          const Divider(height: 18),
          Wrap(spacing: 14, runSpacing: 6, children: [
            _metric(_d1(dl), 'Mb/s ↓ moy.'),
            _metric(_d1(ul), 'Mb/s ↑ moy.'),
            _metric('${ping.round()}', 'ms moy.'),
            _metric(strs.isEmpty ? '—' : '${streamAvg!.round()}', 'pts streaming'),
            _metric(brs.isEmpty ? '—' : _sec(browseAvg!), 'navigation web'),
          ]),
          const Divider(height: 18),
          Flexible(
            child: SingleChildScrollView(
              child: Column(children: [for (final p in pts) _testRow(p)]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _badge(String text, {required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }

  Widget _metric(String value, String label) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
      Text(label, style: TextStyle(color: YeleColors.muted, fontSize: 10.5)),
    ]);
  }

  Widget _testRow(MapPoint p) {
    final d = p.timestamp;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Container(
          width: 10, height: 10,
          decoration: BoxDecoration(color: colorFor(p, mapType), shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              '${d.day}/${d.month}/${d.year} ${d.hour}h${d.minute.toString().padLeft(2, '0')} — ${p.networkType} · ${p.operatorName}',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: YeleColors.surface.ink),
            ),
            Text(
              '↓ ${_d1(p.download)} Mb/s · ↑ ${_d1(p.upload)} Mb/s · ${p.ping.round()} ms'
              '${p.streamingScore != null ? ' · streaming ${p.streamingScore!.round()} pts' : ''}'
              '${p.browsingLoadMs != null ? ' · navigation ${_sec(p.browsingLoadMs!)}' : ''}',
              style: TextStyle(color: YeleColors.muted, fontSize: 11),
            ),
          ]),
        ),
      ]),
    );
  }
}
