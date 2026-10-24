# Gabarit — fiche d'impact par Sous-ID

> **Mode d'emploi** : copier ce fichier vers
> `docs/fiches/<SOUS-ID>-<slug>.md` (ex. `docs/fiches/ISS-03-reseau-wifi.md`),
> puis remplacer tout ce qui est entre chevrons. Une fiche par Sous-ID du
> classeur V14, jointe à la PR (CONTRIBUTING §4). Les valeurs des champs
> « Priorité / vague » et « Validation imposée » se lisent dans
> `docs/items-v14.json` — ne pas les inventer.
>
> La fiche s'écrit au **passé** une fois la PR ouverte : elle décrit ce qui a
> été fait et ce qui a été mesuré, jamais ce qui reste « à réaliser ». Si une
> vérification n'a pas pu être faite, l'écrire explicitement dans « Limites ».

---

# <SOUS-ID> — <titre court de l'impact, pas le titre de l'issue>

| Champ | Valeur |
|---|---|
| Dépôt | `mobilefront` |
| Issue | [#<n>](https://github.com/yele-bf/mobilefront/issues/<n>) |
| Priorité / vague | <P1 · P2 · P3> / <V1 Quick wins … V6 Évolutions lourdes> |
| Owner au classeur | <Nom Prénom> / <Nom Prénom> |
| Branche | `<type>/<SOUS-ID>-<slug>` |
| Validation imposée | <colonne « Validation / test » du classeur> |

## Constat et impact

<Ce qui est faux ou manquant aujourd'hui, et la conséquence concrète pour
l'utilisateur ou pour la mesure. Reprendre le constat du classeur, reformulé
si nécessaire, sans le contredire.>

## Correction

<Ce qui a été changé, dans quels fichiers, et pourquoi cette approche. Une
ligne par décision non évidente (API choisie, repli, cache, compatibilité).
Nommer les fichiers en `code`.>

## Critère d'acceptation

<Le critère du classeur, tel qu'il se vérifie : une phrase observable dans
l'application, pas une intention.>

## Validation

- **Automatisée** : <`flutter analyze` + `flutter test`, tests ajoutés par la
  PR, résultat CI>.
- **Support imposé par le classeur** : <APK réel / Chrome / local backend +
  dashboard> — <fait le AAAA-MM-JJ, où, avec quel appareil ou navigateur, et
  ce qui a été observé>.
- **Preuve** : <capture dans la PR n° … / sortie de test / log, chemin>.

## Limites connues

<Ce qui n'a pas pu être vérifié, ce qui reste hors périmètre, ce qui dépend
d'une autre PR ou d'un autre dépôt. Supprimer la section si elle est vide —
mais ne jamais laisser croire à une validation qui n'a pas eu lieu.>

---

## Liste de contrôle avant d'ouvrir la PR

- [ ] La fiche est dans `docs/fiches/` avec le nom `<SOUS-ID>-<slug>.md`.
- [ ] Les champs du tableau viennent de `docs/items-v14.json`.
- [ ] Une ligne **datée** a été ajoutée au tableau d'historique de
      `docs/registre-revisions.md` (sans elle, `guard` est rouge).
- [ ] Le `CHANGELOG.md` du dépôt a une entrée sous `## [Non publiée]`.
- [ ] Le corps de la PR porte `Closes #<n>` et la même liste de validation.
