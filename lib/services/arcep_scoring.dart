// ─── Squelette du scoring ARCEP — IMP-06 ──────────────────────────────────
//
// Les seuils validés existent (voir `lib/constants/arcep_seuils.dart`) mais
// aucun calcul de score ne les utilise aujourd'hui :
//
//  • navigation — `browsing_test_service_native.dart` compte une page
//    « réussie » sous 10 s et retire 1 point par 100 ms au-delà de 2 s ;
//  • streaming — `aggregateStreamingResults` moyenne les taux de performance
//    par palier, sans confronter le démarrage, le rebuffering, les
//    interruptions ni la résolution minimale aux seuils ARCEP.
//
// Ce fichier pose les deux points d'entrée et les prédicats de seuil. Le
// branchement sur les services et les écrans reste à faire : les scores
// ci-dessous lèvent tant qu'ils ne sont pas implémentés, pour qu'aucun écran
// n'affiche un score faussement conforme.

import '../constants/arcep_seuils.dart';

/// Calculs ancrés sur le référentiel ARCEP (seuils.json v3).
abstract final class ArcepScoring {
  /// Référentiel utilisé. Remplaçable par la réponse `/api/arcep/measure`
  /// (`ArcepSeuils.fromApiJson`) ; les valeurs validées servent de repli.
  static ArcepSeuils seuils = ArcepSeuils.valides;

  // ── Prédicats de seuil (le référentiel, pas encore le score) ─────────────

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

  // ── Scores composites 0-100 (à implémenter) ──────────────────────────────

  /// Score de navigation web, 0-100.
  ///
  /// Attendu : part des pages sous le seuil ARCEP ([pageDansSeuil]) pondérée
  /// par le temps moyen, pour que chaque palier de performance corresponde à
  /// un seuil validé.
  ///
  /// TODO(IMP-06) : implémenter, puis remplacer `_computeScore` de
  /// `browsing_test_service_native.dart` (et son équivalent web).
  static double scoreNavigation({
    required int pagesTestees,
    required int pagesDansSeuil,
    required double pageLoadMoyenMs,
  }) =>
      throw UnimplementedError('IMP-06 : score de navigation ARCEP à définir');

  /// Score de streaming vidéo, 0-100.
  ///
  /// Attendu : démarrage sous 5 s ([preloadDansSeuil]), rebuffering ≤ 10 %,
  /// aucune interruption et résolution ≥ 480p, en conservant la règle
  /// « les paliers non servis ne tirent pas la moyenne vers 0 ».
  ///
  /// TODO(IMP-06) : implémenter, puis brancher dans
  /// `aggregateStreamingResults` (`streaming_shared.dart`).
  static double scoreStreaming({
    required double startupMs,
    required double rebufferRatio,
    required int interruptions,
    required int hauteurServie,
  }) =>
      throw UnimplementedError('IMP-06 : score de streaming ARCEP à définir');
}
