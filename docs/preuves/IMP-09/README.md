# Preuves — IMP-09 (baromètre par opérateur)

## Ce qui est attendu

Le classeur impose une validation **« Local + données multi-utilisateurs »** : un test réel,
puis la vérification de la position du résultat dans le baromètre, avec un backend contenant
plusieurs utilisateurs et plusieurs opérateurs.

La capture à verser ici doit montrer l'écran de résultat avec :

1. les jauges nationales existantes ;
2. le bloc **« Parmi les clients *&lt;opérateur&gt;* »** avec ses trois jauges (Download,
   Upload, Latence) et le nombre de mesures ;
3. la ligne « Débit moyen ▼ : vous · opérateur · toutes mesures ».

Nom de fichier suggéré : `IMP-09_01_barometre-operateur.jpeg`.

## État actuel

**Aucune capture n'est versée.** L'item est `Validé` au registre sur la base du code mergé et
des tests, avec cette réserve écrite. L'owner (SANOU Zossoun Aristide Daouda) peut déposer les
captures ici **sans rouvrir l'item** ; il suffit d'ajouter le fichier et de compléter le tableau
ci-dessous.

| Fichier | Opérateur | Mesures de l'opérateur | Date |
|---|---|---|---|
| — | — | — | — |

## Ce qui atteste l'item en l'absence de capture

- `test/barometre_operateur_test.dart` (mobilefront) : lecture d'une réponse complète et d'une
  ancienne réponse, seuil de 5 mesures, choix entre opérateur de la SIM et fournisseur d'accès.
- `database/mongodb/barometer_test.go` (mobiletest) : `TestBarometerFromParOperateur`,
  `TestBarometerFromSansComparaisonOperateur`, `TestOperatorFamily`.
- Code mergé : `mobilefront#56` → `23cb44da`, `mobiletest#18` → `b0bf3907`.

## Réserves maintenues

- Aucune validation avec des données multi-utilisateurs : ni MongoDB ni `mongod` sur le poste
  de relecture, et le cluster de production n'est pas utilisable pour un test.
- En conséquence, **l'affichage réel du bloc opérateur n'a jamais été observé** ; seuls les
  tests le couvrent.
