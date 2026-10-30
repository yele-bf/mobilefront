# IMP-09 — Baromètre : se comparer aussi aux clients de son opérateur

| Champ | Valeur |
|---|---|
| Dépôts | `mobilefront`, `mobiletest` |
| Issue | [#15](https://github.com/yele-bf/mobilefront/issues/15) |
| Priorité / vague | P3 / V5 Dashboard & référentiel |
| Owner au classeur | SANOU Zossoun Aristide Daouda / SANNA Abdoul Salam |
| Branche | `imp/IMP-09-barometre-operateur` (même nom dans les deux dépôts) |
| Validation imposée | Local + données multi-utilisateurs |

## Constat et impact

Le baromètre existant (`16d2a89`, `836b4cf`) situait le résultat parmi
**toutes** les mesures de la base. Le classeur demande aussi la comparaison
« par opérateur ». Or un client Orange se compare d'abord aux autres clients
Orange : un centile national mélange des réseaux, des technologies et des
fournisseurs Wi-Fi très différents. De plus, les libellés d'opérateurs sont
hétérogènes dans la base (« Orange BF », « Orange Burkina Faso », « 61302 »),
ce qui empêchait de les regrouper.

## Correction

**Serveur (`mobiletest`)**

- `database/mongodb/barometer.go` (nouveau) :
  - `barometerFrom()` calcule, sur les documents chargés, les centiles
    nationaux (inchangés), la moyenne nationale et, si un opérateur est
    fourni, les mêmes centiles et la moyenne parmi ses seuls clients. Au moins
    5 mesures sont exigées pour cette partie. La fonction est isolée de
    MongoDB pour être testée.
  - `operatorFamily()` unifie les libellés : Orange, Moov Africa (Moov, ONATEL,
    Telmob, 61301), Telecel. Un autre fournisseur garde son libellé.
  - L'opérateur d'une mesure est celui de la SIM s'il est connu, sinon le
    fournisseur d'accès.
- `database/mongodb/mongodb.go` : `FetchBarometer` prend un paramètre
  `operator`, lit aussi `operator` et `sim_operator`, et délègue le calcul à
  `barometerFrom`. `BarometerResult` reçoit de nouveaux champs, tous
  optionnels, donc les anciennes versions de l'app ne sont pas affectées.
- `results/barometer.go` : paramètre de requête `operator`.

**Application (`mobilefront`)**

- `lib/services/dashboard_api_service.dart` :
  - `fetchBarometer(..., operator:)` ;
  - nouveaux champs de `BarometerResult` et `hasOperatorComparison` ;
  - `barometerOperatorOf()` choisit l'opérateur transmis : la SIM en données
    mobiles, le fournisseur d'accès en Wi-Fi.
- `lib/screens/score_screen.dart` : sous les trois jauges nationales, un bloc
  « Parmi les clients <opérateur> » avec trois jauges (Download, Upload,
  Latence), le nombre de mesures et la ligne « Débit moyen ▼ : vous · opérateur
  · toutes mesures ».

## Critère d'acceptation

Après un test, le baromètre affiche la position relative du résultat parmi
toutes les mesures et parmi les clients du même opérateur.

## Validation

- **Automatisée** :
  - **Serveur** : `TestBarometerFromParOperateur` (10 mesures, 4 opérateurs,
    libellés hétérogènes ; vérifie les centiles nationaux et Orange et les
    moyennes), `TestBarometerFromSansComparaisonOperateur` (sans opérateur ;
    moins de 5 mesures) et `TestOperatorFamily`.
  - **App** : `test/barometre_operateur_test.dart` vérifie :
    - la lecture de la réponse complète et d'une ancienne réponse ;
    - le seuil de 5 mesures ;
    - le choix entre opérateur de la SIM et fournisseur d'accès.

  Ces tests sont exécutés par les checks `build` et `android` : pas de chaîne
  Flutter ni Go sur le poste de l'agent.
- **Support imposé (Local + données multi-utilisateurs)** : non réalisé à la
  date de la PR. Il faut un backend local avec plusieurs utilisateurs et
  opérateurs : un test, puis une capture de la carte « Baromètre ».
- **Preuve** : à verser dans `docs/preuves/IMP-09/`.

## Limites connues

- Le calcul porte toujours sur les 5 000 dernières mesures actives, comme
  avant ; la comparaison par opérateur est donc limitée à cet échantillon.
- La comparaison par opérateur ne distingue pas la technologie (2G / 3G / 4G).
- La carte du baromètre garde son fond blanc d'origine en thème sombre : ce
  point n'est pas modifié ici.
