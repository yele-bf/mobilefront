import 'package:flutter/material.dart';

import '../theme/yele_theme.dart';

/// Panneaux « comment lire la carte » de l'écran de résultat, ouverts par le
/// bouton ⓘ — ajout du 18/11 (validation utilisateur) : les cartes Baromètre
/// et Min/Moy/Max n'avaient pas de pastille d'information, contrairement aux
/// cartes d'usage (Streaming/Navigation).
///
/// Style commun : même forme et même vocabulaire que les autres panneaux
/// explicatifs (fond blanc, coins arrondis en haut, blocs titre + texte).

Future<void> showBarometerExplanationSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    isScrollControlled: true,
    builder: (_) => const _BarometerExplanation(),
  );
}

Future<void> showMinMeanMaxExplanationSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    isScrollControlled: true,
    builder: (_) => const _MinMeanMaxExplanation(),
  );
}

Widget _bloc(String titre, List<Widget> children) => Padding(
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

Widget _p(String texte) => Text(texte,
    style: TextStyle(
        color: YeleColors.surface.muted, fontSize: 12.5, height: 1.35));

class _SheetScaffold extends StatelessWidget {
  final String titre;
  final List<Widget> children;

  const _SheetScaffold({required this.titre, required this.children});

  @override
  Widget build(BuildContext context) {
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
                        color: YeleColors.primary, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(titre,
                          style: TextStyle(
                              color: YeleColors.surface.ink,
                              fontSize: 16,
                              fontWeight: FontWeight.w800)),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.close, size: 20),
                      color: YeleColors.surface.muted,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...children,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BarometerExplanation extends StatelessWidget {
  const _BarometerExplanation();

  @override
  Widget build(BuildContext context) {
    final s = _SheetScaffold(
        titre: 'Baromètre : comment lire la carte',
        children: [
          _bloc('Votre position', [
            _p('Chaque ligne situe votre mesure parmi les mesures déjà '
                'collectées par l\'application, à connexion comparable '
                '(Wi-Fi avec le Wi-Fi, mobile avec le mobile).'),
            _p('« Meilleur que 78 % des tests » : votre débit est plus '
                'élevé que 78 % des mesures de l\'échantillon. « 3ᵉ sur 120 » '
                ': vous arrivez 3ᵉ du classement, la médiane indique la '
                'valeur qui partage l\'échantillon en deux.'),
          ]),
          _bloc('Sous-groupes', [
            _p('Opérateur × techno : la même lecture, calculée seulement '
                'parmi les clients du même opérateur et de la même techno '
                '(4G, 5G…). Elle n\'apparaît que si l\'échantillon atteint '
                '10 mesures, pour rester significatif.'),
            _p('Zone (~10 km) : comparaison de proximité, limitée aux '
                'mesures prises autour de votre position. Elle aussi exige '
                'un échantillon suffisant.'),
          ]),
          _bloc('Tendance', [
            _p('« Vos 5 derniers tests » : l\'évolution de votre propre '
                'débit d\'un test à l\'autre, sur le même appareil — hausse, '
                'baisse ou stable.'),
          ]),
          _bloc('Pourquoi des blocs manquent', [
            _p('Un sous-groupe n\'est affiché que si l\'échantillon le '
                'permet : pas assez de mesures de votre opérateur, de votre '
                'techno ou de votre zone, pas de comparaison — c\'est une '
                'garantie de fiabilité, pas un bug.'),
          ]),
        ]);
    return s;
  }
}

class _MinMeanMaxExplanation extends StatelessWidget {
  const _MinMeanMaxExplanation();

  @override
  Widget build(BuildContext context) {
    final s = _SheetScaffold(
        titre: 'Min / Moy / Max : comment lire le tableau',
        children: [
          _bloc('Ce que la mesure contient', [
            _p('Pendant une phase de test (téléchargement, envoi, latence), '
                'l\'application prend plusieurs mesures successives. Le '
                'tableau montre la plus basse (Min), la moyenne (Moy) et la '
                'plus haute (Max) de ces mesures.'),
          ]),
          _bloc('Comment l\'interpréter', [
            _p('Min ≈ Max : la connexion a été stable pendant tout le '
                'test — la valeur principale du test est représentative.'),
            _p('Max bien au-dessus de la moyenne : des pointes de débit '
                '(burst) ; Min bien en dessous : des creux, typiques d\'un '
                'réseau qui sature ou d\'un signal irrégulier.'),
            _p('Pour la latence, Min/Moy/Max montrent les fluctuations : '
                'un Max élevé trahit des pics de latence qui pénalisent les '
                'usages en temps réel (visio, jeux).'),
          ]),
          _bloc('Valeur principale', [
            _p('La grande valeur affichée dans les tuiles (Download, '
                'Upload, Latence) est la moyenne — c\'est elle qui alimente '
                'le score et le baromètre.'),
          ]),
        ]);
    return s;
  }
}
