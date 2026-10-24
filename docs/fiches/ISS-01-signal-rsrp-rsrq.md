# ISS-01 — RSRP/RSRQ jamais collectés ni affichés

| Champ | Valeur |
|---|---|
| Dépôt | `mobilefront` |
| Issue | [#18](https://github.com/yele-bf/mobilefront/issues/18) |
| Priorité / vague | P1 / V2 Réseau app (terrain) |
| Owner au classeur | SAWADOGO Hassan Achraf Ammar |
| Branche | `feature/signal-rsrp-rsrq` |
| Validation imposée | APK réel 4G/5G (terrain) |

## Constat et impact

L'application mesurait le débit, la latence et la gigue, mais ne conservait
aucune métrique radio : ni la puissance (RSRP), ni la qualité (RSRQ) de la
cellule qui sert les données. Une mesure de débit ne pouvait donc pas être
replacée dans son contexte radio, ce qui est justement le cœur de la
comparaison demandée au classeur.

## Correction

**Côté Android** (`android/app/src/main/kotlin/com/yele/mobilefront/`) :

- `SignalMetrics.kt` (nouveau) — point unique d'extraction, partagé par le test
  actif et la collecte passive, pour que les deux chemins produisent les mêmes
  champs :
  - mesure générique `signalDbm` / `signalLevel` via `getSignalStrength`
    (Android 9+), qui couvre 2G/3G et sert de repli ;
  - `signalRsrp` / `signalRsrq` depuis la première `CellInfoLte` de
    `getAllCellInfo` (Android 8+) ;
  - `signalNrRsrp` / `signalNrRsrq` (`ssRsrp` / `ssRsrq`) pour la 5G SA
    (Android 11+) ;
  - `wifiRssi` du point d'accès associé, hors plage physique rejeté.
- Convention d'indisponibilité : une valeur inconnue est **absente** du
  payload, jamais `0` — c'est ce qui permet de distinguer « non mesuré » d'une
  vraie mesure côté backend et dashboard.

**Côté Dart** :

- `lib/services/network_info_service.dart` — `NetworkStatus` porte les 7
  nouvelles valeurs, lues depuis le canal natif et laissées nulles si le canal
  ne les renvoie pas (iOS, Android ancien, permission de localisation refusée).
- `lib/models/speed_test_result.dart` (+ `.g.dart`) — champs Hive **36 à 41**.
  Les champs 34 (`dataUsedKiB`, IMP-01) et 35 (`simSlot`, ISS-02) sont
  conservés : aucun numéro de champ existant n'est réutilisé.
- `lib/screens/history_screen.dart` — deux lignes distinctes, « Signal »
  (RSRP/NR RSRP/RSSI, avec libellé de qualité aux seuils IUT −80/−95/−105 dBm et
  −65/−75/−85 dBm) et « Qualité du signal » (RSRQ/NR RSRQ). Rien ne s'affiche
  si rien n'a été mesuré.
- `lib/services/speed_test_api_service.dart` — les six valeurs partent dans le
  payload de mesure pour le backend et le dashboard.

## Critère d'acceptation

Les valeurs RSRP/RSRQ sont affichées pour chaque mesure lorsque disponibles.

## Validation

- **Automatisée** : `flutter analyze` + `flutter test` verts, et le check
  `android` (`flutter build apk --debug`) qui compile réellement
  `SignalMetrics.kt` — `flutter analyze` ne voit pas le Kotlin.
- **Support imposé (APK réel 4G/5G)** : les relevés annoncés par l'auteur
  proviennent de logs de diagnostic ; aucune mesure avec valeurs RSRP/RSRQ
  n'est jointe à la PR. Statut `Transmis` au registre jusqu'à ce relevé.

## Limites

- `getAllCellInfo` exige la permission de localisation : sans elle, seule la
  mesure générique est disponible (repli prévu, aucune valeur inventée).
- En 5G NSA, l'ancre reste LTE : les champs `signalNr*` sont vides et les
  champs LTE sont renseignés — c'est le comportement attendu, pas un défaut.
- Aucun test unitaire Dart ne couvre l'extraction Kotlin : elle n'est vérifiée
  que par la compilation et par un relevé terrain.
