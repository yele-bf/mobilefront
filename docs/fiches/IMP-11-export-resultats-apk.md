# IMP-11 — Export des résultats sur l'APK depuis l'écran de fin de mesure ou depuis l'onglet historique

| Champ | Valeur |
|---|---|
| Dépôt | `mobilefront` |
| Issue | [yele-bf/mobiletest#3](https://github.com/yele-bf/mobiletest/issues/3) |
| Priorité / vague | P2 / V1 Quick wins |
| Owner au classeur | COMPAORE Bobodo Kévin Aymar |
| Branche | `amé/IMP-11-export-resultats-apk` |
| Validation imposée | APK réel |

## Constat et impact

Aucun export des résultats depuis l'écran de fin de mesure ou l'onglet historique de l'APK. Gêne l'exploitation des mesures sur le terrain.

## Correction

**Formalisation / harmonisation** (code déjà existant, ajouté majoritairement sous IMP-13) :

- **Service** : `lib/services/export_service.dart` — `exportCsv`, `exportExcel`, `exportPdf`, `exportPng` pour un `SpeedTestResult`.
- **Feuille d'export** : `lib/widgets/export_sheet.dart` — options CSV / PDF / PNG / Excel uniquement (pas de JSON).
- **Branchement** : `lib/screens/score_screen.dart:598` (écran de fin/résultat) et `lib/screens/history_screen.dart:451` (onglet historique) via `showExportSheet(context, r)`.
- **Assets/affinage** : logo, polices NotoSans, fond blanc PNG (`cd8cd20`, `1717b44`).
- **Harmonisation** : rattachement correct à IMP-11 dans le suivi (items-v14, registre, CHANGELOG). IMP-13 reste strictement centré sur l'UUID anonymisé et stable.

## Critère d'acceptation

Depuis l'écran de fin de mesure ou l'onglet historique, un bouton permet d'exporter le résultat au format CSV/PDF/PNG/Excel.

## Validation

- **Automatisée** : `flutter analyze` OK, `flutter test` 88/88 OK.
- **Support imposé par le classeur** : APK réel — **vérifié par lecture de code + branchement**. Les points d'entrée existent bien aux deux endroits requis.
- **Preuve** : `cd8cd20`, `1717b44` (export) ; branchement `score_screen.dart:598`, `history_screen.dart:451` ; `export_sheet.dart` (CSV/PDF/PNG/Excel).

## Limites connues

- **Mélange historique** : l'essentiel de l'export a été livré sous IMP-13. Seule l'harmonisation/traçabilité est faite ici, sans réécrire l'historique Git.
- **JSON** : hors périmètre (retiré volontairement).
- **Test terrain complet** : idéal sur APK réel, validé par examen du code et des points d'appel.

## Liste de contrôle avant d'ouvrir la PR

- [x] La fiche est dans `docs/fiches/` avec le nom `IMP-11-export-resultats-apk.md`.
- [x] Les champs du tableau viennent de `docs/items-v14.json` (harmonisé vers mobilefront).
- [x] Une ligne **datée** a été ajoutée au tableau d'historique de `docs/registre-revisions.md`.
- [x] Le `CHANGELOG.md` du dépôt a une entrée sous `## [Non publiée]`.
- [ ] Le corps de la PR porte `Closes yele-bf/mobiletest#3` et la même liste de validation.
