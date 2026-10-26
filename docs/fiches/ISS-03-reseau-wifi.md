# ISS-03 — Infos réseau mobile affichées pendant un test Wi-Fi

| Champ | Valeur |
|---|---|
| Dépôt | `mobilefront` |
| Issue | [#20](https://github.com/yele-bf/mobilefront/issues/20) |
| Priorité / vague | P1 / V2 Réseau app (terrain) |
| Owner au classeur | SAWADOGO Hassan Achraf Ammar |
| Branche | `iss/ISS-03-reseau-wifi` |
| Validation imposée | APK réel (Wi-Fi vs données mobiles) |

## Constat et impact

Dès qu'une carte SIM est insérée, l'application affichait la techno cellulaire et
l'opérateur de cette SIM même quand le test passait par le Wi-Fi. Deux
conséquences : le réseau réellement utilisé n'est pas identifiable, et une
mesure faite en Wi-Fi est enregistrée avec des champs SIM, donc attribuable au
mauvais réseau dans l'historique et dans les exports.

## Correction

Une seule règle appliquée aux trois écrans concernés : si la connexion est
Wi-Fi, ni opérateur SIM ni techno cellulaire.

1. `lib/screens/full_test_screen.dart` — `_formatMobile` renvoie « — » en
   Wi-Fi, et le résultat envoyé au service de mesure porte
   `simOperator: null` / `cellularTech: null` : les nouveaux enregistrements ne
   stockent plus l'information. Le champ `simSlot` d'ISS-02 est laissé
   intact, ainsi que l'URL et les constantes de configuration.
2. `lib/screens/history_screen.dart` — la ligne « Réseau mobile » du détail est
   masquée quand `networkType` contient `WIFI`, ce qui couvre aussi les
   enregistrements antérieurs au correctif.
3. `lib/screens/score_screen.dart` — `_mobileLabel` renvoie « — » en Wi-Fi.

## Critère d'acceptation

Lors d'un test Wi-Fi, aucune information de réseau mobile n'est présentée comme
réseau utilisé pour le test.

## Validation

- **Automatisée** : `flutter analyze` + `flutter test` verts, plus les checks
  `guard` et `android` (compilation APK de debug) sur la tête de PR.
- **Défaut reproduit** le 24/10/2026 sur `main` par une capture prise en Wi-Fi,
  données mobiles coupées : l'opérateur de la SIM apparaissait encore.
- **Support imposé (APK réel, Wi-Fi vs données mobiles)** : fait le 25/10/2026
  sur Hicel STAR 1 (Android 12), Orange Burkina Faso, Tampouy / Ouagadougou —
  en Wi-Fi, historique **et** écran de bilan sans ligne « Réseau mobile »
  (bilan :`Réseau mobile : —`) alors que la SIM 4G est enregistrée ;
  contre-épreuve en données mobiles affichant
  `Réseau mobile : 4G · Orange BF · SIM 1`.
- **Preuve** : trois captures —
  [`ISS-03_Wi-Fi_sans-reseau-mobile.png`](../preuves/ISS-03_Wi-Fi_sans-reseau-mobile.png),
  [`ISS-03_4G_reseau-mobile.png`](../preuves/ISS-03_4G_reseau-mobile.png),
  [`ISS-03_bilan-Wi-Fi_reseau-mobile-vide.png`](../preuves/ISS-03_bilan-Wi-Fi_reseau-mobile-vide.png)
  — jointes au commentaire du 26/10/2026 sur [#20](https://github.com/yele-bf/mobilefront/issues/20).

## Limites

- Le correctif agit sur l'affichage et sur les nouveaux enregistrements ; les
  anciens résultats gardent leurs champs SIM en base, seulement masqués.
- Aucun test automatisé ne couvre les trois écrans : la règle est vérifiée par
  revue de code, pas par un test de widget.
