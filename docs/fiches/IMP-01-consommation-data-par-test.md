# IMP-01 — Consommation data par test

| Champ | Valeur |
|---|---|
| Dépôt | `mobilefront` |
| Issue | [#7](https://github.com/yele-bf/mobilefront/issues/7) |
| Priorité / vague | P3 / V3 Mesures & synchronisation |
| Owner au classeur | COMPAORE Bobodo Kévin Aymar |
| Branche | `amé/IMP-01-consommation-data-par-test` |
| Validation imposée | APK réel (conso data) |

## Constat et impact

La quantité de données consommées pendant les mesures n'était pas affichée. D'où difficulté à suivre la consommation de forfait data pour l'utilisateur.

## Correction

Implémentation existante, formalisée dans le cadre du processus :

- **Mesure** : `lib/services/traffic_stats_service.dart` — `TrafficStatsService` lit les compteurs `TrafficStats` Android via `MethodChannel` (`getRxBytes`/`getTxBytes`) ; `DataUsageCapture.start()/stopKiB()` calcule `rx+tx` en KiB entre début et fin de test. Sur iOS, les compteurs ne sont pas exposés → `-1`, affiché « — ».
- **Modèle** : `lib/models/speed_test_result.dart` — ajout du champ `dataUsedKiB` (persisté Hive, sérialisé/désérialisé).
- **Branchement** : `lib/services/speed_test_api_service.dart` (débit complet) et `lib/services/streaming_test_service.dart` / `lib/services/streaming_test_service_hls.dart` (streaming classique + HLS) — relevé avant/après test et agrégation par qualité.
- **Affichage** : `lib/screens/score_screen.dart` et `lib/screens/history_screen.dart` — affichage « Données consommées » si mesuré.
- **Export** : `lib/services/export_service.dart` — intégration CSV/JSON.
- **Suivi** : `lib/services/throughput_service.dart`, `lib/services/settings_service.dart`, `lib/screens/usage_screen.dart` — suivi mensuel et seuil.

## Critère d'acceptation

La consommation est affichée en Mo/Go à la fin de chaque mesure et disponible dans l'historique.

## Validation

- **Automatisée** : `flutter analyze` → No issues found ; `flutter test` → 88 tests passed.
- **Support imposé par le classeur** : APK réel (conso data) — **non vérifié sur appareil physique/forfait**. Validé par **lecture de code** : mesure via `TrafficStats` (rx+tx), différence avant/après, branchement sur les 3 parcours, affichage dans score/historique, export, gestion iOS (—).
- **Preuve** : code vérifié dans `mobilefront` (branche `main` @ `87edf33`), CI locale verte.

## Limites connues

- **Mesure sur appareil physique requise pour validation absolue** : la comparaison « affiché vs compteur téléphone/opérateur » n'a pas pu être faite dans cet environnement (pas de téléphone/forfait disponible). Arbitrage acté : validation par lecture de code.
- **iOS** : non mesurable via `TrafficStats` → « — » par conception.
- **Trafic hors périmètre du test** : la mesure couvre le trafic de l'app entre `start()` et `stopKiB()` (inclut le WebView/Chromium dans le même UID sous Android, cf. commentaire dans `traffic_stats_service.dart`).

## Liste de contrôle avant d'ouvrir la PR

- [x] La fiche est dans `docs/fiches/` avec le nom `IMP-01-consommation-data-par-test.md`.
- [x] Les champs du tableau viennent de `docs/items-v14.json`.
- [x] Une ligne **datée** a été ajoutée au tableau d'historique de `docs/registre-revisions.md`.
- [x] Le `CHANGELOG.md` du dépôt a une entrée sous `## [Non publiée]`.
- [ ] Le corps de la PR porte `Closes #7` et la même liste de validation.
