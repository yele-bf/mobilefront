# IMP-06 — Seuils ARCEP ancrés dans le scoring Navigation / Streaming

| Champ | Valeur |
|---|---|
| Dépôt | `mobilefront` |
| Issue | [#12](https://github.com/yele-bf/mobilefront/issues/12) |
| Priorité / vague | P2 / V5 Dashboard & référentiel |
| Owner au classeur | NIKIEMA Abdoul Fatahou / NONGUIERMA WENDINSOO LEONEL |
| Branche | `feat/IMP-06-seuils-arcep` |
| Validation imposée | Local (jeux de valeurs autour des seuils) |

## Constat et impact

Les seuils de référence ARCEP existent dans le projet — `config/seuils.json`
version 3 du dépôt `mobiletest` (navigation : page ≤ 30 s, 95 % des pages,
connexion ≤ 20 s ; streaming : démarrage ≤ 5 s, 95 % des sessions, rebuffering
≤ 10 %, résolution ≥ 480p, 0 interruption) — mais aucun calcul de score ne les
utilisait.

Les deux scores étaient pourtant affichés comme des notes sur 100 :

- navigation : `lib/services/browsing_test_service_native.dart` comptait une
  page « réussie » sous 10 s et retirait 1 point par 100 ms au-delà de 2 s ;
- streaming : `aggregateStreamingResults` moyennait les taux de performance des
  paliers servis, sans confronter démarrage, rebuffering, interruptions ni
  résolution aux seuils.

Conséquence : un test pouvait afficher 100/100 avec des pages lentes au regard
du référentiel, ou perdre des points pour un démarrage vidéo de 4 s alors que
le seuil ARCEP est de 5 s.

## Correction

Le référentiel est isolé dans `lib/constants/arcep_seuils.dart`
(`ArcepSeuils.valides`, version 3) et les deux scores sont recalculés à partir
de lui, dans `lib/services/arcep_scoring.dart` :

| Mesure | Règle appliquée | Ancrage |
|---|---|---|
| Navigation — page réussie | chargée sous 30 s | `page_load_s` |
| Navigation — score | `100 × pages réussies / pages testées − 20 × (temps moyen / 30 s)`, borné 0-100 | `page_load_s` |
| Streaming — base | moyenne des taux de performance des paliers réellement servis | règle nPerf conservée |
| Streaming — démarrage | facteur 1 jusqu'à 5 s, puis décroissance linéaire jusqu'à 0,5 au double du seuil | `preload_s` |
| Streaming — rebuffering | facteur 1 jusqu'à 10 %, même décroissance jusqu'à 0,5 à 20 % | `qualite_video.rebuffer_ratio_max` |
| Streaming — interruptions | 1 point de moins par interruption : 15 % de la note dès la première | `qualite_video.interruptions_max` (0) |
| Streaming — résolution | moitié de la note sous 480p | `qualite_video.resolution_min` |

Fichiers touchés :

- `lib/services/arcep_scoring.dart` : `scoreNavigation`, `scoreStreaming` et
  les prédicats de seuil (`pageDansSeuil`, `connexionDansSeuil`,
  `preloadDansSeuil`, `sessionBonneQualite`). Aucune durée « magique » : seul
  le seuil du référentiel est utilisé, les pénalités s'expriment en fractions
  de ce seuil.
- `lib/services/browsing_test_service_native.dart` et
  `browsing_test_service_web.dart` : la constante de 10 s et l'heuristique de
  2 s disparaissent ; la réussite d'une page et le délai de sécurité par page
  sont calculés depuis `page_load_s`, et le score vient de `scoreNavigation`.
- `lib/services/streaming_shared.dart` : `aggregateStreamingResults` garde la
  moyenne des paliers servis comme base, puis applique `scoreStreaming`.
- `lib/services/browsing_test_service.dart` : documentation de `successRate`
  alignée sur le seuil réel (30 s).

Choix non évidents :

- La moyenne par palier reste la base du score streaming : la remplacer par un
  barème de résolution aurait changé la règle nPerf que l'item ISS-07 vient de
  stabiliser. Les seuils ARCEP/Yélé la réduisent au lieu de la remplacer.
- Une page au-delà du seuil ne rapporte **aucun** point, même à 30,1 s : c'est
  le sens d'ARCEP, où la page est un échec. Le dégradé ne joue qu'à l'intérieur
  du seuil (20 points de confort).
- Les seuils sont recopiés dans l'application au lieu d'être lus uniquement à
  l'exécution : le test doit rester scoré hors ligne. `ArcepSeuils.fromApiJson`
  existe pour la surcharge, mais aucun appel réseau ne l'alimente encore.

## Critère d'acceptation

Pour chaque niveau de performance, le score obtenu correspond aux seuils
validés — vérifié par des jeux de valeurs de part et d'autre de chaque seuil :

| Seuil | En dessous | Au seuil | Au-dessus |
|---|---|---|---|
| Chargement 30 s | 29,999 s → page réussie, score 80,0 | 30,000 s → échec | 30,001 s → 0 point |
| Connexion 20 s | 19,999 s → dans le seuil | 20,000 s → hors seuil | 20,001 s → hors seuil |
| Démarrage vidéo 5 s | 4,999 s → note pleine | 5,000 s → 100 | 5,001 s → note entamée, 10 s → 50 |
| Rebuffering 10 % | 9,9 % → 100 | 10 % → 100 | 10,1 % → < 100, 20 % → 50 |
| Résolution 480p | 479p → 50 | 480p → 100 | 720p → 100 |
| Interruptions 0 | 0 → 100 | — | 1 → 85 |

## Validation

- **Automatisée** : `flutter analyze` sans aucun avertissement ; `flutter test`
  vert, **88 tests** (63 sur `main` avant la branche, donc +25) dont
  `test/arcep_seuils_test.dart` (4 cas), `test/navigation_score_test.dart`
  (8 cas) et `test/streaming_arcep_score_test.dart` (13 cas) — tous les cas
  limites du tableau ci-dessus.
- **Support imposé par le classeur** : local (jeux de valeurs autour des
  seuils) — **fait par les tests unitaires**, sans exécution de l'application
  sur appareil ni dans Chrome.
- **Preuve** : sortie de `flutter test` ci-dessus, à joindre à la PR.

## Limites connues

- **Aucun test sur APK ni dans Chrome** : les scores sont du calcul pur, couvert
  par les tests, mais l'écran de résultat n'a pas été revu sur appareil réel.
- Le seuil de connexion (20 s) est exposé (`connexionDansSeuil`) mais **n'entre
  pas encore dans le score** : le test de navigation mesure le chargement
  complet de la page, pas le temps d'établissement de connexion. L'ajouter
  suppose une mesure supplémentaire.- `ArcepSeuils.fromApiJson` n'est branché sur aucun appel réseau : les valeurs
  de `seuils.json` v3 recopiées dans l'application font foi. Le module ARCEP
  revient sur `main` de `mobiletest` avec la PR #9 (mêmes seuils, désormais
  servis par `/api/arcep/*`) ; brancher `fromApiJson` sur ces routes reste à
  faire, et les deux copies doivent alors être maintenues ensemble.
- Les pénalités streaming (15 % par interruption, moitié sous 480p, décroissance
  jusqu'au double du seuil) sont des règles **Yélé documentées**, pas des
  valeurs ARCEP : les commentaires du code le disent.
- IMP-05 (échelle de score) et IMP-12 (score global) touchent les mêmes
  fonctions : la définition finale doit être coordonnée avant merge.

---

## Liste de contrôle avant d'ouvrir la PR

- [x] La fiche est dans `docs/fiches/` avec le nom `IMP-06-seuils-arcep-scoring.md`.
- [x] Les champs du tableau viennent de `docs/items-v14.json`.
- [x] Une ligne **datée** a été ajoutée au tableau d'historique de
      `docs/registre-revisions.md` (sans elle, `guard` est rouge).
- [x] Le `CHANGELOG.md` du dépôt a une entrée sous `## [Non publiée]`.
- [x] Le corps de la PR porte `Closes #12` et la même liste de validation.
