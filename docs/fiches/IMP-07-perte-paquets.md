# IMP-07 — Mesure et affichage de la perte de paquets

| Champ | Valeur |
|---|---|
| Dépôts | `mobilefront`, `mobiletest` |
| Issue | [#13](https://github.com/yele-bf/mobilefront/issues/13) |
| Priorité / vague | P2 / V4 Métriques & score |
| Owner au classeur | SANOU Zossoun Aristide Daouda / TRAORE Oumou Kal / Ilboudo Wendpagnagdé Elsa Fleur |
| Branche | `imp/IMP-07-perte-paquets` (même nom dans les deux dépôts) |
| Validation imposée | Local + APK (ping) |

## Constat et impact

La perte de paquets n'était pas mesurée, alors que nPerf l'affiche avec le ping
et la gigue. Une connexion peut avoir un bon débit et pourtant ramer à cause de
paquets perdus : sans cette valeur, l'analyse de la qualité de service restait
incomplète.

## Correction

**Application (`mobilefront`)**

- `lib/services/packet_loss_service.dart` (nouveau) : mesure de la perte vers
  l'hôte du serveur de test.
  - Sur Android, la commande `ping` ICMP du système envoie 20 paquets espacés
    de 200 ms, avec un délai de 1 s par réponse. C'est une vraie perte de
    paquets, comparable à nPerf.
  - Si l'ICMP n'est pas disponible (iOS, web) ou s'il est filtré (100 % de
    perte), on passe à 20 sondes HTTP `/empty` ; une sonde sans réponse sous
    2 s compte comme perdue.

  Le calcul est isolé dans `parsePingLossPercent()` pour être testable ; le
  format d'affichage est commun (`formatPacketLoss()` : « 0 % », « 2,5 % »).
- `lib/services/speed_test_api_service.dart` : la mesure est lancée juste après
  la latence (même serveur, lien déjà déchargé) avec le message « Mesure de la
  perte de paquets ». Le résultat est rangé dans le `SpeedTestResult` et envoyé
  dans `extra.packetLoss`. Il n'est pas envoyé s'il n'a pas été mesuré : 0 est
  une valeur légitime et ne peut pas signifier « absent ».
- `lib/models/speed_test_result.dart` et `.g.dart` : champ `packetLoss`
  (`@HiveField(52)`). Les index 53 à 58 restent libres pour ISS-06.
- `lib/screens/score_screen.dart` : « Perte : x % » sous la gigue, dans la case
  Latence du bilan.
- `lib/screens/history_screen.dart` : ligne « Perte de paquets » dans le détail
  d'un test. Elle est masquée pour les anciens résultats.

**Serveur (`mobiletest`)**

- `database/mongodb/mongodb.go` :
  - `mobileExtra.PacketLoss` est lu dans `extra` ;
  - `Document.PacketLoss` est stocké sous `packet_loss`, en `*float64`, omis
    s'il est nul ;
  - `MapPoint.PacketLoss` est renvoyé par `/api/dashboard/map`.

  `validPacketLoss()` rejette les valeurs hors de 0–100 % comme non mesurées.
  Le type `*float64` sépare « non mesurée » (`null`) de « aucune perte » (0).

## Critère d'acceptation

Le pourcentage de paquets perdus est affiché dans le résultat du test (case
Latence) et dans l'historique (détail du test).

## Validation

- **Automatisée** :
  - `test/packet_loss_test.dart` (app) vérifie :
    - la lecture de la sortie de `ping` (perte partielle, décimale, nulle,
      sortie sans synthèse) ;
    - le repli HTTP (50 % et 0 %) ;
    - le format d'affichage.
  - `TestToDocumentPacketLoss` (serveur) vérifie six cas : absente, 0, 2,456
    arrondi à 2,46, 100, négative, au-delà de 100.

  Ces tests sont exécutés par les checks `build` et `android` des deux PR :
  aucune chaîne Flutter ni Go n'était disponible sur le poste de l'agent.
- **Support imposé par le classeur (Local + APK, ping)** : non réalisé à la
  date de la PR. À faire avec l'APK de debug produit par le check `android` :
  1. lancer un test sur un réseau mobile ;
  2. capturer la case Latence du bilan et le détail de l'historique ;
  3. lancer nPerf au même endroit et comparer les valeurs, idéalement sur un
     réseau chargé.
- **Preuve** : à verser dans `docs/preuves/IMP-07/`.

## Limites connues

- Le repli HTTP sous-estime la perte réelle, car TCP retransmet les paquets
  perdus : il ne voit que les pertes qui bloquent une requête plus de 2 s.
  L'iPhone et le web passent toujours par ce repli.
- Certains réseaux ou serveurs filtrent l'ICMP. La mesure retombe alors sur
  HTTP et n'est plus directement comparable à nPerf.
- La mesure ajoute environ 4 s (ICMP) à 40 s (HTTP dans le pire cas) à la
  phase de latence.
- Les valeurs n'ont pas encore été comparées à nPerf sur le terrain.
- Le dashboard reçoit `packetLoss` dans `/api/dashboard/map` mais ne l'affiche
  pas encore : cela ne fait pas partie de l'item.
