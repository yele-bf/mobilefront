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

- Vérifications automatisées et compilation : à exécuter avant la PR.
- Validation imposée : APK réel sur un téléphone double SIM, en alternant les
  SIM de données et en vérifiant l'opérateur affiché ; à réaliser sur le terrain.
