# Échelle de score YELE — définition de référence

> **Ce document fait autorité.** Il définit l'unique échelle de score du projet
> YELE, celle que doivent appliquer l'application, le dashboard et
> l'historique. Toute valeur de score affichée à un utilisateur se lit dans ce
> document ; en cas de divergence entre un écran et ce texte, c'est l'écran qui
> est faux.
>
> Version du référentiel : **`yele-open-1.0.0`** — item **IMP-05**
> ([issue #11](https://github.com/yele-bf/mobilefront/issues/11)), owner au
> classeur V14 : TRAORE Abdoulaye / KIEMA François.
> Mise en œuvre dans le code : item **IMP-12**
> ([issue #16](https://github.com/yele-bf/mobilefront/issues/16)).

---

## 1. Le problème que cette échelle résout

Jusqu'ici, deux échelles coexistaient dans la même application :

| Écran | Ce qui était affiché | Échelle |
|---|---|---|
| Écran de résultat (`lib/screens/score_screen.dart`) | « Streaming vidéo 78/100 », « Navigation web 85/100 » | note bornée 0-100 |
| Historique (`lib/screens/history_screen.dart`) | score global | points, échelle ouverte |

Un même test pouvait donc valoir « 85/100 » sur un écran et « 80 495 » sur un
autre, sans que l'utilisateur puisse savoir si ces deux nombres parlaient de la
même chose. C'est le constat d'IMP-05 : *« L'échelle de score YELE diffère
fortement de celle utilisée par nPerf. »*

La correction n'est pas de choisir entre les deux, mais de **définir une seule
échelle et de l'appliquer partout**.

## 2. L'unité : le point YELE

Un score YELE est exprimé en **points**, jamais en pourcentage.

| Propriété | Valeur | Conséquence |
|---|---|---|
| Unité | point YELE | le suffixe affiché est `pts`, jamais `%` ni `/100` |
| Échelle | **ouverte**, non plafonnée | un score supérieur à 75 000 est normal et correct |
| Total de référence | **75 000 points** | somme des cinq allocations ; c'est un repère de lecture, **pas un maximum** |
| Précision | calcul en `double` | l'arrondi à l'entier n'a lieu qu'**à l'affichage** (§6) |
| Plancher | 0 | une composante ne peut pas être négative |

**Pourquoi 75 000 ?** C'est la somme des cinq allocations nominales :

```
17 500 (débit descendant) + 7 500 (débit montant) + 15 000 (latence)
+ 17 500 (navigation) + 17 500 (streaming) = 75 000
```

Ces 75 000 points correspondent à un test où chaque composante atteint son
allocation nominale. Comme les deux composantes de débit ne sont pas plafonnées
(§3.1 et §3.2), un très bon réseau dépasse 75 000 : c'est le comportement
attendu.

**Rapport avec nPerf.** nPerf exprime son score composite en « nPoints », sur
une échelle ouverte, avec une progression logarithmique sur les débits et sans
plafond publié. Notre échelle en points suit cette méthode. En revanche, nPerf
**ne publie pas ses formules ni ses coefficients de pondération** : nous
revendiquons la même *méthode*, jamais la même *formule*. Les allocations
ci-dessous sont les nôtres, documentées ici, et c'est ce document qui fait foi.

## 3. Les cinq composantes

Le score global est la **somme des cinq composantes**. Chacune est calculée
indépendamment, avec son propre statut.

| # | Composante | Allocation | Entrées | Fichier |
|---|---|---|---|---|
| 1 | Débit descendant | 17 500 pts | débit descendant (Mb/s) | `lib/services/yele_scoring_engine.dart` |
| 2 | Débit montant | 7 500 pts | débit montant (Mb/s) | idem |
| 3 | Latence et gigue | 15 000 pts | ping (ms), gigue (ms) | idem |
| 4 | Navigation web | 17 500 pts | temps de chargement de chaque page (s) | idem |
| 5 | Streaming vidéo | 17 500 pts | durée totale, temps de mise en tampon, interruptions | idem |

### 3.1 Débit descendant

```
S_D = 17 500 × log10(1 + D)     si D ≥ 0,1 Mb/s
S_D = 0                          si D < 0,1 Mb/s
```

`D` en Mb/s. Échelle **logarithmique** : chaque multiplication du débit par 10
ajoute environ 17 500 points. Non plafonné.

| Débit | Points |
|---:|---:|
| 0,1 Mb/s | 724 |
| 1 Mb/s | 5 268 |
| 5 Mb/s | 13 618 |
| 9 Mb/s | 17 500 |
| 10 Mb/s | 18 224 |
| 50 Mb/s | 29 882 |
| 100 Mb/s | 35 076 |
| 1 000 Mb/s | 52 508 |

### 3.2 Débit montant

```
S_U = 7 500 × log10(1 + U)      si U ≥ 0,1 Mb/s
S_U = 0                          si U < 0,1 Mb/s
```

Même forme, allocation plus faible : le montant pèse moins que le descendant.

| Débit | Points |
|---:|---:|
| 1 Mb/s | 2 258 |
| 5 Mb/s | 5 836 |
| 9 Mb/s | 7 500 |
| 50 Mb/s | 12 807 |

### 3.3 Latence et gigue

La latence **effective** combine ping et gigue, la gigue comptant double :

```
L = Ping + 2 × Gigue                       (en ms)

S_P = 15 000 × (1 − L / 250)²              si L < 250 ms
S_P = 0                                     sinon
```

Décroissance **quadratique** : la pénalité s'accélère quand la latence
augmente. C'est volontaire — au-delà de 100 ms, l'expérience se dégrade plus
vite que linéairement. Ne pas remplacer par une exponentielle.

| Latence effective | Points |
|---:|---:|
| 0 ms | 15 000 |
| 20 ms | 12 696 |
| 50 ms | 9 600 |
| 100 ms | 5 400 |
| 200 ms | 600 |
| 250 ms et plus | 0 |

### 3.4 Navigation web

Chaque page testée produit une note de qualité entre 0 et 100 :

```
QoE_page = max(0, 100 × (1 − T / 10))       T = temps de chargement, en s
```

La note de la composante est la **moyenne des pages réellement mesurées** :

```
QoE_web = moyenne des QoE_page
S_B     = 17 500 × QoE_web / 100
```

| Temps de chargement | Points |
|---:|---:|
| 1 s | 15 750 |
| 2 s | 14 000 |
| 5 s | 8 750 |
| 10 s et plus | 0 |

**Une page non mesurée n'est pas une page à 0.** Un temps `null` (délai
dépassé, erreur technique, page non testée) est **exclu de la moyenne** : il ne
tire pas le score vers le bas, il rend la composante *partielle* (§4 et §5).

### 3.5 Streaming vidéo

```
QoE_video = max(0, 100 × (1 − T_buf / T_total) − 15 × N_stalls)

S_V = 17 500 × QoE_video / 100
```

- `T_total` : durée totale de la session vidéo, en secondes (somme des paliers
  réellement joués) ;
- `T_buf` : temps passé en mise en tampon, démarrage initial **inclus** ;
- `N_stalls` : nombre d'interruptions de lecture.

Chaque interruption coûte **15 points de QoE**, soit 2 625 points YELE — la
première interruption est donc la plus chère en proportion, ce qui est
intentionnel.

| Session | Points |
|---|---|
| 30 s, 0 s de tampon, 0 interruption | 17 500 |
| 30 s, 3 s de tampon, 0 interruption | 15 750 |
| 30 s, 3 s de tampon, 1 interruption | 13 125 |
| 30 s, 0 s de tampon, 2 interruptions | 12 250 |
| 30 s, 3 s de tampon, 7 interruptions | 0 |

## 4. Une absence n'est jamais un zéro

C'est la règle la plus importante du référentiel, et la plus facile à casser.

| Situation | Score | Statut | Affichage |
|---|---|---|---|
| Mesure valide qui vaut réellement 0 point | `0` | `completed` | `0 pts` |
| Mesure absente (test non effectué) | `null` | `unavailable` | « non mesuré » |
| Mesure incohérente (négative, NaN, infinie) | `null` | `invalid` | « mesure invalide » |
| Test tenté mais échoué | `null` | `failed` | « échec » |
| Mesure partielle | score calculé | `partial` | « partiel » + motif |

Un `null` **ne doit jamais être converti en 0** à l'affichage : cela
transformerait une absence de mesure en mauvaise performance, ce qui est faux et
injuste pour l'utilisateur.

## 5. Quand le score global existe

Le score global n'est calculé que si **les cinq composantes sont `completed`** :

```
Score global = S_D + S_U + S_P + S_B + S_V
               (uniquement si les 5 composantes sont completed)
```

Sinon le score global vaut `null`, avec un statut global qui reprend la cause la
plus grave, dans cet ordre : `invalid` > `failed` > `unavailable` > `partial`.

L'interface **ne présente jamais un total partiel comme un score global**. Elle
affiche les composantes mesurées et indique ce qui manque. C'est le sens de
`YeleScoringResult.isComplete` : à vérifier avant tout affichage du total.

## 6. Arrondi

- Le calcul se fait en `double`, sans arrondi intermédiaire.
- La **somme** porte sur les valeurs non arrondies.
- L'arrondi à l'entier a lieu **au dernier moment**, à l'affichage
  (`round()`), jamais avant une addition.

Arrondir avant de sommer cinq composantes peut décaler le total de 2 à 3 points,
assez pour changer de classe en limite de seuil (§7).

## 7. Classification indicative

| Score global | Libellé |
|---|---|
| ≤ 30 000 pts | Très faible |
| ≤ 70 000 pts | Moyen |
| ≤ 110 000 pts | Bon |
| ≤ 160 000 pts | Très bon |
| > 160 000 pts | Excellent / élite |

Ces seuils sont **provisoires** : ils ne sont pas calibrés sur un échantillon
représentatif de mesures réelles. Ils sont centralisés dans le moteur
(`YeleScoringEngine.classify`) pour pouvoir être recalibrés en un seul endroit,
et la classification est **toujours secondaire** par rapport au score en
points : on affiche le score d'abord, le libellé ensuite.

## 8. Ce que chaque écran doit afficher

C'est le critère d'acceptation d'IMP-05 : *« L'échelle est clairement définie,
documentée et identique dans tous les écrans concernés. »*

| Vue | Score global | Composantes | Format |
|---|---|---|---|
| Application — écran de résultat | **oui**, en points | oui, en points | `80 495 pts` |
| Application — historique | **oui**, en points | non | `80 495 pts` |
| Dashboard (`New_web`) | **oui**, en points | oui, en points | `80 495 pts` |

Règles transverses :

1. **Un seul format** : `NN NNN pts` (espace insécable fine comme séparateur de
   milliers, suffixe `pts`).
2. **La même valeur** partout pour un même test : le score est stocké, pas
   recalculé différemment selon l'écran.
3. **Jamais de score global en `/100`** ni en `%`.
4. Si le score est `null`, afficher « non mesuré » et la raison — jamais `0`.
5. La version du référentiel (`yele-open-1.0.0`) est enregistrée avec chaque
   résultat, pour qu'un score ancien reste interprétable.

## 9. Les notes de qualité sur 100 restent internes

Les notes `QoE_page`, `QoE_web` et `QoE_video` (§3.4, §3.5) sont des valeurs
**internes** au calcul, sur 100, héritées du cadre ARCEP. Elles peuvent
apparaître dans l'interface **à deux conditions** :

- être étiquetées explicitement comme **note de qualité d'une composante** —
  par exemple « Navigation — note de qualité 70/100 » ;
- être accompagnées de leur **équivalent en points**, qui est la valeur de
  référence.

Elles ne sont **jamais** présentées comme le score YELE, ni comme un score
global, ni comparées à un score global. Deux échelles dans une même phrase,
c'est exactement le défaut qu'IMP-05 corrige.

## 10. Exemple complet, de bout en bout

Mesures : 50 Mb/s descendant, 20 Mb/s montant, ping 15 ms, gigue 2,5 ms,
pages chargées en 2 s / 3 s / 4 s, session vidéo de 30 s avec 3 s de tampon et
aucune interruption.

| Composante | Calcul | Points |
|---|---|---:|
| Débit descendant | `17 500 × log10(51)` | 29 882 |
| Débit montant | `7 500 × log10(21)` | 9 917 |
| Latence (L = 15 + 2×2,5 = 20 ms) | `15 000 × (1 − 20/250)²` | 12 696 |
| Navigation (QoE 80, 75, 60 → 70) | `17 500 × 70/100` | 12 250 |
| Streaming (QoE = 100 × 0,9) | `17 500 × 90/100` | 15 750 |
| **Score global** | somme | **80 495 pts** |

Classification : `80 495 ≤ 110 000` → **Bon**.

Ce tableau sert de test de référence : les valeurs sont reproductibles et
doivent rester stables tant que la version du référentiel ne change pas.

## 11. Versionnage

| Élément | Règle |
|---|---|
| Version courante | `yele-open-1.0.0` |
| Enregistrement | la version est stockée avec chaque résultat |
| Changement de formule | incrément de version obligatoire, et mention dans ce document |
| Changement d'allocation | idem : un score de 1.0.0 et un score de 1.1.0 ne sont pas comparables |
| Historique | un score ancien garde sa version d'origine ; il n'est pas recalculé |

## 12. Portée et suites

- **Livré dans `mobilefront`** : la définition (ce document) et l'application
  dans l'application et l'historique (IMP-12).
- **Hors périmètre de cette vague** : l'affichage dans le dashboard `New_web`
  et l'exposition des champs côté `mobiletest`. Le critère d'IMP-12 nomme le
  dashboard ; il reste à brancher, et ce document est la référence à appliquer
  le jour où il le sera.
- **Seuils ARCEP** : les seuils de navigation et de streaming viennent du
  référentiel ARCEP documenté dans
  [`docs/fiches/IMP-06-seuils-arcep-scoring.md`](fiches/IMP-06-seuils-arcep-scoring.md).
  Ce document ne les redéfinit pas : il définit la façon dont ils produisent un
  score.
