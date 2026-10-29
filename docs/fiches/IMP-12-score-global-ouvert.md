# IMP-12 — Application du référentiel de score YELE (résultat et historique)

| Champ | Valeur |
|---|---|
| Dépôt | `mobilefront` — l'item du classeur couvre aussi `mobiletest` et `New_web` |
| Issue | [#16](https://github.com/yele-bf/mobilefront/issues/16) |
| Priorité / vague | P2 / V4 Métriques & score |
| Owner au classeur | TRAORE Abdoulaye / KIEMA François |
| Branche | `imp/IMP-12-score-global-ouvert` |
| Validation imposée | Local (3 vues cohérentes) |

> **Définition de l'échelle : IMP-05.** Cette fiche ne définit pas l'échelle, elle
> constate son application. La norme est
> [`docs/echelle-score.md`](../echelle-score.md) (item IMP-05), qui fait autorité
> pour les quatre dépôts. Toute divergence entre un écran et ce document est un
> défaut de cette fiche, pas du document.

## Constat et impact

Chaque écran produisait un chiffre différent pour le même test :

- l'historique calculait une note /100 **propre à l'écran** (`_score` dans
  `history_screen.dart` : 60 pts pour le débit descendant, 20 pour le montant,
  20 pour la latence) — un test sans navigation ni streaming était donc noté sur
  la même échelle qu'un test complet ;
- l'écran de résultat n'affichait **aucun score global** : seulement deux notes
  par composante, `streamingScore` et `browsingScore`, sur 100 chacune, qui ne se
  combinent pas en un total ;
- le backend ne portait aucun score global.

Conséquence : deux tests aux mesures identiques pouvaient afficher deux notes
différentes selon l'écran consulté, et aucune note ne couvrait les cinq
dimensions mesurées par l'application. C'est l'écart qu'IMP-12 devait fermer :
**un seul score, la même valeur partout**.

## Correction

### 1. Le moteur et le stockage (déjà présents dans cette branche)

Le score est produit par un moteur pur, sans dépendance Flutter
(`lib/services/yele_scoring_engine.dart`, version `yele-open-1.0.0`), puis stocké
avec le résultat et affiché depuis cette valeur unique — jamais recalculé par un
écran :

- `lib/models/speed_test_result.dart` : champs Hive **44 à 51** (les index 34 à
  41 étaient déjà pris par IMP-01, ISS-02 et ISS-01 — aucun index existant n'est
  renuméroté) et getters `scoreGlobalOn100`, `scoreMeasuredSubtotal`,
  `scoreMeasuredOn100`, `scoringStatuses` ;
- `lib/services/speed_test_api_service.dart` : `_applyOpenScore` renseigne les
  champs à la construction du résultat ;
- `test/yele_scoring_engine_test.dart` : 53 cas (bornes de débit, latence à
  250 ms, pages manquantes, incohérences de streaming, complétude).

Les formules, allocations et règles sont celles de
[`docs/echelle-score.md`](../echelle-score.md) §3 à §6 : elles ne sont pas
reproduites ici pour qu'il n'existe qu'une seule définition.

### 2. L'écran de résultat (ajouté par ce commit)

`lib/screens/score_screen.dart` portait deux notes `/100` et aucun total. Une
carte **« Score YELE »** est désormais affichée dès qu'un résultat porte une
version de scoring :

- valeur principale : le score global **en points**, avec sa classification ;
- composantes en points (débit ↓, débit ↑, latence, navigation, streaming) ;
- ligne « Référentiel » : la version `yele-open-1.0.0` réellement utilisée ;
- résultat incomplet : « incomplet » plus le sous-total des composantes
  mesurées, avec la mention « composantes absentes exclues » ;
- résultat antérieur au scoring : **aucune carte**, et aucune version
  rétro-attribuée.

Le formateur est celui de l'historique (`toStringAsFixed(0)` + suffixe `pts`),
pour que les deux vues affichent littéralement la même chaîne.

### 3. L'historique (aligné dans cette branche)

`lib/screens/history_screen.dart` : la colonne « Score » affiche le score ouvert
en points (`—` si aucune composante, `*` si sous-total) ; le dépli ajoute le
score global, sa classification et les composantes en points, avec l'indice
`/100` explicitement étiqueté « lecture ».

### Ce qui a été retiré de cette fiche

La section « Arbitrage avec le classeur » — qui discutait du libellé « 0-100 »
et du choix de l'échelle ouverte — a été **transférée dans IMP-05**. C'est une
décision de définition, pas d'application : elle appartient au document qui fait
autorité, et non à la fiche de la PR qui l'applique.

## Critère d'acceptation

*« Le score global est calculé et identique sur l'app, le dashboard et
l'historique. »* — Pour un même résultat, **le score en points est identique
dans l'écran de résultat et dans l'historique**, et il est dérivé du seul score
global stocké.

| Situation | Attendu, dans les deux vues |
|---|---|
| Cinq composantes complètes | score global en points, sans marque, avec sa classification |
| Test incomplet (sans navigation ni streaming) | score global `null` ; sous-total mesuré en points suivi de `*`, composantes absentes exclues |
| Aucune composante mesurée | `—` (historique) / carte « incomplet » (résultat) |
| Résultat antérieur au scoring | ancienne note d'écran, aucune version attribuée, pas de carte sur le résultat |

## Validation

- **Automatisée** : `flutter analyze` — **aucun avertissement** ; `flutter test`
  — **141 tests verts** (88 sur `main` avant la branche, donc **+53**), dont les
  53 cas de `test/yele_scoring_engine_test.dart`.
- **Support imposé par le classeur** : local (3 vues cohérentes) — **partiel** :
  seules les deux vues de `mobilefront` sont couvertes, le dashboard `New_web`
  n'étant pas branché.
- **Non réalisé** : aucun test sur APK ni dans Chrome pour ce commit. La carte
  de score n'a pas été vue sur appareil réel.
- **Preuve** : sortie de `flutter test` (141 tests, 0 échec) et `flutter analyze`
  (« No issues found! »), à joindre à la PR.

## Limites connues

- **Deux vues sur trois.** Le dashboard `New_web` n'affiche pas encore le score,
  et `mobiletest` n'expose pas les champs calculés (ils sont envoyés dans
  `extra` et ignorés par un backend plus ancien). Le critère du classeur reste
  donc **partiellement** satisfait.
- **Dépendance à IMP-05.** Cette PR applique
  [`docs/echelle-score.md`](../echelle-score.md) : elle doit être mergée **après**
  IMP-05, sinon le lien de référence pointe vers un fichier absent de `main`.
- **La navigation n'est pas pénalisée par ses pages en échec** : les temps par
  page ne sont pas persistés, seule la moyenne l'est, et les pages au-delà de
  30 s sortent de la moyenne. Persister les temps par page reste à faire.
- **Les anciens résultats ne sont pas rescopés** : sans version de scoring, ils
  conservent l'ancienne note d'écran.
- **Les seuils de classification** (30 000 / 70 000 / 110 000 / 160 000 pts)
  restent provisoires, non calibrés sur un échantillon représentatif.
- **Aucun test de widget** ne couvre la nouvelle carte « Score YELE » : elle est
  vérifiée par l'analyse statique et par la cohérence du formateur avec
  l'historique, pas par un rendu testé.

---

## Liste de contrôle avant d'ouvrir la PR

- [x] La fiche est dans `docs/fiches/` avec le nom `IMP-12-score-global-ouvert.md`.
- [x] Les champs du tableau viennent de `docs/items-v14.json`.
- [x] Une ligne **datée** a été ajoutée au tableau d'historique de
      `docs/registre-revisions.md` (sans elle, `guard` est rouge).
- [x] Le `CHANGELOG.md` du dépôt a une entrée sous `## [Non publiée]`.
- [x] Le corps de la PR porte `Closes #16` et la même liste de validation.
