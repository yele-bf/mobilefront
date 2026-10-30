# Preuves — IMP-14 (conditions d'utilisation au premier lancement)

Captures fournies par l'owner de l'item, SANOU Zossoun Aristide Daouda, sur un
téléphone Android (APK de debug produit par le check `android`), en thème sombre.

| Fichier | Ce qu'il montre |
|---|---|
| `IMP-14_01_ecran-avant-de-commencer.jpeg` | L'écran bloquant à la première ouverture : résumé des données envoyées, lien « Lire la politique de confidentialité », boutons « J'accepte et je continue » et « Refuser et quitter ». |
| `IMP-14_02_politique-haut-du-texte.jpeg` | Haut de la politique : « Dernière mise à jour : 15 octobre 2026 (v2) », « Qui sommes-nous », « Données collectées lors d'un test », début de « Collecte en arrière-plan ». |
| `IMP-14_03_politique-donnees-et-collecte.jpeg` | Suite : collecte en arrière-plan, « Compte (facultatif) », « Ce que Yélé ne collecte pas », « Utilisation des données ». |
| `IMP-14_04_politique-exclusions.jpeg` | Exclusions (téléphone, nom, e-mail sans compte, contacts, IMEI, publicité), utilisation des données, services tiers. |
| `IMP-14_05_politique-services-et-droits.jpeg` | Services tiers (Render/MongoDB Atlas, OpenStreetMap, YouTube et sites du test de navigation) et « Vos choix et vos droits » (refus, retrait de l'accord, effacement de l'historique, localisation). |

Les captures 02 à 05 se recouvrent : elles suivent le défilement du texte, sans
mise en page différente.

## Ce que ces captures ne montrent pas

- **Aucune capture Chrome** : le classeur demande « Chrome + APK », seule la
  moitié APK est couverte ici.
- **Aucune capture de la réouverture** : l'absence de l'écran aux lancements
  suivants après acceptation, et le retour de l'écran après « Retirer mon
  accord », ne sont attestés que par `test/consent_test.dart` (4 cas), pas par
  une image.
- Aucune capture de « Réglages → Assistance → Conditions d'utilisation ».
