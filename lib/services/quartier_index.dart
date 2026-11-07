import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart' show rootBundle;

/// Index embarqué des quartiers du Burkina Faso (ISS-10).
///
/// La base `lib/assets/quartiers_bf.json` est extraite d'OpenStreetMap
/// (Overpass, place=suburb/quarter/neighbourhood) complétée d'entrées
/// manuelles « seeded » pour les quartiers non taggés (ex. Zogona à
/// Ouagadougou, dont OSM ne portait que des POIs « … de Zogona »).
///
/// Usage : quand Nominatim ne fournit pas de champ quartier pour un GPS,
/// l'app sélectionne ici le quartier **le plus proche** du point, dans la
/// limite de [_maxPickDistanceM] — au-delà, on ne fabrique rien : l'adresse
/// reste sans quartier, comme une donnée OSM incomplète.
class QuartierIndex {
  QuartierIndex._(this._entries);

  static const double _earthRadiusM = 6371000;

  /// Distance max point↔quartier retenue (m). Un quartier de ville couvre
  /// typiquement moins d'un kilomètre de rayon ; 2 km évite d'attribuer le
  /// voisin erroné (ex. Kalgodin, à ~3 km du GPS testé, reste exclu).
  static const int _maxPickDistanceM = 2000;

  final List<QuartierEntry> _entries;
  bool loaded = false;

  static QuartierIndex? _instance;
  static QuartierIndex get instance => _instance ??= QuartierIndex._(const []);

  /// Index à entrées injectées pour les tests (par-dessus l'asset réel).
  QuartierIndex.withEntries(this._entries) : loaded = true;

  /// Index vide (retour à l'état initial en tests).
  QuartierIndex.empty() : _entries = const [], loaded = true;

  static void setInstanceForTest(QuartierIndex index) => _instance = index;

  /// Charge l'asset (une fois). En cas d'échec, l'index reste vide :
  /// l'adresse retombe sur les champs OSM seuls, sans levée d'erreur.
  Future<void> load() async {
    if (loaded || _entries.isNotEmpty) {
      loaded = true;
      return;
    }
    try {
      final raw = await rootBundle
          .loadString('lib/assets/quartiers_bf.json', cache: false);
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final list = (data['entries'] as List? ?? const [])
          .cast<Map<String, dynamic>>();
      _entries
        ..clear()
        ..addAll(list.map(QuartierEntry.fromJson));
    } catch (_) {
      // Asset indisponible (tests, emballage web) : index vide.
    }
    loaded = true;
  }

  /// Nombre d'entrées connues (diagnostic + tests).
  int get size => _entries.length;

  /// Nom du quartier le plus proche de (lat, lon), ou null si aucun
  /// candidat n'est assez près ([_maxPickDistanceM]).
  String? nearest(double lat, double lon) {
    if (_entries.isEmpty) return null;
    double? bestDist;
    var bestName = '';
    for (final e in _entries) {
      final d = distanceM(lat, lon, e.lat, e.lon);
      final dd = d.toDouble();
      if (d <= _maxPickDistanceM && (bestDist == null || dd < bestDist)) {
        bestDist = dd;
        bestName = e.name;
      }
    }
    return bestDist == null ? null : bestName;
  }

  /// Distance orthodromique (Haversine), en mètres, arrondie au mètre.
  static int distanceM(double lat1, double lon1, double lat2, double lon2) {
    const rad = math.pi / 180.0;
    final p1 = lat1 * rad, p2 = lat2 * rad;
    final dp = (lat2 - lat1) * rad, dl = (lon2 - lon1) * rad;
    final a = math.sin(dp / 2) * math.sin(dp / 2) +
        math.cos(p1) * math.cos(p2) * math.sin(dl / 2) * math.sin(dl / 2);
    final c = 2 * math.asin(math.sqrt(a.clamp(0.0, 1.0)));
    return (c * _earthRadiusM).round();
  }
}

/// Une entrée de la base embarquée.
class QuartierEntry {
  const QuartierEntry({
    required this.name,
    required this.lat,
    required this.lon,
    required this.kind,
  });

  final String name;
  final double lat;
  final double lon;
  final String kind; // suburb | quarter | neighbourhood | manual

  static QuartierEntry fromJson(Map<String, dynamic> j) => QuartierEntry(
        name: j['name'] as String? ?? '',
        lat: (j['lat'] as num?)?.toDouble() ?? 0,
        lon: (j['lon'] as num?)?.toDouble() ?? 0,
        kind: j['kind'] as String? ?? '',
      );
}
