# Preuves — IMP-03 (comptes utilisateurs)

## Captures retirées

Les quatre captures qui se trouvaient ici (menu « Mon compte », connexion, sélection
de compte, création de compte) ont été **retirées le 30/10/2026 à la demande de l'owner**,
SANOU Zossoun Aristide Daouda. Elles sont toujours présentes dans l'historique Git
(commits `4c14905`, puis `4be42650` qui en masquait l'adresse e-mail).

Motif : elles provenaient d'une build locale contenant un bouton « Continuer avec Google »
absent du dépôt (aucun `google_sign_in`, aucune occurrence de « Google » dans
`lib/screens/account_screen.dart`), et l'une d'elles affichait une adresse personnelle
dans un dépôt public.

## Statut de l'item

IMP-03 reste **`Validé`** et l'issue `yele-bf/mobilefront#9` reste fermée. L'owner pourra
verser de nouvelles captures dans ce dossier (build de `main`, sur Android et dans Chrome) :
elles seront ajoutées ici et mentionnées au registre, sans rouvrir l'item.

## Ce qui atteste l'item en l'absence de captures

- `test/account_test.dart` (mobilefront) : état anonyme, session mémorisée puis rechargée,
  isolation des historiques entre deux comptes et sans compte, persistance de `accountId`
  (`HiveField(59)`).
- `database/mongodb/accounts_test.go` et `results/auth_test.go` (mobiletest) : hachage
  PBKDF2, empreinte du jeton, limiteur, validation de l'e-mail, en-tête Bearer.
- Le code mergé : `mobilefront#57` → `b29474c`, `mobiletest#19` → `c679e7e`.

## Réserves maintenues

- Le parcours serveur complet (register → login → me → results) n'a pas été rejoué de bout
  en bout : ni MongoDB ni `mongod` sur le poste de relecture.
- La connexion Google n'est pas implémentée dans ce dépôt.
