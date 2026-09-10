# Yélé — Application mobile

Application Flutter de mesure de la qualité des réseaux mobiles au Burkina Faso.
Elle mesure le débit, la latence, la qualité du streaming vidéo et le temps de
chargement des pages web, puis remonte chaque mesure géolocalisée vers le
backend Yélé. Ces mesures alimentent la carte publique de couverture.

---

## Le projet Yélé en un coup d'œil

Yélé est composé de quatre dépôts indépendants :

| Dépôt | Rôle | Techno |
|---|---|---|
| **`mobilefront`** *(ce dépôt)* | Application mobile : réalise les mesures sur le terrain | Flutter / Dart |
| `mobiletest` | Backend : serveur de speedtest, réception des mesures, API du tableau de bord | Go + MongoDB |
| `new_web` | Tableau de bord public : carte, statistiques, comparaison des opérateurs | HTML/CSS/JS |
| `ai` | Micro-service d'analyse : détection d'anomalies et prévision de qualité | Python / FastAPI |

Le parcours d'une mesure :

```
  [ Application mobile ]                   ce dépôt
       |
       |  1. mesure le débit contre le serveur (/garbage, /empty)
       |  2. envoie le résultat + contexte (opérateur, GPS, techno radio)
       v
  POST /results/telemetry
       |
       v
  [ Backend Go ] ---- stocke ----> [ MongoDB Atlas ]
       |                                  ^
       |  GET /api/dashboard/*            | lit les mesures
       v                                  |
  [ Tableau de bord web ]           [ Service IA ]
```

---

## Prérequis

- **Flutter SDK >= 3.12** (canal stable) — vérifier avec `flutter --version`
- **Android Studio** ou le SDK Android en ligne de commande
- Un appareil Android physique **recommandé** : un émulateur ne donne ni signal
  radio réel, ni opérateur SIM, ni position GPS crédible — les mesures y sont
  donc peu représentatives.
- iOS n'est pas pris en charge pour la collecte en arrière-plan (voir plus bas).

## Démarrage rapide

```bash
git clone <url-du-depot>
cd mobilefront

flutter pub get

# Génère le code Hive (modèle de stockage local)
dart run build_runner build --delete-conflicting-outputs

flutter run
```

L'application pointe par défaut sur le backend de démonstration hébergé sur
Render. Aucune configuration n'est nécessaire pour un premier lancement.

## Configuration

Tout est centralisé dans **`lib/constants/config.dart`**.

| Constante | Rôle | Défaut |
|---|---|---|
| `API_BASE_URL` | URL du backend Go | `https://mobiletest-j0c6.onrender.com` |
| `SPEED_PHASE_DURATION_SEC` | Durée d'une phase de mesure de débit | `10` s |
| `SPEED_WARMUP_MS` | Montée en charge exclue du calcul | `1000` ms |
| `STREAMING_YOUTUBE_VIDEO_ID` | Vidéo de référence du test streaming | `aqz-KE-bpKQ` |
| `BROWSING_REFERENCE_PAGES` | Pages du test de navigation | 6 sites dont `lefaso.net` |
| `BACKGROUND_DEFAULT_INTERVAL_MIN` | Cadence de la collecte passive | `15` min |

Pour pointer sur un backend local ou temporairement exposé :

```dart
const String API_BASE_URL = 'http://10.0.2.2:8989';  // émulateur Android
// const String API_BASE_URL = 'http://192.168.1.42:8989';  // appareil physique
// const String API_BASE_URL = 'https://wilder-heaviness-fabulous.ngrok-free.dev';  // tunnel ngrok local
```

> `10.0.2.2` est l'adresse par laquelle l'émulateur Android voit la machine
> hôte. Depuis un téléphone réel, il faut l'adresse IP de la machine sur le
> réseau local.
>
> Le tunnel ngrok est utile pour que le dashboard local et l'app mobile
> appellent le backend via internet sans exposer durablement le backend local.
> Dans ce cas, nginx continue de servir le dashboard, et le mobile pointe
> directement sur l'URL ngrok.

## Structure du code

```
lib/
├── main.dart                    Point d'entrée, définition des routes
├── constants/
│   ├── config.dart              TOUTE la configuration (URL, seuils, cadences)
│   └── app_colors.dart          Palette et styles de texte
├── models/
│   ├── speed_test_result.dart   Modèle principal (persisté via Hive)
│   └── test_selection.dart      Quels tests lancer (débit / streaming / web)
├── screens/
│   ├── full_test_screen.dart    Écran de test — paramétré par TestSelection
│   ├── score_screen.dart        Résultat détaillé
│   ├── history_screen.dart      Historique local
│   ├── coverage_screen.dart     Carte de couverture
│   └── settings_screen.dart     Réglages + pilotage de la collecte passive
├── services/
│   ├── speed_test_api_service.dart         Moteur de mesure du débit
│   ├── streaming_test_service.dart         Test de streaming YouTube
│   ├── browsing_test_service.dart          Test de navigation web
│   ├── background_collection_service.dart  Pont vers le service Android
│   ├── network_info_service.dart           Opérateur, techno radio, signal
│   ├── location_service.dart               Position GPS
│   └── local_storage_service.dart          Persistance Hive
└── widgets/                     Composants réutilisables

android/app/src/main/kotlin/com/yele/mobilefront/
├── MainActivity.kt              Canal de méthode `com.yele/telephony`
├── SignalCollectorService.kt    Collecte passive (service de premier plan)
└── BootReceiver.kt              Relance la collecte au redémarrage
```

---

## Comprendre les trois moteurs de mesure

### 1. Le débit — `speed_test_api_service.dart`

La mesure se fait sur une **durée fixe (10 s)** et non sur une taille de fichier
fixe. C'est un choix délibéré : sur un lien rapide, quelques mégaoctets sont
transférés en une fraction de seconde, ce qui ne mesure que le démarrage lent de
TCP et ne laisse rien voir à l'écran.

Deux précautions donnent des chiffres comparables d'un test à l'autre :

- La **première seconde est exclue** du calcul (`SPEED_WARMUP_MS`) : c'est la
  montée en charge de TCP, elle sous-estime systématiquement le débit réel.
- Une **pause de 1,2 s** sépare la fin de l'upload de la mesure de latence
  (`LATENCY_SETTLE_MS`), le temps que les files d'attente du réseau se vident.
  Sans elle, le ping mesuré est celui d'un réseau saturé par le test lui-même
  (bufferbloat), pas celui du réseau au repos.

### 2. Le streaming — `streaming_test_service.dart`

Plutôt que d'estimer la qualité vidéo à partir du débit, le test **lit réellement
une vidéo YouTube** dans une WebView via l'IFrame Player API. Il demande
successivement 720p, 1080p puis 2160p et mesure ce que le réseau tient
effectivement : temps de démarrage, nombre de coupures, résolution maximale
atteinte. C'est l'approche utilisée par nPerf.

> La vidéo de référence **doit** être disponible en 2160p, sinon la colonne 4K
> restera systématiquement vide. Vérifier `STREAMING_YOUTUBE_VIDEO_ID` avant
> toute mise en production.

### 3. La navigation web — `browsing_test_service.dart`

Charge six pages de référence et mesure le temps de chargement, selon le critère
ARCEP : une page est considérée correctement chargée en **moins de 10 secondes**.

---

## La collecte passive en arrière-plan

C'est la brique qui permet de construire une véritable carte de couverture.

**Le problème.** Un speedtest complet consomme plusieurs dizaines de mégaoctets.
Personne ne peut en lancer un toutes les quinze minutes. Or une carte de
couverture a besoin de beaucoup de points, régulièrement.

**La solution.** Une relève passive enregistre uniquement la position, la
technologie radio, l'opérateur et la puissance du signal — **sans mesure de
débit**. Elle pèse environ un kilo-octet. La cadence peut donc être élevée sans
peser sur le forfait de l'utilisateur.

**L'implémentation.** Le code vit dans un service Android de premier plan
(`SignalCollectorService.kt`) et non dans un isolate Dart, pour deux raisons :
`TelephonyManager` et le fournisseur de position sont des API Android natives,
et un isolate d'arrière-plan entrerait en conflit avec la base Hive de
l'interface.

La notification permanente n'est pas décorative : Android l'impose en
contrepartie du droit de tourner en continu, et elle donne à l'utilisateur le
moyen d'arrêter la collecte à tout moment.

**Limites connues.**

- **Android uniquement.** iOS n'autorise aucune exécution périodique garantie en
  arrière-plan. `BackgroundCollectionService.isSupported` renvoie `false` ailleurs.
- Les gestionnaires de batterie agressifs (Xiaomi, Huawei, Samsung) tuent le
  service malgré son statut de premier plan. C'est pourquoi l'état distingue
  `enabled` (l'utilisateur a activé) de `running` (le service tourne vraiment) :
  `CollectStatus.wasKilled` permet de le signaler honnêtement à l'utilisateur
  plutôt que d'afficher un état faux.

### Permissions Android

| Permission | Pourquoi |
|---|---|
| `INTERNET`, `ACCESS_NETWORK_STATE`, `ACCESS_WIFI_STATE` | Mesures et type de connexion |
| `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION` | Géolocaliser chaque mesure |
| `READ_PHONE_STATE` | Opérateur SIM et technologie radio |
| `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_LOCATION` | Collecte passive |
| `POST_NOTIFICATIONS` | Notification permanente imposée par Android |
| `RECEIVE_BOOT_COMPLETED` | Relancer la collecte après redémarrage |

---

## Compilation

```bash
flutter build apk --release            # APK universel
flutter build appbundle --release      # Bundle pour le Play Store
```

L'intégration continue est décrite dans **`codemagic.yaml`** (Codemagic).
Identifiant d'application : `com.yele.mobilefront`.

## Tests

```bash
flutter test
flutter analyze
```

> La couverture de tests est actuellement minimale (`test/widget_test.dart`).
> C'est le premier chantier ouvert aux contributions.

---

## Contribuer

Les contributions sont bienvenues. Quelques pistes concrètes :

- Étoffer les tests, en particulier autour des services de mesure.
- Support iOS pour les tests actifs (la collecte passive restera hors de portée).
- Traduction de l'interface (actuellement en français uniquement).
- Consolider la table MCC+MNC vers nom d'opérateur, aujourd'hui **dupliquée**
  entre `SignalCollectorService.kt` et `NetworkInfoService` côté Dart. Si un
  opérateur change, il faut penser aux deux endroits.

Merci d'ouvrir une *issue* décrivant le problème avant une *pull request*
importante.

## Licence

À définir avant l'ouverture publique du dépôt. Voir la note du dépôt
`mobiletest`, qui hérite de la licence LGPL-3.0 de LibreSpeed.
