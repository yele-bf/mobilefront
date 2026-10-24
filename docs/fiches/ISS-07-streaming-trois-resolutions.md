# ISS-07 — Test streaming simultané (720p, 1080p et 2160p) manquant

| Champ | Valeur |
|---|---|
| Dépôt | `mobilefront` |
| Issue | [#23](https://github.com/yele-bf/mobilefront/issues/23) |
| Priorité / vague | P2 / V2 Réseau app (terrain) |
| Owner au classeur | SAWADOGO Hassan Achraf Ammar |
| Branche | `iss/ISS-07-streaming-trois-resolutions` |
| Validation imposée | Chrome + APK |

## Constat et impact

Le test vidéo affichait une image mais ne mesurait qu'une seule qualité : les
trois paliers demandés par le classeur (720p, 1080p, 2160p) n'étaient pas tous
exercés, et rien ne disait quelle qualité avait réellement été servie. La
qualité de service ne pouvait donc pas être évaluée par résolution.

## Correction

**Boucle sur les trois paliers** (`lib/services/streaming_test_service.dart`) —
un lecteur neuf est construit puis détruit pour chaque palier, afin que chaque
mesure parte d'un démarrage à froid ; quatre indicateurs sont relevés par
palier (taux de performance, chargement initial, mise en tampon, données
consommées) et la qualité **réellement servie** est lue
(`getPlaybackQuality`). Si YouTube sert une qualité hors du tableau (par ex.
1440p), la mesure est conservée dans la colonne du palier demandé, avec la
qualité servie affichée : elle n'est plus jetée.

**Moteur HLS verrouillé** (`lib/services/streaming_test_service_hls.dart` +
stub) — `hls.js` avec `currentLevel` fixé, ABR désactivé : le palier servi est
le palier demandé, la mesure devient reproductible. Le flux de test est
auto-hébergé (`streamTestStreamUrl`), construit depuis l'échelle DASH publique
de Big Buck Bunny **sans ré-encodage** (3 variantes 720p/1080p/2160p + audio,
segments fMP4 de 4 s), pour ne pas dépendre d'un backend tiers pendant la
mesure.

**Débit minimal requis** (`lib/constants/config.dart`) — `minRequiredKbpsFor`
applique le `BANDWIDTH` du manifeste, la durée de segment et le timeout de
démarrage (marge ×1,15 pour les pointes d'encodeur). C'est ce qui explique
qu'un 2160p échoue sous ~12,3 Mb/s : un échec de palier n'est plus une panne
silencieuse.

**Choix du moteur à chaud** (`lib/services/streaming_backend_setting.dart`,
`lib/screens/settings_screen.dart`) — surcharge persistée du drapeau compilé
`streamingBackend` (`youtube` par défaut) : on peut comparer les deux moteurs
sur le même appareil sans reconstruire l'application. Une valeur invalide ou
illisible retombe silencieusement sur le défaut.

**Restitution** (`lib/widgets/streaming_table.dart`) — tableau à trois colonnes,
en-tête indiquant la qualité servie (YouTube) ou verrouillée (HLS), et les
quatre indicateurs par palier.

`lib/services/streaming_shared.dart` fournit un hôte local de lecteur, pour que
la page du lecteur ait une origine valide en Web.

## Critère d'acceptation

Un test de streaming est exécuté et son résultat est enregistré.

## Validation

- **Automatisée** : cinq fichiers de tests ajoutés
  (`streaming_backend_setting_test.dart`, `streaming_hls_min_bandwidth_test.dart`,
  `streaming_hls_service_test.dart`, `streaming_result_test.dart`,
  `streaming_score_test.dart`), verts en CI, plus `guard` et le check
  `android`.
- **Support imposé (Chrome + APK)** : l'auteur déclare trois passages (réseau
  limité, moyen, excellent) avec 2160p qui n'aboutit que sur le troisième ; ces
  relevés ne sont pas joints en capture. Statut `Transmis` au registre.

## Limites

- Avec le moteur YouTube, la qualité reste décidée par l'ABR : l'application
  mesure ce qui est servi, elle ne l'impose pas (`setPlaybackQuality` est
  ignoré depuis 2019).
- Le moteur HLS nécessite `hls.js` (Web) et un flux de test accessible : sans
  réseau vers `streamTestStreamUrl`, les paliers échouent.
- Le 2160p dépend du débit disponible (~12,3 Mb/s) : un échec à ce palier sur
  réseau moyen est un résultat, pas une régression.
