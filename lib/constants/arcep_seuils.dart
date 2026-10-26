// ─── Référentiel ARCEP — seuils QoS validés (IMP-06) ───────────────────────
//
// Source unique : `config/seuils.json` (version 3) du dépôt `mobiletest`, qui
// reprend le rapport de synthèse QoS des réseaux mobiles d'ARCEP Burkina Faso
// (T1 2026, campagne du 23/02/2026 au 08/04/2026) et la présentation QoS du
// 29/05/2026 pour la navigation et le streaming.
//
// Ces valeurs servent au calcul des scores Navigation et Streaming : les
// changer change les scores affichés, pas seulement des libellés. Toute
// évolution doit être répercutée dans `config/seuils.json` et datée dans
// `docs/registre-revisions.md`.
//
// Règle d'honnêteté (cf. champ `method_note` du référentiel) : la comparaison
// ARCEP reste simplifiée. Aucun écran ne doit afficher « conforme » à partir de
// ces seuils. Fiche : `docs/fiches/IMP-06-seuils-arcep-scoring.md`.

/// Seuils ARCEP de la navigation web.
class ArcepSeuilsNavigation {
  /// Temps de chargement maximal d'une page, en secondes (ARCEP : 30 s).
  final double pageLoadS;

  /// Part minimale de pages chargées sous [pageLoadS] (ARCEP : 95 %).
  final double pageLoadPct;

  /// Temps maximal d'établissement de la connexion, en secondes (20 s).
  final double connectionS;

  /// Part minimale de connexions établies sous [connectionS] (95 %).
  final double transferPct;

  const ArcepSeuilsNavigation({
    required this.pageLoadS,
    required this.pageLoadPct,
    required this.connectionS,
    required this.transferPct,
  });
}

/// Seuils ARCEP du streaming vidéo, complétés par la définition Yélé d'une
/// session de bonne qualité : le rapport ARCEP ne définit pas « bonne qualité ».
class ArcepSeuilsStreaming {
  /// Démarrage maximal de la lecture, en secondes (ARCEP : 5 s).
  final double preloadS;

  /// Part minimale de sessions lancées sous [preloadS] (ARCEP : 95 %).
  final double qualityPct;

  /// Ratio de rebuffering maximal (définition Yélé : 10 %).
  final double rebufferRatioMax;

  /// Hauteur minimale de la résolution servie (définition Yélé : 480p).
  final int resolutionMinHeight;

  /// Nombre maximal d'interruptions (définition Yélé : 0).
  final int interruptionsMax;

  const ArcepSeuilsStreaming({
    required this.preloadS,
    required this.qualityPct,
    required this.rebufferRatioMax,
    required this.resolutionMinHeight,
    required this.interruptionsMax,
  });
}

/// Référentiel complet, avec la version du fichier `seuils.json` d'origine.
class ArcepSeuils {
  /// Version du référentiel (`config/seuils.json` → `version`).
  final String version;

  /// Source documentaire des seuils, affichée dans les écrans ARCEP.
  final String source;

  final ArcepSeuilsNavigation navigation;
  final ArcepSeuilsStreaming streaming;

  const ArcepSeuils({
    required this.version,
    required this.source,
    required this.navigation,
    required this.streaming,
  });

  /// Valeurs validées (seuils.json v3) — repli quand l'API n'est pas joignable.
  static const ArcepSeuils valides = ArcepSeuils(
    version: '3',
    source: 'ARCEP Burkina Faso — Rapport de synthèse QoS des réseaux mobiles, '
        'T1 2026 (campagne 23/02/2026 – 08/04/2026)',
    navigation: ArcepSeuilsNavigation(
      pageLoadS: 30,
      pageLoadPct: 95,
      connectionS: 20,
      transferPct: 95,
    ),
    streaming: ArcepSeuilsStreaming(
      preloadS: 5,
      qualityPct: 95,
      rebufferRatioMax: 0.10,
      resolutionMinHeight: 480,
      interruptionsMax: 0,
    ),
  );

  /// Surcharge depuis le champ `qos` de `/api/arcep/measure`.
  ///
  /// Un champ absent conserve la valeur validée : un backend plus ancien ne
  /// doit pas remettre les seuils à zéro. Le référentiel de l'API reste la
  /// référence (`config/seuils.json`), [valides] n'est qu'un repli.
  factory ArcepSeuils.fromApiJson(Map<String, dynamic> json) {
    final navigation = json['navigation'];
    final streaming = json['streaming'];
    final nav = navigation is Map<String, dynamic> ? navigation : const {};
    final stream = streaming is Map<String, dynamic> ? streaming : const {};

    return ArcepSeuils(
      version: json['version']?.toString() ?? valides.version,
      source: json['source']?.toString() ?? valides.source,
      navigation: ArcepSeuilsNavigation(
        pageLoadS: _d(nav['pageLoadSeuilS'], valides.navigation.pageLoadS),
        pageLoadPct: valides.navigation.pageLoadPct,
        connectionS: _d(nav['connectionSeuil'], valides.navigation.connectionS),
        transferPct: valides.navigation.transferPct,
      ),
      streaming: ArcepSeuilsStreaming(
        preloadS: _d(stream['preloadSeuilS'], valides.streaming.preloadS),
        qualityPct:
            _d(stream['qualityPctReference'], valides.streaming.qualityPct),
        rebufferRatioMax: _d(
            stream['rebufferRatioMax'], valides.streaming.rebufferRatioMax),
        resolutionMinHeight: _height(stream['resolutionMin']) ??
            valides.streaming.resolutionMinHeight,
        interruptionsMax: _i(stream['interruptionsMax'],
            valides.streaming.interruptionsMax),
      ),
    );
  }
}

/// Lit un nombre JSON, en gardant [fallback] s'il est absent ou illisible.
double _d(Object? value, double fallback) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}

/// Lit un entier JSON, en gardant [fallback] s'il est absent ou illisible.
int _i(Object? value, int fallback) {
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

/// Convertit « 480p » / « 1080p » en hauteur en pixels ; null si illisible.
int? _height(Object? value) {
  if (value is num) return value.toInt();
  if (value is! String) return null;
  final match = RegExp(r'(\d+)').firstMatch(value);
  return match == null ? null : int.tryParse(match.group(1)!);
}
