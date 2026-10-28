# IMP-12 — Score global unique (échelle ouverte `yele-open-1.0.0`)

| Champ | Valeur |
|---|---|
| Dépôt | `mobilefront` — l'item du classeur couvre aussi `mobiletest` et `New_web` |
| Issue | [#16](https://github.com/yele-bf/mobilefront/issues/16) |
| Priorité / vague | P2 / V4 Métriques & score |
| Owner au classeur | TRAORE Abdoulaye / KIEMA François |
| Branche | `imp/IMP-12-score-global-ouvert` |
| Validation imposée | Local (3 vues cohérentes) |

## Constat et impact

Chaque écran affichait un chiffre différent pour le même test :

- l'historique calculait une note /100 **propre à l'écran** (`_score` dans
  `history_screen.dart` : 60 pts pour le débit descendant, 20 pour le montant,
  20 pour la latence) — un test sans navigation ni streaming était donc noté
  sur la même échelle qu'un test complet ;
- l'écran de résultat et le backend ne portaient aucun score global ;
- `streamingScore` et `browsingScore` sont des notes **par composante**, sur 100
  chacune, et ne se combinent pas en un total.

Conséquence : deux tests aux mesures identiques pouvaient afficher deux notes
différentes selon l'écran consulté, et aucune note ne couvrait les cinq
dimensions mesurées par l'application.

## Correction

Le score global est produit par un moteur pur, sans dépendance Flutter
(`lib/services/yele_scoring_engine.dart`, version `yele-open-1.0.0`), stocké
avec le résultat et affiché depuis une valeur unique.

| Composante | Formule | Plafond |
|---|---|---|
| Débit descendant | `17 500 × log10(1 + D)` si `D ≥ 0,1 Mb/s`, sinon 0 | non plafonné |
| Débit montant | `7 500 × log10(1 + U)` si `U ≥ 0,1 Mb/s`, sinon 0 | non plafonné |
| Latence | `15 000 × (1 − L/250)²` avec `L = ping + 2 × gigue`, 0 au-delà de 250 ms | 15 000 |
| Navigation | `17 500 × QoE/100`, `QoE = max(0, 100 × (1 − T/10 s))` moyenné | 17 500 |
| Streaming | `17 500 × QoE/100`, `QoE = max(0, 100 × (1 − T_buf/T_total) − 15 × N_stalls)` | 17 500 |

Le **score global est la somme des cinq composantes**, et n'existe que si les
cinq sont complètes. Sinon il vaut `null` avec un statut explicite
(`partial`, `failed`, `invalid`, `unavailable`) : un total partiel n'est jamais
présenté comme un score.

**Indice 0-100.** Le score ouvert s'exprime en points (somme de référence
75 000, non plafonnée). L'indice affiché est `points / 75 000 × 100`, écrêté à
100 — c'est la seule valeur 0-100 de l'application, et elle est calculée par un
getter unique (`SpeedTestResult.scoreGlobalOn100`), donc identique partout où
elle est affichée.

**Convention « zéro = non mesuré ».** Une composante absente vaut `null`, jamais
0 ; 0 est réservé à une mesure valide qui rapporte réellement zéro point.

Fichiers touchés :

- `lib/services/yele_scoring_engine.dart` (nouveau) : moteur pur, composantes,
  statuts, classification indicative.
- `lib/models/speed_test_result.dart` : champs Hive **44 à 51** (les index 34 à
  41 étaient déjà pris par IMP-01, ISS-02 et ISS-01 — aucun index existant n'est
  renuméroté) et getters `scoreGlobalOn100`, `scoreMeasuredSubtotal`,
  `scoreMeasuredOn100`, `scoringStatuses`.
- `lib/services/speed_test_api_service.dart` : `_applyOpenScore` renseigne les
  champs à la construction du résultat.
- `lib/screens/history_screen.dart` : la colonne « Score » affiche l'indice
  0-100 (`—` si aucune composante, `*` si sous-total) ; le dépli ajoute le score
  global et les composantes mesurées.

## Choix non évidents

- **Le streaming est reconstruit exactement** : durée totale = somme des paliers
  réellement servis (`STREAMING_LEVEL_DURATION_SEC`), buffering = somme mesurée,
  interruptions = `rebufferCount` cumulé. Aucun chiffre n'est inventé.
- **La navigation utilise le temps moyen**, seul temps conservé aujourd'hui : les
  temps par page ne sont pas persistés. La QoE du moteur étant linéaire en
  temps, la moyenne des QoE égale la QoE du temps moyen — mais les pages en
  échec (au-delà de 30 s, non comptées dans la moyenne) ne sont pas pénalisées.
  Persister les temps par page reste à faire.
- **Les anciens résultats ne sont pas rescopés** : sans version de scoring, ils
  conservent l'ancienne note d'écran ; aucune version ne leur est rétro-attribuée.

## Ce que ce portage ne couvre pas

Le critère du classeur porte sur **trois vues** (application, dashboard,
historique). Ce commit couvre l'application et l'historique :

- `New_web` (dashboard) n'affiche pas encore l'indice : la route backend et la
  vue restent à faire ;
- `mobiletest` n'expose pas encore le score calculé : les champs sont envoyés
  dans `extra` et ignorés par un backend plus ancien.

## Critère d'acceptation

Pour un même résultat, l'indice affiché est identique dans l'écran de résultat
et dans l'historique, et il est dérivé du seul score global stocké.

| Situation | Attendu |
|---|---|
| Cinq composantes complètes | score global = somme, indice 0-100 sans marque |
| Test de débit seul (sans navigation ni streaming) | score global `null`, sous-total mesuré suivi de `*` |
| Aucune composante mesurée | `—` |
| Résultat antérieur au scoring | ancienne note d'écran, aucune version attribuée |

## Validation

- **Automatisée** : `flutter analyze` sans aucun avertissement ; `flutter test`
  vert, **141 tests** (88 sur `main` avant la branche, donc +53) dont
  `test/yele_scoring_engine_test.dart` (53 cas : bornes de débit, plafonds,
  latence à 250 ms, pages manquantes, incohérences de streaming, complétude).
- **Support imposé par le classeur** : local (3 vues cohérentes) — **partiel** :
  seules les deux vues de `mobilefront` existent à ce stade, le dashboard
  `New_web` n'étant pas branché.
- **Non réalisé** : aucun test sur APK ni dans Chrome pour ce commit.

## Limites connues

- L'indice 0-100 est une normalisation par la somme de référence : elle ne
  change pas le classement, mais elle n'est pas calibrée sur un échantillon
  représentatif, pas plus que les seuils de `classify`.
- La navigation n'est pas pénalisée par ses pages en échec (voir plus haut).
- IMP-05 (échelle de score) reste ouverte : le scoring ARCEP d'IMP-06 note
  navigation et streaming sur 100, tandis que ce moteur les note en points. Les
  deux échelles coexistent dans l'application et doivent être unifiées.
- Le backend `mobiletest` et le dashboard `New_web` ne consomment pas encore ces
  champs.

## Liste de contrôle avant d'ouvrir la PR

- [x] La fiche est dans `docs/fiches/` avec le nom `IMP-12-score-global-ouvert.md`.
- [x] Les champs du tableau viennent de `docs/items-v14.json`.
- [x] Une ligne **datée** a été ajoutée au tableau d'historique de
      `docs/registre-revisions.md` (sans elle, `guard` est rouge).
- [x] Le `CHANGELOG.md` du dépôt a une entrée sous `## [Non publiée]`.
- [x] Le corps de la PR porte `Closes #16` et la même liste de validation.
