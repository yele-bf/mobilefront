import 'package:flutter/material.dart';

import '../models/speed_test_result.dart';
import '../theme/yele_theme.dart';

/// IMP-05 / IMP-12 — panneau « Comment le score est calculé », ouvert par le
/// bouton ⓘ de la carte Score YELE. Le contenu s'adapte au test en cours :
/// seules les composantes réellement mesurées (valeur != null) sont expliquées,
/// la section « Score global » est toujours présente. Les textes vulgarisent le
/// document qui fait autorité : `docs/echelle-score.md` (référentiel
/// `yele-open-1.0.0`) ; en cas de divergence, ce dernier gagne.
Future<void> showScoreExplanationSheet(
    BuildContext context, SpeedTestResult r) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    isScrollControlled: true,
    builder: (_) => _ScoreExplanation(r: r),
  );
}

class _ScoreExplanation extends StatelessWidget {
  final SpeedTestResult r;
  const _ScoreExplanation({required this.r});

  ({String title, String text})? _section(String key) => switch (key) {
        'download' => r.scoreDownload == null
            ? null
            : (
                title: "Download",
                text: "Points = 17 500 × log10(1 + débit Mb/s). Le débit est "
                    "récompensé de façon logarithmique : chaque multiplication "
                    "par 10 de la vitesse ajoute environ 17 500 pts "
                    "(9 Mb/s ≈ 17 500 ; 50 Mb/s ≈ 29 900). Échelle ouverte, "
                    "jamais plafonnée."
              ),
        'upload' => r.scoreUpload == null
            ? null
            : (
                title: "Upload",
                text: "Même progression logarithme que le descendant, avec une "
                    "pondération plus faible (7 500 pts à 9 Mb/s) : l'envoi "
                    "pèse deux fois moins que la réception. Échelle ouverte, "
                    "jamais plafonnée."
              ),
        'latence' => r.scorePingJitter == null
            ? null
            : (
                title: "Latence",
                text: "Latence effective = ping + 2 × gigue (ms) ; "
                    "15 000 × (1 − L / 250)². Décroissance quadratique : "
                    "0 ms ≈ 15 000 pts, 100 ms ≈ 5 400 pts, 250 ms et plus = 0. "
                    "La gigue compte double — l'instabilité coûte autant que "
                    "la lenteur."
              ),
        'browsing' => r.scoreBrowsing == null
            ? null
            : (
                title: "Navigation",
                text: "Chaque page reçoit une note max(0, 100 × (1 − temps/10 s)) "
                    "; la composante est la moyenne des pages mesurées × 17 500. "
                    "Une page en échec est exclue, jamais comptée à zéro. Seuils "
                    "de référence ARCEP appliqués au scénario (IMP-06)."
              ),
        'streaming' => r.scoreStreaming == null
            ? null
            : (
                title: "Streaming",
                text: "Note = 100 × (1 − temps de tampon / durée totale) "
                    "− 15 points par interruption de lecture, × 17 500. La "
                    "première interruption coûte 2 625 pts. La qualité réellement "
                    "servie dépend de la plateforme : elle ajuste elle-même le "
                    "palier selon le réseau (720p/1080p/2160p)."
              ),
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    const sections = ['download', 'upload', 'latence', 'browsing', 'streaming'];
    final shown = sections
        .map(_section)
        .whereType<({String title, String text})>()
        .toList();
    final mesures = shown.map((s) => s.title).join(' · ');

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
                    const Icon(Icons.info_outline,
                        color: YeleColors.primary, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text("Comment le score est calculé",
                          style: TextStyle(
                              color: YeleColors.surface.ink,
                              fontSize: 16,
                              fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text("Référentiel : ${r.scoringVersion ?? 'yele-open-1.0.0'}",
                    style: TextStyle(
                        color: YeleColors.surface.muted, fontSize: 12)),
                const SizedBox(height: 12),

                // Principe général, adapté au type de test en cours.
                Text(
                  "Le score YELE s'exprime en points sur une échelle ouverte : "
                  "il n'y a pas de maximum. Dans un test partiel, seules les "
                  "composantes concernées entrent dans le score."
                  "${mesures.isEmpty ? '' : ' Ce test a mesuré : $mesures.'}",
                  style: TextStyle(
                      color: YeleColors.surface.ink,
                      fontSize: 13,
                      height: 1.35),
                ),
                const SizedBox(height: 10),

                // Une explication par indicateur réellement mesuré.
                for (final s in shown)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.title,
                            style: TextStyle(
                                color: YeleColors.surface.ink,
                                fontSize: 14,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(s.text,
                            style: TextStyle(
                                color: YeleColors.surface.muted,
                                fontSize: 12.5,
                                height: 1.35)),
                      ],
                    ),
                  ),

                // Score global — toujours présent, texte selon l'état.
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Score global",
                        style: TextStyle(
                            color: YeleColors.surface.ink,
                            fontSize: 14,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      r.scoreGlobal != null
                          ? "Somme des composantes mesurées. L'allocation "
                              "nominale totale est 75 000 pts (17 500 + 7 500 + "
                              "15 000 + 17 500 + 17 500) : c'est un repère de "
                              "lecture, pas un maximum — un très bon réseau le "
                              "dépasse normalement, car les deux débits ne sont "
                              "pas plafonnés. Le niveau (Faible → Excellent) se "
                              "lit sur l'indice 0-100 affiché sous le score."
                          : "Test incomplet : l'écran affiche le sous-total des "
                              "composantes réellement mesurées. Une absence "
                              "n'est jamais un zéro — les composantes non "
                              "mesurées sont exclues, jamais comptées à zéro.",
                      style: TextStyle(
                          color: YeleColors.surface.muted,
                          fontSize: 12.5,
                          height: 1.35),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
