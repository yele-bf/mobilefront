# IMP-03 — Comptes utilisateurs et historiques isolés

| Champ | Valeur |
|---|---|
| Dépôts | `mobiletest`, `mobilefront` |
| Issue | [#9](https://github.com/yele-bf/mobilefront/issues/9) |
| Priorité / vague | P3 / V6 Évolutions lourdes |
| Owner au classeur | SANOU Zossoun Aristide Daouda / SANNA Abdoul Salam |
| Branche | `imp/IMP-03-comptes` (même nom dans les deux dépôts) |
| Validation imposée | Local (backend + app) |

## Constat et impact

Aucun espace n'existait pour gérer un compte. Les mesures n'étaient rattachées
qu'à un appareil, et plusieurs personnes qui partagent un téléphone voyaient le
même historique. Un utilisateur qui change de téléphone perdait aussi le lien
avec ses mesures.

## Correction

**Serveur (`mobiletest`)**

- `database/mongodb/accounts.go` (nouveau) : collections `users` et
  `sessions`.
  - **Mots de passe** : PBKDF2-SHA256, 600 000 itérations et un sel aléatoire
    par compte (recommandation OWASP), comparés en temps constant. Un e-mail
    inconnu déclenche un calcul factice, pour ne pas révéler quels e-mails ont
    un compte.
  - **Sessions** : jeton aléatoire de 32 octets remis à l'app ; seule son
    empreinte SHA-256 est stockée. Expiration après 90 jours par index TTL,
    e-mail unique par index.
  - **Suppression du compte** : les sessions sont supprimées et les mesures
    sont détachées du compte (rendues anonymes), mais restent sur la carte.
- `results/auth.go` (nouveau) :
  - `POST /api/auth/register` (e-mail valide, mot de passe de 8 à
    128 caractères) ;
  - `POST /api/auth/login` et `POST /api/auth/logout` ;
  - `GET`, `PUT` et `DELETE /api/me` ;
  - `GET /api/me/results` (mesures du seul compte, paginées).
- `results/ratelimit.go` (nouveau) : 20 tentatives d'inscription ou de
  connexion par IP et par 10 minutes. La limite reste large à cause du CGNAT
  des opérateurs.
- `results/telemetry.go` : un test envoyé avec `Authorization: Bearer` est
  rattaché au compte (`Document.UserID`, `user_id`, jamais renvoyé par l'API).
- `database/mongodb/mongodb.go` crée les index des comptes à l'ouverture ;
  `database/schema/schema.go` ajoute `UserID` ; `web/web.go` déclare les
  routes et autorise PUT et DELETE en CORS.

**Application (`mobilefront`)**

- `lib/services/account_service.dart` (nouveau) : inscription, connexion,
  déconnexion, modification du nom, suppression, nombre de mesures sur le
  serveur. La session est gardée dans la boîte Hive `account`, et
  `AccountService.current` est un `ValueNotifier` que les écrans écoutent.
  Les codes d'erreur sont traduits en messages lisibles.
- `lib/screens/account_screen.dart` (nouveau) : écran « Mon compte » (menu
  latéral). Déconnecté, il montre les formulaires de connexion et de création ;
  connecté, il montre le profil, les mesures rattachées, la déconnexion et la
  suppression.
- `lib/services/speed_test_api_service.dart` : chaque test porte
  `accountId`, et le jeton est joint à l'envoi.
- `lib/models/speed_test_result.dart` et `.g.dart` : `accountId`
  (`@HiveField(59)` ; 52 à 58 sont réservés à IMP-07 et ISS-06).
- `lib/screens/history_screen.dart` : l'historique n'affiche que les mesures
  du compte connecté ou, déconnecté, celles faites sans compte.
- `lib/main.dart` et `lib/widgets/yele_drawer.dart` : session rechargée au
  démarrage, route `/account` et entrée « Mon compte » dans le menu.

## Critère d'acceptation

Un utilisateur crée un compte ou s'y connecte, et retrouve les mesures
associées : celles de son historique et le nombre de mesures rattachées sur le
serveur. Deux comptes sur le même téléphone ont des historiques séparés.

## Validation

- **Automatisée** :
  - **Serveur** :
    - `TestHashPasswordDeterministicPerSalt` ;
    - `TestTokenHashHidesToken` ;
    - `TestNormalizeEmail` ;
    - `TestRateLimiter` (limite, autre IP, fenêtre suivante) ;
    - `TestValidEmail` ;
    - `TestBearerToken`.
  - **App** : `test/account_test.dart` vérifie :
    - l'état anonyme ;
    - la session mémorisée puis rechargée au lancement suivant ;
    - l'isolation des historiques (Awa, Ali, sans compte) ;
    - la persistance de `accountId` ;
    - les messages d'erreur.

  Ces tests sont exécutés par les checks `build` et `android` : pas de chaîne
  Flutter ni Go sur le poste de l'agent.
- **Support imposé (Local, backend + app)** : non réalisé à la date des PR. À
  faire :
  1. démarrer le backend avec MongoDB en local ;
  2. créer deux comptes depuis l'app et faire un test avec chacun ;
  3. vérifier que chaque historique ne montre que ses mesures, et que
     `/api/me/results` ne renvoie que celles du compte.
- **Preuve** : à verser dans `docs/preuves/IMP-03/`.

## Limites connues

- La connexion avec Google n'est pas incluse. Elle demande un client OAuth
  Android lié à l'empreinte SHA-1 de la clé de signature de l'APK publiée, ce
  qui n'est pas disponible avec la clé de debug de la CI. Elle fera l'objet
  d'une contribution séparée.
- L'historique filtre les mesures sur le téléphone : les mesures d'un compte
  faites sur un autre téléphone ne sont pas encore téléchargées dans
  l'historique, seul leur nombre est affiché.
- Pas de récupération de mot de passe oublié : il faudrait un envoi d'e-mails.
- Si IMP-14 (conditions d'utilisation) est fusionnée, son texte doit être
  complété : « Yélé ne collecte pas votre adresse e-mail » n'est vrai que sans
  compte.
