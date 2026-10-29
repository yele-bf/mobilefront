# IMP-05 — Échelle de score YELE : définition de référence unique

| Champ | Valeur |
|---|---|
| Dépôt | `mobilefront` |
| Issue | [#11](https://github.com/yele-bf/mobilefront/issues/11) |
| Priorité / vague | P2 / V5 Dashboard & référentiel |
| Owner au classeur | TRAORE Abdoulaye / KIEMA François |
| Branche | `imp/IMP-05-echelle-score` |
| Validation imposée | Local (3 vues) |

## Constat et impact

Deux échelles de score coexistaient dans la même application, pour les mêmes
mesures :

| Écran | Affichage relevé | Échelle |
|---|---|---|
| Écran de résultat (`lib/screens/score_screen.dart`) | « Streaming vidéo 78/100 », « Navigation web 85/100 », via `_resultCard` | note bornée 0-100 |
| Historique (`lib/screens/history_screen.dart`) | score global | points, échelle ouverte |

Aucun score global n'était affiché sur l'écran de résultat. L'utilisateur voyait
donc, après un test, deux notes sur 100 sans rapport apparent avec le score en
points qui apparaissait ensuite dans son historique — la comparaison et
l'interprétation étaient impossibles.

Le second point est documentaire : la méthode de calcul n'était décrite nulle
part. Elle existait uniquement dans le code de
`lib/services/yele_scoring_engine.dart` et dans la fiche
[`docs/fiches/IMP-06-seuils-arcep-scoring.md`](IMP-06-seuils-arcep-scoring.md),
qui note elle-même en « Limites connues » : *« IMP-05 (échelle de score) et
IMP-12 (score global) touchent les mêmes fonctions : la définition finale doit
être coordonnée avant merge. »*

## Correction

Le référentiel est désormais **écrit et publié** dans
[`docs/echelle-score.md`](../echelle-score.md), qui fait autorité pour les quatre
dépôts. Il fixe :

- **l'unité** : le point YELE, échelle ouverte non plafonnée, total de
  référence **75 000 points** (somme des cinq allocations : 17 500 + 7 500 +
  15 000 + 17 500 + 17 500) — repère de lecture, pas maximum ;
- **les cinq composantes** et leurs formules exactes, avec les valeurs de
  référence chiffrées : descendant `17 500 × log10(1 + D)` (logarithmique, non
  plafonné), montant `7 500 × log10(1 + U)`, latence effective
  `L = ping + 2 × gigue` puis `15 000 × (1 − L/250)²` (quadratique),
  navigation `17 500 × moyenne(QoE_page)/100` avec
  `QoE_page = max(0, 100 × (1 − T/10))`, streaming
  `17 500 × max(0, 100 × (1 − T_buf/T_total) − 15 × N_stalls)/100` ;
- **la règle « une absence n'est jamais un zéro »** : mesure manquante ou
  incohérente → `null` avec statut, jamais `0` ;
- **la condition d'existence du score global** : les cinq composantes
  `completed`, sinon `null` et un statut qui nomme la cause ;
- **l'arrondi** : calcul en `double`, arrondi à l'entier seulement à
  l'affichage, jamais avant une somme ;
- **la classification indicative** (seuils provisoires, centralisés) ;
- **ce que chaque écran doit afficher** : format unique `NN NNN pts`, même
  valeur partout, jamais de score global en `/100` ni en `%` ;
- **l'encadrement des notes sur 100** : les notes de qualité ARCEP restent
  internes et, si elles sont affichées, sont étiquetées « note de qualité »
  et accompagnées de leur équivalent en points ;
- **le versionnage** : `yele-open-1.0.0`, enregistré avec chaque résultat.

Choix non évidents :

- **On ne choisit pas entre les deux échelles, on hiérarchise.** La note sur 100
  n'est pas supprimée : elle reste la note de qualité d'une composante, telle
  qu'elle vient du cadre ARCEP déjà documenté par IMP-06. Ce qui change, c'est
  qu'elle n'est plus jamais présentée comme le score du test.
- **On ne recopie pas la formule de nPerf, parce qu'elle n'est pas publique.**
  nPerf publie sa *méthode* — cinq composantes, score composite en nPoints,
  progression logarithmique, échelle ouverte — mais pas ses coefficients. Le
  document revendique donc « même méthode que nPerf », et assume explicitement
  que les allocations sont les nôtres. Revendiquer « même formule » aurait été
  faux.
- **Le repère de 75 000 points est conservé tel quel**, alors qu'il est
  dépassable : les composantes de débit ne sont pas plafonnées, donc le
  dépassement est normal. C'est écrit dans le document pour éviter qu'il soit
  pris pour un bug.
- **Aucun calcul n'est modifié par cette PR.** Elle ne touche que la
  documentation : les valeurs du code sont décrites, pas changées. La
  conformité des écrans est l'objet d'IMP-12.

Fichiers touchés :

- `docs/echelle-score.md` : le référentiel (nouveau) ;
- `docs/fiches/IMP-05-echelle-score.md` : cette fiche ;
- `CHANGELOG.md` : entrée sous `## [Non publiée]` ;
- `docs/registre-revisions.md` : ligne datée de suivi.

## Critère d'acceptation

*« L'échelle est clairement définie, documentée et identique dans tous les
écrans concernés. »* — Vérifiable comme suit : le document publié énonce une
définition unique, les cinq formules, l'unité et le format d'affichage, et la
table des valeurs de référence est reproductible ; tout écran dont l'affichage
s'en écarte est identifié comme non conforme. La conformité des écrans
`mobilefront` est constatée par IMP-12.

## Validation

- **Automatisée** : `guard` (format du commit, Sous-ID connu, ligne `Agent:`,
  ligne de registre) — exécuté en local avant le push, et par la CI sur la PR.
  `build` et `android` n'ont rien de nouveau à compiler : **cette PR ne touche
  que des fichiers Markdown**, aucun fichier Dart ni Kotlin.
- **Support imposé par le classeur** : Local (3 vues).
- **Preuve** : les tables de valeurs de `docs/echelle-score.md` §3 et §10, dont
  chaque ligne se recalcule à la main (par exemple l'exemple complet :
  29 882 + 9 917 + 12 696 + 12 250 + 15 750 = **80 495 pts**).

## Limites connues

- **La validation « 3 vues » n'est pas atteinte : 2 vues sur 3.** Cette PR
  définit l'échelle et couvre, avec IMP-12, l'application et l'historique. Le
  **dashboard `New_web` n'est pas branché** : il ne consomme aujourd'hui ni le
  score global ni ses composantes. La documentation lui est opposable, mais rien
  ne démontre encore qu'il s'y conforme.
- **Le score global n'est pas encore affiché sur l'écran de résultat** : c'est
  l'objet d'IMP-12. Tant qu'IMP-12 n'est pas mergée, l'écran de résultat reste
  non conforme à ce document (deux notes sur 100, aucun total).
- **Les seuils de classification (30 000 / 70 000 / 110 000 / 160 000 points)
  ne sont pas calibrés** sur un échantillon représentatif de mesures réelles.
  Ils sont documentés comme provisoires et centralisés pour être recalibrés.
- **Aucune comparaison chiffrée avec un score nPerf réel** n'a été faite : la
  méthode est comparée, pas les valeurs, ce qui est cohérent avec l'absence de
  formule publique chez nPerf.
- **Aucun test sur APK ni dans Chrome** : le livrable est documentaire.

---

## Liste de contrôle avant d'ouvrir la PR

- [x] La fiche est dans `docs/fiches/` avec le nom `IMP-05-echelle-score.md`.
- [x] Les champs du tableau viennent de `docs/items-v14.json`.
- [x] Une ligne **datée** a été ajoutée au tableau d'historique de
      `docs/registre-revisions.md` (sans elle, `guard` est rouge).
- [x] Le `CHANGELOG.md` du dépôt a une entrée sous `## [Non publiée]`.
- [x] Le corps de la PR porte `Closes #11` et la même liste de validation.
