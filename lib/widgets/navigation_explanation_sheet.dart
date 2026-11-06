import 'package:flutter/material.dart';

import '../models/speed_test_result.dart';
import '../theme/yele_theme.dart';

/// IMP-06 / IMP-12 — panneau « Navigation web : comment c'est calculé », ouvert
/// par le bouton ⓘ de la carte Navigation web de l'écran de résultat. Vulgarise
/// le référentiel ARCEP du scénario (6 pages, seuil de chargement 30 s) et les
/// deux lectures du même test : la note 0-100 affichée et le score ouvert en
/// points YÉLÉ. Documents qui font autorité : le référentiel ARCEP embarqué
/// (`lib/constants/arcep_seuils.dart`, seuils.json v3) et sa fiche de synthèse
/// `docs/fiches/IMP-06-seuils-arcep-scoring.md` ; en cas de divergence, ce
/// dernier gagne.
Future<void> showNavigationExplanationSheet(
    BuildContext context, SpeedTestResult r) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    isScrollControlled: true,
    builder: (_) => _NavigationExplanation(r: r),
  );
}

class _NavigationExplanation extends StatelessWidget {
  final SpeedTestResult r;
  const _NavigationExplanation({required this.r});

  static const scenario = [
    'www.google.com',
    'www.wikipedia.org',
    'www.facebook.com',
    'lefaso.net',
    'www.youtube.com',
    'www.bing.com',
  ];

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
    final pages = r.browsingPagesTested ?? 6;
    final reussite = ((r.browsingSuccessRate ?? 0) * 100).toStringAsFixed(0);
    final moyen = ((r.browsingAvgLoadMs ?? 0) / 1000).toStringAsFixed(1);
    final score100 = r.browsingScore?.toStringAsFixed(0);
    final ptsNav = r.scoreBrowsing?.toStringAsFixed(0);

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
                    const Icon(Icons.public,
                        color: YeleColors.primary, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text("Navigation web — comment c'est calculé",
                          style: TextStyle(
                              color: YeleColors.surface.ink,
                              fontSize: 16,
                              fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // 1 — le scénario ARCEP chargé pendant le test.
                bloc("Le scénario", [
                  Text("$pages pages du scénario de référence ARCEP, chargées "
                          "une à une pendant le test : ${scenario.join(' · ')}.",
                      style: TextStyle(
                          color: YeleColors.surface.muted,
                          fontSize: 12.5,
                          height: 1.35)),
                ]),

                // 2 — deux lectures du même test.
                bloc("Comment ça marche", [
                  p("Note affichée sur la carte (0-100) : une page est réussie "
                      "si elle charge en moins de 30 s (seuil ARCEP). La note est "
                      "la part de pages réussies, moins une pénalité de confort "
                      "de 20 points au plus quand le temps moyen approche le "
                      "seuil : une page à 29 s ne vaut pas une page à 1 s."),
                  const SizedBox(height: 6),
                  p("Score YÉLÉ (points) : chaque page vaut "
                      "100 × (1 − temps / 10 s) ; la moyenne des pages mesurées "
                      "est multipliée par 17 500. Une page manquante ou en échec "
                      "technique est exclue de la moyenne, jamais comptée à "
                      "zéro."),
                ]),

                // 3 — le résultat de CE test, valeurs réelles.
                bloc("Votre mesure", [
                  Text("Pages testées : $pages",
                      style: TextStyle(
                          color: YeleColors.surface.ink, fontSize: 13)),
                  Text("Réussite : $reussite %",
                      style: TextStyle(
                          color: YeleColors.surface.ink, fontSize: 13)),
                  Text("Temps de chargement moyen : $moyen s",
                      style: TextStyle(
                          color: YeleColors.surface.ink, fontSize: 13)),
                  if (score100 != null)
                    Text("Note : $score100 / 100",
                        style: TextStyle(
                            color: YeleColors.surface.ink, fontSize: 13)),
                  if (ptsNav != null)
                    Text(
                        "Composante Navigation du Score YÉLÉ : $ptsNav pts",
                        style: TextStyle(
                            color: YeleColors.surface.ink, fontSize: 13)),
                ]),

                // 4 — avertissement d'honnêteté (règle du référentiel ARCEP).
                bloc("À savoir", [
                  p("La comparaison aux seuils ARCEP reste simplifiée : elle "
                      "reprend quelques seuils de référence, pas une campagne "
                      "complète. Aucun écran de YELE ne conclut « conforme » à "
                      "partir de ce score."),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
