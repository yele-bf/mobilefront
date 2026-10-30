# IMP-14 — Conditions d'utilisation à accepter au premier lancement

| Champ | Valeur |
|---|---|
| Dépôt | `mobilefront` |
| Issue | [#27](https://github.com/yele-bf/mobilefront/issues/27) |
| Priorité / vague | P3 / V1 Quick wins |
| Owner au classeur | SANOU Zossoun Aristide Daouda |
| Branche | `imp/IMP-14-conditions-utilisation` |
| Validation imposée | Chrome + APK |

## Constat et impact

À la première ouverture, l'application lançait directement l'écran de test,
sans rien dire de son usage ni des données qu'elle collecte. Pourtant, chaque
test envoie au serveur la position GPS, l'adresse IP, l'opérateur, le modèle de
l'appareil et un identifiant. Google Play exige d'ailleurs une divulgation
explicite et un accord avant toute collecte de localisation.

## Correction

- `lib/services/consent_service.dart` (nouveau) : accord **versionné**
  (`termsVersion = 1`) et daté, gardé dans une boîte Hive dédiée (`consent`).
  Si le stockage est illisible, `hasAccepted` vaut faux : mieux vaut redemander
  l'accord que mesurer sans. Pour redemander l'accord à tous, il suffit
  d'incrémenter la version quand les données collectées changent.
- `lib/screens/consent_screen.dart` (nouveau) : écran bloquant du premier
  lancement. Il résume les données envoyées à chaque test, renvoie au texte
  complet et propose « J'accepte et je continue » ou « Refuser et quitter ».
  Refuser ferme l'application : sans envoi au serveur, aucune fonction de Yélé
  n'a de sens. Après l'accord, l'écran ouvert est le test par défaut des
  réglages.
- `lib/constants/conditions_utilisation.dart` et
  `lib/screens/conditions_screen.dart` (nouveaux) : texte complet. Il couvre
  l'objet de l'application et les conditions d'utilisation (gratuité, données
  consommées, résultats indicatifs, usage loyal, localisation obligatoire), les
  données envoyées, la collecte en arrière-plan facultative, ce qui n'est pas
  collecté, l'usage des données, les services tiers et les droits. Les services
  tiers sont ceux que le code de `main` appelle réellement :
  - le serveur Render ;
  - OpenStreetMap et Nominatim ;
  - YouTube, ou la vidéo de test HLS sur Netlify avec jsDelivr ;
  - les sites du test de navigation.
- `lib/main.dart` : `ConsentService` est ouvert au démarrage ; `YeleApp` démarre
  sur `/consent` tant que l'accord manque. Ajout des routes `/consent` et
  `/conditions`. Le paramètre `hasAccepted` vaut vrai par défaut, pour que les
  tests de widgets existants, qui ne passent pas par `main()`, restent
  inchangés.
- `lib/screens/settings_screen.dart` : deux entrées dans « Assistance » :
  - « Conditions d'utilisation » relit le texte ;
  - « Retirer mon accord » demande confirmation puis renvoie aux conditions,
    en vidant la pile de navigation.

## Critère d'acceptation

À la première ouverture, l'application montre les conditions d'utilisation de
Yélé et n'en sort que par l'acceptation. Aux ouvertures suivantes, elle s'ouvre
directement sur le test.

## Validation

- **Automatisée** : `test/consent_test.dart` (nouveau) :
  - pas d'accord au premier lancement ;
  - accord conservé après fermeture et réouverture de la boîte ;
  - retrait qui redemande l'accord ;
  - sans accord, l'app s'ouvre sur les conditions et non sur « Test complet ».

  Ce test, avec `flutter analyze` et la compilation de l'APK, est exécuté par
  les checks `build` et `android` de la PR : aucune chaîne Flutter n'était
  disponible sur le poste de l'agent.
- **Support imposé par le classeur (Chrome + APK)** : non réalisé à la date de
  la PR. À faire avec l'APK de debug produit par le check `android` :
  1. installer l'APK sur un téléphone, ouvrir l'app et capturer l'écran des
     conditions ;
  2. accepter, fermer l'app, la rouvrir et vérifier qu'elle s'ouvre
     directement sur le test ;
  3. faire de même dans Chrome.
- **Preuve** : à verser dans `docs/preuves/IMP-14/` avant de passer l'item en
  `Validé`.

## Limites connues

- Validation sur Chrome et sur APK non faite (voir ci-dessus) : l'item reste
  `En cours` au registre.
- Le bouton « Refuser et quitter » appelle `SystemNavigator.pop()`. Sur le web
  (Chrome), il ne ferme pas l'onglet : l'utilisateur reste sur l'écran des
  conditions, ce qui garde la collecte bloquée.
- Le texte est en français seulement : la traduction relève d'IMP-02 (langue).
- La collecte en arrière-plan n'est pas encore conditionnée à l'accord dans le
  code : elle n'est jamais lancée au démarrage dans `main`, et le texte la
  présente comme facultative.
