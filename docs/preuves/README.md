# Preuves de validation terrain — groupe 2

Captures d'écran produites le **25/10/2026** par SAWADOGO Hassan Achraf Ammar
(`aspinfo10`) pour satisfaire la colonne « Validation / test » du classeur V14
sur les quatre items du groupe 2, tous fusionnés dans `main` le 24/10/2026 :

| Item | Issue | PR | Commit de merge |
|---|---|---|---|
| ISS-01 | [#18](https://github.com/yele-bf/mobilefront/issues/18) | [#31](https://github.com/yele-bf/mobilefront/pull/31) | `96b75e8` |
| ISS-03 | [#20](https://github.com/yele-bf/mobilefront/issues/20) | [#32](https://github.com/yele-bf/mobilefront/pull/32) | `5b98edf` |
| ISS-07 | [#23](https://github.com/yele-bf/mobilefront/issues/23) | [#33](https://github.com/yele-bf/mobilefront/pull/33) | `93d6a33` |
| ISS-10 | [#25](https://github.com/yele-bf/mobilefront/issues/25) | [#34](https://github.com/yele-bf/mobilefront/pull/34) | `8f610f5` |

Chaque image porte un bandeau qui dit ce qu'elle prouve et encadre en rouge la
ligne concernée. Les originaux non annotés ne sont **pas** joints : voir
« Ce qui ne figure pas dans ce dossier ».

## Les six fichiers

| Fichier | Item | Ce que la capture montre | Ce qu'elle ne montre pas |
|---|---|---|---|
| `ISS-01_4G_RSRP-RSRQ.png` | ISS-01 | Deux lignes distinctes dans l'historique : `Signal : RSRP -106 dBm (Mauvais/Faible)` et `Qualité du signal : RSRQ -20 dB`, avec `Réseau mobile : 4G · Orange BF · SIM 1` | la 5G : aucune cellule 5G dans la zone (voir « 5G ») |
| `ISS-03_Wi-Fi_sans-reseau-mobile.png` | ISS-03 | Test en Wi-Fi, données mobiles actives (deux icônes 4G en barre d'état) : **aucune** ligne « Réseau mobile » dans l'historique, alors que le bloc affiche bien `FAI` | l'écran de bilan (capture suivante, dédiée) |
| `ISS-03_4G_reseau-mobile.png` | ISS-03 | Contre-épreuve en données mobiles : `Réseau mobile : 4G · Orange BF · SIM 1` | — |
| `ISS-03_bilan-Wi-Fi_reseau-mobile-vide.png` | ISS-03 | Écran de **bilan** en Wi-Fi : `Connexion WiFi`, `FAI : Orange Burkina Faso`, `Réseau mobile : —`, SIM 4G pourtant enregistrée | — |
| `ISS-10_adresse.png` | ISS-10 | `Coord. (adresse) : Piis Zuure, Tampouy, Ouagadougou, Centre`, au-dessus de `12.3855, -1.5700` | une adresse hors de cette zone |
| `ISS-07_HLS_trois-paliers.png` | ISS-07 | Tableau HLS à trois colonnes, 720p / 1080p / 2160p, avec le débit mini requis par palier | un passage en Chrome (non fourni, voir plus bas) |

### Détail chiffré de la capture ISS-07

| Palier | Qualité servie | Débit mesuré | Débit mini requis | Score |
|---|---|---|---|---|
| 720p | 89,31 % | 5 962 kiB | ≥ 0,65 Mb/s | 77 / 100 |
| 1080p | 91,98 % | 9 912 kiB | ≥ 0,99 Mb/s | (idem) |
| 2160p | 48,06 % | 16 915 kiB | ≥ 2,83 Mb/s | (idem) |

Les trois « débit mini requis » se recalculent depuis le code de `main` :
`minRequiredKbpsFor(bandwidth, segmentSec: 4, timeoutSec: 20, margin: 1.15)` sur
les `BANDWIDTH` du manifeste public
(`https://yele-test-assets.netlify.app/bbb/master.m3u8` → 2 817 071 / 4 317 071 /
12 317 071 b/s) donne 648 / 993 / 2 833 kb/s, soit 0,65 / 0,99 / 2,83 Mb/s. La
capture est donc cohérente avec le build de `main` et non avec un autre.

## Provenance déclarée

| Build | Utilisé pour | SHA-256 déclaré |
|---|---|---|
| `yele-2.0.0-2-main-8a256ff.apk` | captures 4G et Wi-Fi (ISS-01, ISS-03) | `cd025644d69edd79aa00ee98fa30124f78b3de45dba83092899287a71cc6261f` |
| `app-release.apk`, moteur HLS par défaut | captures ISS-07 et ISS-03 (bilan), sur le STAR 1 | `c3aef74981ea746e2ca744cec2580a2a7db1574b35c7da97976430d2920603aa` |

Déclaré par l'auteur : `com.yele.mobilefront`, versionName 2.0.0 /
versionCode 2, construits depuis `main` = `8a256ff` (les quatre fusions #32,
#31, #34, #33), signés avec la clé debug ; appareil **Hicel STAR 1**
(Android 12), Orange Burkina Faso, Tampouy / Ouagadougou, le 25/10/2026.

Les deux APK ne sont pas joints et les empreintes ne peuvent pas être
recalculées après coup : ce tableau rapporte une déclaration de l'auteur, pas
une vérification indépendante. Ce qui **a** été vérifié indépendamment, c'est le
contenu des captures : les libellés, les valeurs et les débits mini requis
correspondent au code de `main` (voir ci-dessus).

## 5G

Il n'existe **aucun réseau 5G commercial au Burkina Faso** à la date du test ;
la 5G n'y fait l'objet que d'essais. En 5G NSA, l'ancre reste LTE : les champs
`signalNrRsrp` / `signalNrRsrq` restent vides et ce sont les champs LTE qui sont
renseignés — c'est le comportement attendu de ISS-01, pas un défaut. La capture
4G satisfait donc la colonne « APK réel 4G/5G (terrain) » du classeur.

## Ce qui ne figure pas dans ce dossier

- **Les originaux non annotés** : une première version du README annonçait un
  dossier `sources/` (quatre JPEG/PNG plus trois captures d'émulateur). Ce
  dossier n'a jamais été poussé ; il a été retiré de ce README plutôt que
  laissé en référence morte. Si les originaux arrivent, ils vont dans
  `docs/preuves/sources/` et cette section est mise à jour.
- **Un passage en Chrome pour ISS-07** : le classeur écrit « Chrome + APK » ;
  seul l'APK a été fourni. Décision du 26/10 : un seul support suffit dès lors
  qu'il prouve le critère (voir `CONTRIBUTING` §6.1).
- **Les APK** eux-mêmes, seulement leurs empreintes déclarées.

## Comment citer une preuve

Chemin dans le dépôt (stable une fois fusionné dans `main`) :

```
docs/preuves/ISS-01_4G_RSRP-RSRQ.png
docs/preuves/ISS-03_Wi-Fi_sans-reseau-mobile.png
docs/preuves/ISS-03_4G_reseau-mobile.png
docs/preuves/ISS-03_bilan-Wi-Fi_reseau-mobile-vide.png
docs/preuves/ISS-07_HLS_trois-paliers.png
docs/preuves/ISS-10_adresse.png
```

La branche `docs/preuves-groupe2` est **conservée** après fusion : les liens
`raw.githubusercontent.com/…/docs/preuves-groupe2/…` publiés dans les issues
#18, #20, #23 et #25 le 26/10/2026 continuent de résoudre. Ne pas la supprimer.
