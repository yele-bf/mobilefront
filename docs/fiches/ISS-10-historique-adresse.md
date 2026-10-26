# ISS-10 — Historique sans adresse (coordonnées seules)

| Champ | Valeur |
|---|---|
| Dépôt | `mobilefront` |
| Issue | [#25](https://github.com/yele-bf/mobilefront/issues/25) |
| Priorité / vague | P2 / V3 Mesures & synchronisation |
| Owner au classeur | SAWADOGO Hassan Achraf Ammar |
| Branche | `iss/ISS-10-historique-adresse` |
| Validation imposée | Chrome/APK + GPS |

## Constat et impact

Le détail d'une mesure n'affichait que `12.3657, -1.5339`. Ces coordonnées
suffisent au traitement statistique, mais pas à un utilisateur qui veut savoir
dans quelle ville ou quel quartier la mesure a été faite : la localisation
restait peu lisible, y compris pour le rapport transmis au régulateur.

## Correction

**Nouveau service** `lib/services/reverse_geocoding_service.dart` — géocodage
inversé par Nominatim (OpenStreetMap), le fournisseur déjà utilisé par la
recherche d'adresse du dashboard :

- **politique Nominatim respectée** : une requête au maximum par seconde,
  requêtes sérialisées (la suivante attend la fin de la précédente) et
  `User-Agent` identifiable (`YeleMobileApp/1.0 …`) ;
- **double cache** mémoire et disque (Hive, boîte `reverse_geocoding_cache`) :
  une même coordonnée n'est jamais demandée deux fois et les adresses
  survivent au redémarrage ;
- **périmètre** borné à la boîte englobante du Burkina Faso (9,0–15,5 N /
  −6,5–2,5 E) : hors de cette zone, aucun appel réseau n'est émis ;
- **« pas d'adresse ici » mémorisé** (sentinelle en cache) pour ne pas
  redemander à chaque affichage ;
- `forTest` désactive le cache disque : sans `Hive.init`, l'ouverture de boîte
  produit une erreur asynchrone qu'aucun `try/catch` ne rattrape.

**Écran** `lib/screens/history_screen.dart` — résolution à la demande, une
seule fois par coordonnée arrondie à 4 décimales, au dépliage du test :
« Coord. (adresse) » avec l'adresse lisible puis « Coordonnées » avec la valeur
brute ; pendant la résolution un indicateur discret s'affiche, et en cas
d'échec ou d'absence d'adresse OSM on retombe sur les seules coordonnées.

## Critère d'acceptation

Chaque mesure géolocalisée affiche coordonnées + adresse lorsque disponible.

## Validation

- **Automatisée** : `flutter analyze` + `flutter test` verts (dont
  `test/reverse_geocoding_service_test.dart`), plus `guard` et le check
  `android` sur la tête de PR.
- **Support imposé (Chrome/APK + GPS)** : fait sur APK le 25/10/2026, GPS
  actif, sur Hicel STAR 1 (Android 12), Ouagadougou — historique affichant
  `Coord. (adresse) : Piis Zuure, Tampouy, Ouagadougou, Centre` au-dessus de
  `12.3855, -1.5700`.
- **Preuve** : [`docs/preuves/ISS-10_adresse.png`](../preuves/ISS-10_adresse.png),
  jointe au commentaire du 26/10/2026 sur [#25](https://github.com/yele-bf/mobilefront/issues/25).

## Limites

- Nominatim est un service public gratuit : hors ligne, ou si le quota est
  atteint, seule la coordonnée s'affiche — c'est le repli prévu.
- Aucune adresse n'est stockée avec la mesure : la résolution se fait à
  l'affichage, donc une mesure peut afficher une adresse au premier dépliage
  et la même adresse ensuite depuis le cache.
- Hors Burkina Faso, l'adresse n'est jamais résolue (choix assumé, cohérent
  avec le périmètre du projet).
- La capture du 25/10 porte 12.3855 / −1.5700, et non 12,3657 / −1,5339 comme
  le relevé annoncé le 24/10 : deux points de mesure différents dans
  Ouagadougou, la précision du géocodage varie avec le point.
