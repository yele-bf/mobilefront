// ─── Scoring ancré sur les seuils ARCEP — IMP-06 ──────────────────────────
//
// Deux scores sont affichés sur 100 ; ils sont désormais calculés à partir du
// référentiel validé (`lib/constants/arcep_seuils.dart`, seuils.json v3) et non
// plus de constantes choisies au hasard :
//
//  • navigation — une page est « réussie » sous le seuil ARCEP de chargement
//    (30 s). Le score est la part de pages réussies, moins une pénalité de
//    confort qui atteint 20 points quand le temps moyen atteint le seuil.
//  • streaming — la base reste la moyenne des taux de performance des paliers
//    réellement servis (règle nPerf : un palier non servi ne tire pas la
//    moyenne vers 0). Cette base est ensuite réduite par les quatre critères
//    ARCEP/Yélé : démarrage ≤ 5 s, rebuffering ≤ 10 %, résolution ≥ 480p,
//    aucune interruption.
//
// Règle d'honnêteté (cf. `method_note` du référentiel) : la comparaison reste
// simplifiée. Aucun écran ne doit conclure « conforme » à partir de ces scores.
// Fiche : `docs/fiches/IMP-06-seuils-arcep-scoring.md`.

import '../constants/arcep_seuils.dart';

/// Calculs ancrés sur le référentiel ARCEP (seuils.json v3).
abstract final class ArcepScoring {
  /// Référentiel utilisé. Remplaçable par la réponse `/api/arcep/measure`
  /// (`ArcepSeuils.fromApiJson`) ; les valeurs validées servent de repli.
  static ArcepSeuils seuils = ArcepSeuils.valides;

  // ── Prédicats de seuil ───────────────────────────────────────────────────

  /// Vrai si la page respecte le seuil ARCEP de chargement (< 30 s).
  static bool pageDansSeuil(double pageLoadMs) =>
      pageLoadMs < seuils.navigation.pageLoadS * 1000;

  /// Vrai si la connexion respecte le seuil ARCEP (< 20 s).
  static bool connexionDansSeuil(double connectionMs) =>
      connectionMs < seuils.navigation.connectionS * 1000;

  /// Vrai si le démarrage vidéo respecte le seuil ARCEP (< 5 s).
  static bool preloadDansSeuil(double startupMs) =>
      startupMs < seuils.streaming.preloadS * 1000;

  /// Vrai si la session vidéo est de bonne qualité au sens Yélé :
  /// rebuffering ≤ 10 %, résolution servie ≥ 480p, aucune interruption.
  static bool sessionBonneQualite({
    required double rebufferRatio,
    required int hauteurServie,
    required int interruptions,
  }) =>
      rebufferRatio <= seuils.streaming.rebufferRatioMax &&
      hauteurServie >= seuils.streaming.resolutionMinHeight &&
      interruptions <= seuils.streaming.interruptionsMax;

  // ── Scores composites 0-100 ──────────────────────────────────────────────

  /// Score de navigation web, 0-100.
  ///
  /// [pagesDansSeuil] compte les pages chargées sous le seuil ARCEP (30 s) :
  /// une page au-delà est un échec, quelle que soit sa vitesse relative. La
  /// part de pages réussies donne le score, d'où l'on retire au plus 20 points
  /// de confort quand le temps moyen atteint le seuil — sans quoi une page à
  /// 29 s vaudrait autant qu'une page à 1 s.
  static double scoreNavigation({
    required int pagesTestees,
    required int pagesDansSeuil,
    required double pageLoadMoyenMs,
  }) {
    if (pagesTestees <= 0) return 0;
    final seuilMs = seuils.navigation.pageLoadS * 1000;
    final taux = (pagesDansSeuil / pagesTestees).clamp(0.0, 1.0);
    final lenteur =
        seuilMs <= 0 ? 1.0 : (pageLoadMoyenMs / seuilMs).clamp(0.0, 1.0);
    return (100 * taux - 20 * lenteur).clamp(0, 100);
  }

  /// Score de streaming vidéo, 0-100.
  ///
  /// [fluidite] est la moyenne des taux de performance des paliers réellement
  /// servis (0-100) : les paliers non servis n'entrent pas dans la moyenne, un
  /// réseau qui ne tient pas le 4K ne doit pas écraser la mesure des paliers
  /// servis. Les quatre critères ARCEP/Yélé réduisent ensuite cette base :
  ///
  ///  - démarrage au-delà de 5 s : jusqu'à la moitié du score en moins quand il
  ///    atteint le double du seuil ;
  ///  - rebuffering au-delà de 10 % : même décroissance ;
  ///  - une interruption ou plus : 15 % de la note en moins (définition Yélé :
  ///    aucune interruption) ;
  ///  - résolution sous 480p : moitié de la note.
  static double scoreStreaming({
    required double fluidite,
    required double startupMs,
    required double rebufferRatio,
    required int interruptions,
    required int hauteurServie,
  }) {
    if (fluidite <= 0) return 0;

    final facteurDemarrage = _facteurAuDela(
      startupMs,
      seuils.streaming.preloadS * 1000,
    );
    final facteurRebuffer = _facteurAuDela(
      rebufferRatio,
      seuils.streaming.rebufferRatioMax,
    );
    final facteurInterruptions =
        interruptions <= seuils.streaming.interruptionsMax ? 1.0 : 0.85;
    final facteurResolution =
        hauteurServie >= seuils.streaming.resolutionMinHeight ? 1.0 : 0.5;

    return (fluidite *
            facteurDemarrage *
            facteurRebuffer *
            facteurInterruptions *
            facteurResolution)
        .clamp(0, 100);
  }

  /// Vaut 1 tant que [mesure] reste sous [seuil], puis décroît linéairement
  /// jusqu'à 0,5 quand elle atteint le double du seuil. Le seuil est la seule
  /// constante : aucune durée « magique » n'est codée en dur.
  static double _facteurAuDela(double mesure, double seuil) {
    if (seuil <= 0 || mesure <= seuil) return 1;
    final depassement = ((mesure - seuil) / seuil).clamp(0.0, 1.0);
    return 1 - 0.5 * depassement;
  }
}
