# Preuves — IMP-03 (comptes utilisateurs)

Captures fournies par l'owner de l'item, SANOU Zossoun Aristide Daouda, le 30/10/2026,
prises sur l'application Android (APK de debug).

| Fichier | Ce que la capture montre |
|---|---|
| `IMP-03_01_menu-mon-compte.jpeg` | L'entrée « Mon compte » dans le menu latéral de l'application. |
| `IMP-03_02_connexion.jpeg` | L'écran « Se connecter » : e-mail, mot de passe, « Pas de compte ? En créer un ». |
| `IMP-03_03_selection-compte-google.jpeg` | La feuille de sélection de compte ouverte depuis le bouton Google. |
| `IMP-03_04_creation-de-compte.jpeg` | L'écran « Créer un compte » : nom facultatif, e-mail, mot de passe (8 caractères au moins), « J'ai déjà un compte ». |

## Ce que ces captures attestent

L'espace de gestion de compte demandé par le classeur existe et est atteignable :
création de compte, connexion, et sélection d'un fournisseur d'identité.

## Réserves

- Les captures montrent un bouton **« Continuer avec Google »** et un texte d'introduction
  (« …sur un nouveau téléphone… ») qui **ne sont pas dans le code de cette branche** :
  `lib/screens/account_screen.dart` n'a aucune occurrence de « Google », et `google_sign_in`
  n'est déclaré dans aucun `pubspec.yaml` du dépôt. La connexion Google est donc explicitement
  hors périmètre de cette PR ; les captures proviennent d'une build locale qui la contient.
  À reproduire après fusion sur la build de `main` si l'on veut une preuve strictement
  conforme au code livré.
- La méthode de test du classeur — « créer plusieurs comptes et vérifier l'isolation des
  historiques » — **n'est pas photographiée**. Elle est couverte par `test/account_test.dart`
  (deux comptes puis aucun compte : seules les mesures du compte connecté, ou les mesures
  anonymes, apparaissent).
- Aucune capture du parcours serveur (`/api/me/results`) : le backend n'était pas disponible
  sur le poste de l'agent au moment de la validation.
