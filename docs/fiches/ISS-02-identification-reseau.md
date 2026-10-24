# ISS-02 — Identification réseau en double SIM

| Champ | Valeur |
|---|---|
| Dépôt | `mobilefront` |
| Issue | [#19](https://github.com/yele-bf/mobilefront/issues/19) |
| Priorité / vague | P1 / V2 Réseau app (terrain) |
| Owner au classeur | BAMBA Seydou / NANEMA Wendinkonté Dimitri Judicaël |
| Branche | `iss/ISS-02-identification-reseau` |

## Constat et impact

Sur un appareil à deux SIM, l'application peut afficher l'opérateur de la SIM 1
alors que les données mobiles et la mesure utilisent la SIM 2. Les mesures
risquent donc d'être attribuées au mauvais opérateur.

## Correction

Sur Android 7 ou ultérieur, lire les informations téléphoniques via un
`TelephonyManager` lié à l'abonnement de données par défaut. Exposer également
son emplacement SIM à l'interface et enregistrer cet emplacement avec le
résultat de mesure. Si l'abonnement ou les détails SIM sont indisponibles,
conserver le comportement dégradé existant sans inventer d'opérateur.

## Critère d'acceptation

L'opérateur et, lorsque disponibles, l'emplacement SIM affichés correspondent à
la SIM sélectionnée pour les données mobiles pendant la mesure.

## Validation

- **Automatisée** : `flutter analyze` et `flutter test` verts en CI sur la
  PR #30, dont `test/sim_identification_test.dart`.
- **Terrain (support imposé par le classeur : APK réel double SIM)** — faite le
  24/10/2026, captures publiées dans la PR #30 :
  - données mobiles sur **Orange → SIM 2** : la SIM 2 est annoncée ;
  - données mobiles sur **Télécel → SIM 1** : la SIM 1 est annoncée ;
  - **Wi-Fi, données mobiles coupées** : la capture montre encore l'opérateur
    de la SIM présenté comme réseau du test. Ce point relève d'ISS-03 (PR #32)
    et non d'ISS-02.

Statut : **Validé** — merge `5ca52d9` (24/10/2026).
