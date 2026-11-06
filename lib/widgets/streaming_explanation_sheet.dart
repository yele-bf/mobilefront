import 'package:flutter/material.dart';

import '../models/speed_test_result.dart';
import '../theme/yele_theme.dart';

/// IMP-06 / ISS-07 / IMP-12 — panneau « Streaming vidéo : comment c'est
/// calculé », ouvert par le bouton ⓘ de la carte Streaming vidéo de l'écran de
/// résultat. Vulgarise la mesure par paliers (ISS-07 : le test mesure, il ne
/// se contente plus d'afficher) et la note 0-100 ancrée sur les seuils ARCEP
/// (IMP-06 : démarrage ≤ 5 s, rebuffering ≤ 10 %, résolution ≥ 480p, aucune
/// interruption). Voir aussi `docs/fiches/IMP-06-seuils-arcep-scoring.md`.
Future<void> showStreamingExplanationSheet(
    BuildContext context, SpeedTestResult r) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    isScrollControlled: true,
    builder: (_) => _StreamingExplanation(r: r),
  );
}

class _StreamingExplanation extends StatelessWidget {
  final SpeedTestResult r;
  const _StreamingExplanation({required this.r});

  Widget bloc(String titre, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titre,
                style: TextStyle(
                    color: YeleColors.surface.ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            ...children,
          ],
        ),
      );

  Widget p(String texte) => Text(texte,
      style: TextStyle(
          color: YeleColors.surface.muted, fontSize: 12.5, height: 1.35));

  @override
  Widget build(BuildContext context) {
    final paliers = r.streamingQualities.length;
    final servie = r.streamingMaxResolution ?? '—';
    final demarrage = r.streamingStartupMs;
    final interruptions = r.streamingRebufferCount;
    final score100 = r.streamingScore?.toStringAsFixed(0);
    final ptsStream = r.scoreStreaming?.toStringAsFixed(0);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.72,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.play_circle_outline,
                        color: YeleColors.primary, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text("Streaming vidéo — comment c'est calculé",
                          style: TextStyle(
                              color: YeleColors.surface.ink,
                              fontSize: 16,
                              fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // 1 — la mesure par paliers (ISS-07).
                bloc("La mesure", [
                  p("L'app lit une vraie vidéo YouTube et mesure "
                      "$paliers résolutions l'une après l'autre — 720p, "
                      "1080p, 1440p et 2160p. Chaque résolution a sa "
                      "colonne dans le tableau ; pour chacune : le "
                      "démarrage, le temps de mise en tampon, les données "
                      "consommées, les interruptions et les données "
                      "réellement servies par YouTube. Si YouTube a servi "
                      "une autre qualité que celle demandée pour un palier, "
                      "le tableau le signale par un astérisque. Un palier "
                      "impossible à lire reste vide sans pénaliser les "
                      "autres paliers."),
                ]),

                // 2 — la note ancrée ARCEP (IMP-06).
                bloc("Comment ça marche", [
                  p("La note affichée (0-100) part de la fluidité des paliers "
                      "mesurés, puis les quatre critères ARCEP la réduisent : "
                      "démarrage au-delà de 5 s, mise en tampon au-delà de "
                      "10 % du temps de lecture, une interruption ou plus "
                      "(−15 % chacune), résolution réellement servie sous "
                      "480p (note divisée par 2)."),
                  const SizedBox(height: 6),
                  p("Score YÉLÉ (points) : la note 0-100 est convertie en "
                      "points pour l'échelle ouverte — la composante Streaming "
                      "vaut 17 500 pts × (note / 100), une note de 100 "
                      "correspond donc à 17 500 pts."),
                ]),

                // 3 — le résultat de CE test.
                bloc("Votre mesure", [
                  Text("Paliers testés : $paliers",
                      style: TextStyle(
                          color: YeleColors.surface.ink, fontSize: 13)),
                  Text("Résolution maximale servie : $servie",
                      style: TextStyle(
                          color: YeleColors.surface.ink, fontSize: 13)),
                  if (demarrage != null)
                    Text("Démarrage : ${(demarrage / 1000).toStringAsFixed(1)} s",
                        style: TextStyle(
                            color: YeleColors.surface.ink, fontSize: 13)),
                  if (interruptions != null)
                    Text("Interruptions : $interruptions",
                        style: TextStyle(
                            color: YeleColors.surface.ink, fontSize: 13)),
                  if (score100 != null)
                    Text("Note : $score100 / 100",
                        style: TextStyle(
                            color: YeleColors.surface.ink, fontSize: 13)),
                  if (ptsStream != null)
                    Text(
                        "Composante Streaming du Score YÉLÉ : $ptsStream pts",
                        style: TextStyle(
                            color: YeleColors.surface.ink, fontSize: 13)),
                ]),

                // 4 — honnêteté + mécanique YouTube.
                bloc("À savoir", [
                  p("Le palier demandé n'est qu'une cible : YouTube ajuste "
                      "lui-même la qualité selon le réseau et la taille du "
                      "lecteur. Demander 2160p et être servi en 1080p est une "
                      "donnée de mesure, pas un bug — l'astérisque du tableau "
                      "le signale, et la note suit la qualité réellement "
                      "servie."),
                  const SizedBox(height: 6),
                  p("La comparaison aux seuils ARCEP reste simplifiée : aucun "
                      "écran de YELE ne conclut « conforme » à partir de ce "
                      "score."),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
