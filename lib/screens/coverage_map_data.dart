import 'package:flutter/material.dart';

import '../models/speed_test_result.dart';
import '../theme/yele_theme.dart';

/// ─── Portage de l'onglet « Carte » du dashboard (js/map.js + js/quality.js)
///
/// Les données viennent de l'ONGLET HISTORIQUE DU TÉLÉPHONE (SparkTestResult
/// local) et non de /api/dashboard/map : la carte de l'application ne montre
/// que les MESURES DE L'UTILISATEUR (voir B4 — IMP-10 / ISS-11).

/// Référentiel des opérateurs mobiles du Burkina (libellés ARCEP utilisés dans
/// l'app) ; le filtre Opérateur mobile est limité à ceux-ci.
const List<String> kMobileOperators = <String>[
  'Orange BF SA',
  'Telecel Faso SA',
  'Moov Africa SA',
];

/// Unifie les variantes de libellés d'opérateur (« Orange Burkina Faso »,
/// « TELECEL BURKINA »…) vers les libellés ARCEP ci-dessus.
String normalizeOperator(String raw) {
  final s = raw.trim().toLowerCase();
  if (s.contains('orange')) return 'Orange BF SA';
  if (s.contains('moov')) return 'Moov Africa SA';
  if (s.contains('telecel') || s.contains('telmob')) return 'Telecel Faso SA';
  return raw.trim();
}

/// Un test local projeté sur la carte.
class MapPoint {
  final double lat;
  final double lng;
  final String operatorName; // Opérateur mobile ou FAI (déduit de l'IP)
  final String networkType; // 'WiFi', '2G', '3G', '4G', '4G+', '5G'…
  final bool cellular; // test passé par le réseau MOBILE (WiFi = fixe)
  final double download;
  final double upload;
  final double ping;
  final double? streamingScore; // null si non mesuré (0 = absent côté web)
  final double? browsingLoadMs; // null si non mesuré
  final DateTime timestamp;
  final String city; // partie avant la première virgule de [location]

  MapPoint._({
    required this.lat,
    required this.lng,
    required this.operatorName,
    required this.networkType,
    required this.cellular,
    required this.download,
    required this.upload,
    required this.ping,
    required this.streamingScore,
    required this.browsingLoadMs,
    required this.timestamp,
    required this.city,
  });

  factory MapPoint.fromResult(SpeedTestResult r) {
    final cellular = _isCellular(r.networkType);
    // Opérateur : SIM pour un test en données mobiles, sinon FAI déduit de
    // l'IP ; dénormalisé vers les libellés ARCEP, '' si inconnu.
    final rawOp = (r.simOperator ?? '').isNotEmpty && cellular
        ? r.simOperator!
        : (r.operator ?? '').trim();
    return MapPoint._(
      lat: r.latitude ?? 0,
      lng: r.longitude ?? 0,
      operatorName: rawOp.isEmpty ? '' : normalizeOperator(rawOp),
      networkType: _normalizeNetwork(r.networkType),
      cellular: cellular,
      download: r.downloadSpeed,
      upload: r.uploadSpeed,
      ping: r.ping,
      streamingScore: (r.streamingScore ?? 0) > 0 ? r.streamingScore : null,
      browsingLoadMs:
          (r.browsingAvgLoadMs ?? 0) > 0 ? r.browsingAvgLoadMs : null,
      timestamp: r.timestamp,
      city: _cleanCity(r.location),
    );
  }

  /// Ville mesurable : partie avant la première virgule de [location].
  /// Un libellé « pays seul » (BF, Burkina Faso) ou vide n'est PAS une ville :
  /// il est écarté de la liste des lieux mais la mesure reste comptée.
  static String _cleanCity(String? location) {
    final head = (location ?? '').split(',')[0].trim();
    final lower = head.toLowerCase();
    if (head.isEmpty ||
        head.length <= 3 ||
        lower == 'bf' ||
        lower == 'burkina faso' ||
        lower == 'unknown') {
      return '';
    }
    return head;
  }

  static bool _isCellular(String? networkType) {
    final n = (networkType ?? '').trim().toUpperCase();
    return n.isNotEmpty && !n.contains('WIFI') && !n.contains('NON PRÉCISÉ');
  }

  static String _normalizeNetwork(String? networkType) {
    final n = (networkType ?? '').trim().toUpperCase();
    if (n.contains('LTE+')) return '4G+';
    if (n.contains('4G+') || n.contains('4.5G')) return '4G+';
    if (n.contains('LTE') || n.contains('4G')) return '4G';
    if (n.contains('3G') || n.contains('H+') || n.contains('HSPA')) return '3G';
    if (n.contains('2G') || n.contains('EDGE') || n.contains('GPRS')) return '2G';
    if (n.contains('5G')) return '5G';
    return (networkType ?? '').trim().isEmpty ? 'Non précisé' : 'WiFi';
  }
}

/// ─── Niveaux qualité 1-4 (0 = indisponible) — référentiel SEUILS.md ─────────

int dlLevel(double v) => v >= 30 ? 4 : v >= 10 ? 3 : v >= 5 ? 2 : 1;
int ulLevel(double v) =>
    v >= 10 ? 4 : v >= 5 ? 3 : v >= 1.5 ? 2 : 1;
int pingLevel(double v) =>
    v <= 0 ? 0 : v < 30 ? 4 : v < 80 ? 3 : v < 200 ? 2 : 1;
int streamLevel(double? s) =>
    s == null ? 0 : s >= 80 ? 4 : s >= 60 ? 3 : s >= 40 ? 2 : 1;
int browseLevel(double? ms) =>
    ms == null ? 0 : ms < 2000 ? 4 : ms < 5000 ? 3 : ms < 10000 ? 2 : 1;

/// Niveau (1-4, 0 si indisponible) d'un point pour le type de carte demandé.
/// « global » = moyenne des niveaux presents (dq + montée + latence +
/// streaming + navigation), chaque absence est ignorée.
int levelOf(MapPoint p, String mapType) {
  switch (mapType) {
    case 'global':
      final comps = <int>[
        dlLevel(p.download),
        ulLevel(p.upload),
        if (p.ping > 0) pingLevel(p.ping),
        if (p.streamingScore != null) streamLevel(p.streamingScore),
        if (p.browsingLoadMs != null) browseLevel(p.browsingLoadMs),
      ];
      if (comps.isEmpty) return 0;
      return (comps.reduce((a, b) => a + b) / comps.length).round();
    case 'dl':
      return dlLevel(p.download);
    case 'ul':
      return ulLevel(p.upload);
    case 'ping':
      return pingLevel(p.ping);
    case 'streaming':
      return streamLevel(p.streamingScore);
    case 'browsing':
      return browseLevel(p.browsingLoadMs);
    default:
      return 0;
  }
}

/// Couleur d'un niveau (palette du dashboard web : bleu > vert > orange > rouge).
Color levelColor(int level) {
  switch (level) {
    case 4:
      return const Color(0xFF2F6BFF); // très bonne → bleu
    case 3:
      return YeleColors.g3; // bonne → vert
    case 2:
      return YeleColors.g4; // limitée → orange
    case 1:
      return YeleColors.g4p; // très limitée → rouge
    default:
      return YeleColors.muted; // indisponible → gris
  }
}

/// ─── Couverture :palette nPerf 2G bleu / 3G vert / 4G orange / 5G violet ─────

int netRank(String net) {
  switch (net) {
    case '5G':
      return 5;
    case '4G+':
      return 4;
    case '4G':
      return 3;
    case '3G':
      return 2;
    case '2G':
      return 1;
    default:
      return 0;
  }
}

/// Meilleure technologie testée dans un ensemble de points.
String? bestTechOf(List<MapPoint> points) {
  final counts = <String, int>{};
  String? top;
  int topCount = 0;
  for (final p in points) {
    final t = p.networkType;
    if (netRank(t) == 0) continue;
    final c = (counts[t] ?? 0) + 1;
    counts[t] = c;
    if (c > topCount || (c == topCount && netRank(t) > netRank(top ?? ''))) {
      top = t;
      topCount = c;
    }
  }
  return top;
}

Color coverageColor(String net) {
  // Charte validée sur device (09/11) : 2G rouge, 3G orange, 4G et 4G+ vert,
  // 5G violet, non précisé gris — palette identique à la charte qualité.
  switch (net) {
    case '5G':
      return const Color(0xFF8A3FFC); // violet
    case '4G+':
    case '4G':
      return const Color(0xFF7AC143); // vert
    case '3G':
      return const Color(0xFFF5A623); // orange
    case '2G':
      return const Color(0xFFE0492F); // rouge
    default:
      return YeleColors.muted;
  }
}

/// Couleur d'un point pour le type de carte actif.
Color colorFor(MapPoint p, String mapType) {
  if (mapType == 'coverage') {
    return coverageColor(p.networkType);
  }
  return levelColor(levelOf(p, mapType));
}

/// ─── Libellés des 7 types de carte (mapType → (label, titre de légende)) ────

const Map<String, String> kMapTypeLabels = {
  'global': 'Global',
  'coverage': 'Couverture',
  'dl': 'Download',
  'ul': 'Upload',
  'ping': 'Latence',
  'streaming': 'Streaming',
  'browsing': 'Navigation',
};

/// Libellé court de chaque niveau 1-4 (charte unifiée app + dashboard,
/// référence SEUILS.md) — la palanquée : bleu > vert > orange > rouge.
List<(int, String)> legendShortLevelsOf(String mapType) {
  switch (mapType) {
    case 'global':
      return const [
        (4, 'Très bonne'),
        (3, 'Bonne'),
        (2, 'Limitée'),
        (1, 'Dégradée'),
      ];
    case 'dl':
    case 'ul':
      return const [
        (4, 'Très rapide'),
        (3, 'Rapide'),
        (2, 'Moyen'),
        (1, 'Lent'),
      ];
    case 'ping':
      return const [
        (4, 'Excellente'),
        (3, 'Bonne'),
        (2, 'Limitée'),
        (1, 'Faible'),
      ];
    case 'streaming':
      return const [
        (4, 'Fluide'),
        (3, 'Bon'),
        (2, 'Limité'),
        (1, 'Difficile'),
      ];
    case 'browsing':
      return const [
        (4, 'Très fluide'),
        (3, 'Fluide'),
        (2, 'Lente'),
        (1, 'Très lente'),
      ];
    default:
      return const [];
  }
}

/// Titre de la légende flottante (charte dashboard : kLegendTitles du web).
String legendFloatTitleOf(String mapType) {
  return switch (mapType) {
    'global' => 'Score global',
    'coverage' => 'Couverture',
    'dl' => 'Débit descendant',
    'ul' => 'Débit montant',
    'ping' => 'Latence',
    'streaming' => 'Streaming vidéo',
    'browsing' => 'Navigation web',
    _ => 'Légende',
  };
}

/// Légende flottante façon dashboard : (niveau, libellé, fourchette).
/// Niveau 1-4 = palette qualité ; 0 = gris (« non mesuré »). Ordre du pire
/// au meilleur (en bas = bleu, comme le dashboard). Couverture : 0 partout,
/// pastilles via [coverageColor]. Fourchettes = référence SEUILS.md.
List<(int, String, String)> legendFloatEntriesOf(String mapType) {
  switch (mapType) {
    case 'dl':
      return const [
        (1, 'Lent', '0 à 5 Mbps'),
        (2, 'Moyen', '5 à 10 Mbps'),
        (3, 'Rapide', '10 à 30 Mbps'),
        (4, 'Très rapide', '≥ 30 Mbps'),
        (0, 'non mesuré', ''),
      ];
    case 'ul':
      return const [
        (1, 'Lent', '0 à 1,5 Mbps'),
        (2, 'Moyen', '1,5 à 5 Mbps'),
        (3, 'Rapide', '5 à 10 Mbps'),
        (4, 'Très rapide', '≥ 10 Mbps'),
        (0, 'non mesuré', ''),
      ];
    case 'ping':
      return const [
        (1, 'Faible', '≥ 200 ms'),
        (2, 'Limitée', '80 à 200 ms'),
        (3, 'Bonne', '30 à 80 ms'),
        (4, 'Excellente', '< 30 ms'),
        (0, 'non mesuré', ''),
      ];
    case 'streaming':
      return const [
        (1, 'Difficile', '0 à 40 pts'),
        (2, 'Limité', '40 à 60 pts'),
        (3, 'Bon', '60 à 80 pts'),
        (4, 'Fluide', '≥ 80 pts'),
        (0, 'non mesuré', ''),
      ];
    case 'browsing':
      return const [
        (1, 'Très lente', '≥ 10 s'),
        (2, 'Lente', '5 à 10 s'),
        (3, 'Fluide', '2 à 5 s'),
        (4, 'Très fluide', '< 2 s'),
        (0, 'non mesuré', ''),
      ];
    case 'global':
      return const [
        (1, 'Dégradée', ''),
        (2, 'Limitée', ''),
        (3, 'Bonne', ''),
        (4, 'Très bonne', ''),
        (0, 'non mesuré', ''),
      ];
    default:
      return const [];
  }
}

/// ─── Périodes (grains cumulables, cf. map.js) ───────────────────────────────

String two(dynamic v) => v.toString().padLeft(2, '0');

/// Clé de période d'un instant, pour le grain donné (année, mois, semaine =
/// lundi, jour, heure). Retourne une clé de grain vide pour « all ».
String periodKeyOf(DateTime d, String grain) {
  switch (grain) {
    case 'year':
      return '${d.year}';
    case 'month':
      return '${d.year}-${two(d.month)}';
    case 'week':
      final monday = d.subtract(Duration(days: (d.weekday - 1)));
      return '${monday.year}-${two(monday.month)}-${two(monday.day)}';
    case 'day':
      return '${d.year}-${two(d.month)}-${two(d.day)}';
    case 'hour':
      return '${d.hour}';
    default:
      return '';
  }
}

const Map<String, String> kGrainLabels = {
  'all': 'Tout',
  'year': 'Années',
  'month': 'Mois',
  'week': 'Semaines',
  'day': 'Jours',
  'hour': 'Heures',
};
