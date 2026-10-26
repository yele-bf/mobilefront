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
utilise.

Les deux scores sont pourtant affichés comme des notes sur 100 :

- navigation : `lib/services/browsing_test_service_native.dart` compte une page
  « réussie » sous 10 s et retire 1 point par 100 ms au-delà de 2 s ;
- streaming : `aggregateStreamingResults` (`lib/services/streaming_shared.dart`)
  moyenne les taux de performance des paliers servis.

Conséquence : un test peut afficher 100/100 avec des pages lentes au regard du
référentiel, ou perdre des points pour un démarrage vidéo de 4 s alors que le
seuil ARCEP est de 5 s. Le score ne reflète donc pas le référentiel attendu.

## Correction

Cette branche pose le référentiel et le squelette du recâblage ; elle ne
change encore aucun score affiché.

- `lib/constants/arcep_seuils.dart` : le référentiel validé (v3) sous forme de
  constantes typées (`ArcepSeuils.valides`), avec `ArcepSeuils.fromApiJson`
  pour le champ `qos` de `/api/arcep/measure`. Un champ absent conserve la
  valeur validée, pour qu'un backend plus ancien ne remette pas les seuils à
  zéro.
- `lib/services/arcep_scoring.dart` : les prédicats de seuil (`pageDansSeuil`,
  `connexionDansSeuil`, `preloadDansSeuil`, `sessionBonneQualite`) sont
  implémentés ; les deux scores composites (`scoreNavigation`,
  `scoreStreaming`) lèvent explicitement tant qu'ils ne sont pas définis, afin
  qu'aucun écran n'affiche un score faussement conforme.

Choix non évidents :

- Les seuils sont recopiés côté application au lieu d'être lus uniquement à
  l'exécution : un test de débit doit rester scoré hors ligne ou quand l'API
  ARCEP est désactivée. La réponse de l'API reste prioritaire quand elle est
  disponible.
- Le seuil de navigation retenu est celui du référentiel (30 s), pas la
  constante de 10 s actuelle, qui n'a pas de source ARCEP.
- La résolution minimale (480p), le rebuffering (10 %) et l'absence
  d'interruption viennent de la définition Yélé, pas d'ARCEP : les commentaires
  le disent, pour ne jamais présenter ces valeurs comme officielles.

## Critère d'acceptation

Pour chaque niveau de performance, le score obtenu correspond aux seuils
validés — vérifié par des jeux de valeurs situées de part et d'autre de chaque
seuil (30 s, 20 s, 5 s, 10 %, 480p, 0/1 interruption).

**Non atteint à ce stade** : les scores ne sont pas encore recâblés, donc le
critère reste à démontrer.

## Validation

- **Automatisée** : `flutter analyze` sans aucun avertissement et `flutter test`
  vert (67 tests, dont `test/arcep_seuils_test.dart` : valeurs v3, surcharge par
  l'API, repli d'un champ absent, réponse vide).
- **Support imposé par le classeur** : local (jeux de valeurs autour des
  seuils) — **non fait pour le score** : aucun score n'est encore calculé par
  les seuils.
- **Preuve** : sortie de `flutter test test/arcep_seuils_test.dart` (4 cas
  verts) à joindre à la PR.

## Limites connues

- Les deux scores composites ne sont pas implémentés : la branche ne fait que
  poser le référentiel et les prédicats.
- Aucun branchement dans `browsing_test_service_native.dart`,
  `browsing_test_service_web.dart` ni `streaming_shared.dart`.
- La partie backend de l'item (`mobiletest`) est préparée dans une branche
  distincte : sur `main`, le module ARCEP n'existe plus (`results/arcep.go` et
  `config/seuils.json` ne sont pas fusionnés), donc l'application ne peut pas
  encore lire les seuils depuis l'API. Le repli `ArcepSeuils.valides` couvre ce
  cas.
- IMP-05 (échelle de score) et IMP-12 (score global) touchent les mêmes
  fonctions : la définition finale des scores doit être coordonnée avec ces
  deux items avant merge.

---

## Liste de contrôle avant d'ouvrir la PR

- [x] La fiche est dans `docs/fiches/` avec le nom `IMP-06-seuils-arcep-scoring.md`.
- [x] Les champs du tableau viennent de `docs/items-v14.json`.
- [x] Une ligne **datée** a été ajoutée au tableau d'historique de
      `docs/registre-revisions.md` (sans elle, `guard` est rouge).
- [x] Le `CHANGELOG.md` du dépôt a une entrée sous `## [Non publiée]`.
- [ ] Le corps de la PR porte `Closes #12` et la même liste de validation.
