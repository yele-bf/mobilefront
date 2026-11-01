# ISS-06 — Débit et latence : Min / Moy / Max

| Champ | Valeur |
|---|---|
| Dépôts | `mobilefront`, `mobiletest` |
| Issue | [#22](https://github.com/yele-bf/mobilefront/issues/22) |
| Priorité / vague | P2 / V3 Mesures & synchronisation |
| Owner au classeur | Wangraoua Aicha Bénédicte Flore Myriam / SAWADOGO Sutongnoma Saturnin |
| Branche | `iss/ISS-06-min-moy-max` (même nom dans les deux dépôts) |
| Validation imposée | Local (Chrome + dashboard) |

## Constat et impact

Le résultat d'un test ne donnait qu'une valeur par métrique : le débit moyen et
la latence moyenne. Impossible de savoir si une connexion avait été stable ou
avait connu des creux et des pics pendant la mesure.

## Correction

**Application (`mobilefront`)**

- `lib/services/speed_test_api_service.dart` :
  - **Débits** : pendant chaque phase de transfert, un minuteur relève le débit
    instantané (fenêtre glissante) toutes les 500 ms, hors montée en charge
    TCP. Le min et le max sont tirés de ces relevés. C'est un minuteur, et non
    l'arrivée des octets, qui cadence les relevés : une coupure du flux donne
    donc bien un relevé à 0 au lieu de passer inaperçue. Si la phase est trop
    courte pour avoir un relevé, min = max = moyenne.
  - **Latence** : 10 sondes au lieu de 5 (pour que le min et le max aient un
    sens), dont on garde le min et le max.
  - **Moyenne** : inchangée (`downloadSpeed`, `uploadSpeed`, `ping`), pour que
    le score et l'historique ne bougent pas.
- `lib/models/speed_test_result.dart` et `.g.dart` :
  - six champs `downloadMin/Max`, `uploadMin/Max`, `pingMin/Max`
    (`@HiveField(53–58)` ; le 52 est réservé à `packetLoss`, IMP-07) ;
  - une extension `downloadStats` / `uploadStats` / `pingStats` qui renvoie le
    triplet (min, moyenne, max), ou null si min ou max manque.
- `lib/screens/score_screen.dart` : tableau Min / Moy / Max (Download, Upload,
  Latence) sous les trois valeurs principales du bilan.
- `lib/screens/history_screen.dart` : lignes « Download / Upload / Latence
  min / moy / max » dans le détail d'un test, masquées pour les anciens
  résultats.
- Envoi au serveur : six clés dans `extra`, omises si non mesurées.

**Serveur (`mobiletest`)**

- `database/mongodb/mongodb.go` : les six valeurs sont lues dans `extra` et
  stockées (`download_min`…`ping_max`, en `*float64`, omises si nulles).
- `database/mongodb/minmax.go` : `validMinMax()` ne garde un couple que s'il est
  complet, positif ou nul et ordonné (min ≤ max) ; sinon le couple est « non
  mesuré ».

## Critère d'acceptation

Les six indicateurs (min, moyenne et max du download, de l'upload et de la
latence) sont disponibles dans le résultat et dans l'historique dès qu'ils sont
calculables.

## Validation

- **Automatisée** :
  - `test/min_moy_max_test.dart` (app) vérifie :
    - les triplets, la moyenne étant la valeur principale ;
    - les métriques absentes ou incomplètes ;
    - la persistance Hive des index 53 à 58.
  - `TestToDocumentMinMax` (serveur) vérifie les couples conservés et les
    couples absents, incomplets, inversés ou négatifs.

  Ces tests sont exécutés par les checks `build` et `android` des deux PR :
  pas de chaîne Flutter ni Go sur le poste de l'agent.
- **Support imposé par le classeur (Local, Chrome + dashboard)** : non réalisé
  à la date de la PR. À faire :
  1. lancer un test dans Chrome (`flutter run -d chrome`) ;
  2. capturer le tableau du bilan et le détail de l'historique.
- **Preuve** : à verser dans `docs/preuves/ISS-06/`.

## Limites connues

- Le dashboard ne montre pas encore les min / max : le serveur les stocke mais
  ne les expose pas dans `/api/dashboard/*`. C'est à prévoir dans `New_web` si
  le classeur l'exige pour la validation « dashboard ».
- Le min de débit inclut les creux réels (0 pendant une coupure) : c'est voulu,
  mais il peut surprendre sur un réseau instable.
- Passer de 5 à 10 sondes de latence allonge la phase d'environ une seconde.
- Si la PR IMP-07 (perte de paquets) est fusionnée avant, il faudra résoudre un
  conflit trivial dans `speed_test_result.g.dart` : le nombre de champs écrits
  (`writeByte`) passe à 56 avec les deux PR.
