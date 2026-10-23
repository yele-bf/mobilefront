# ISS-04 — Afficher le serveur réellement utilisé

## Constat

Les écrans de test et de résultat affichaient « yele_serveur — Ouagadougou »,
alors que l'application envoie les tests à l'endpoint configuré dans
`API_BASE_URL`.

## Correction

Le libellé du serveur est désormais dérivé du nom d'hôte de `API_BASE_URL` et
utilisé dans les écrans, les résultats enregistrés et la liste du serveur.
L'application n'affirme plus que le serveur se trouve à Ouagadougou.

## Critère d'acceptation

Le serveur affiché correspond à l'endpoint configuré et effectivement utilisé.

## Validation

`flutter analyze` et `flutter test -d chrome test/server_display_name_test.dart`
passent. L'application a été lancée localement dans Chrome et affiche
`mobiletest-j0c6.onrender.com` comme serveur de test. Le test de débit n'a pas
été lancé afin de ne pas solliciter le backend de production depuis cette
branche.
