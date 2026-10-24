# Registre des révisions — `yele-bf/<DÉPÔT>`

> Une ligne par contribution **mergée** (CONTRIBUTING §5). Le hash de commit est
> complété **après** le merge. Vocabulaire de statut : `À faire | En cours |
> Transmis | Validé | Rejeté | À re-vérifier`.
>
> **Aucune ligne d'exemple** : `guard` exige une ligne datée par Sous-ID cité, donc
> une ligne factice rendrait le garde-fou menteur. Une contribution qui n'a pas de
> hash de merge n'a pas sa place ici.

| Date | Sous-ID (V14) | Type | Agent | Owner (classeur) | Branche / PR | Commit | Validation | Statut |
|---|---|---|---|---|---|---|---|---|
| 2026-10-14 | ISS-12 | fix | COMPAORE Bobodo Kévin Aymar | COMPAORE Bobodo Kévin Aymar | `iss/ISS-12-reglages` (antérieur au garde-fou) | `709dd26` | Chrome + APK réel | Validé |
| 2026-10-20 | ISS-02 | fix | BAMBA Seydou | BAMBA Seydou / NANEMA Wendinkonté Dimitri Judicaël | `iss/ISS-02-identification-reseau` (#30) | `5ca52d9` | APK réel double SIM le 24/10/2026 : données Orange → SIM 2, données Télécel → SIM 1 | Validé |
| 2026-10-23 | ISS-04 | fix | TAMINI Heremave | KOHOUN Damou Daniel / TAMINI Heremave | `iss/ISS-04-serveur-reel` (#35) | `a84aa4f` | Local Chrome : serveur affiché = hôte de `API_BASE_URL` ; test de débit non lancé | Validé |
| 2026-10-24 | ISS-03 | fix | SAWADOGO Hassan Achraf Ammar | SAWADOGO Hassan Achraf Ammar | `iss/ISS-03-reseau-wifi` (#32) | `5b98edf` | Analyse + tests + APK debug compilé en CI ; APK réel Wi-Fi vs données à refaire après merge | Transmis |
| 2026-10-24 | ISS-01 | feat | SAWADOGO Hassan Achraf Ammar | SAWADOGO Hassan Achraf Ammar | `feature/signal-rsrp-rsrq` (#31) | `96b75e8` | Analyse + tests + APK debug (Kotlin compilé) en CI ; relevé APK 4G/5G à joindre | Transmis |
| 2026-10-24 | ISS-10 | feat | SAWADOGO Hassan Achraf Ammar | SAWADOGO Hassan Achraf Ammar | `iss/ISS-10-historique-adresse` (#34) | `8f610f5` | Analyse + tests CI ; adresse Ouagadougou annoncée sans capture, à joindre | Transmis |
| 2026-10-24 | ISS-07 | feat | SAWADOGO Hassan Achraf Ammar | SAWADOGO Hassan Achraf Ammar | `iss/ISS-07-streaming-trois-resolutions` (#33) | `93d6a33` | 5 fichiers de tests verts en CI ; relevés Chrome + APK à joindre | Transmis |

## Nomenclature V14 vs V11 vs V4 (à lire avant de citer un Sous-ID)

- **V14 (19/10/2026) = V11 + IMP-14** (conditions d'utilisation au premier lancement, P3, `mobilefront`) **+ IMP-15** (prévision de la qualité réseau, P1, `New_web`) : 27 items.

- **Baromètre de comparaison = IMP-09 en V11** (il s'appelait **IMP-11 en V4**).
  Deux commits déjà poussés portent l'ancien libellé et doivent être référencés
  comme **IMP-09** : `16d2a89` (mobilefront), `836b4cf` (mobiletest).
- **IMP-11 en V11 = export CSV/JSON** des mesures depuis le dashboard ou l'API :
  **pas encore implémenté** (périmètre `mobiletest` + `New_web`). Ne jamais
  citer `IMP-11` pour le baromètre.

## État connu au 14/10/2026 (audit des commits déjà poussés)

Cette section est documentaire : elle reflète l'historique **antérieur** à la
mise en place du garde-fou, dont les commits ne respectent pas encore le §2.

| Sous-ID | Commits poussés | Validation | Statut |
|---|---|---|---|
| IMP-09 | `16d2a89` (mobilefront), `836b4cf` (mobiletest) — libellé « IMP-11 » au moment du commit | Local (écran résultat + base) | Validé |
| IMP-04 | `f9c2f0e` | APK réel | Validé |
| IMP-08 | `1f6f62a` | APK réel | Validé |
| IMP-13 | `fb7cccd`, `7f81eac` | APK réel | Validé |
| ISS-09 | `1a889e3` | APK (GPS off) | Validé |
| ISS-12 | `709dd26` | Chrome + APK | Validé |

## Suivi des 27 items V14 (une ligne par Sous-ID — référence du garde-fou §5)

| Sous-ID | Intitulé (V14) | Owner (classeur) | Statut classeur |
|---|---|---|---|
| IMP-01 | Consommation data — P3 | COMPAORE Bobodo Kévin Aymar | Valide |
| IMP-04 | Permissions — P3 | COMPAORE Bobodo Kévin Aymar | Valide |
| IMP-08 | Consommation data — P3 | COMPAORE Bobodo Kévin Aymar | Valide |
| IMP-13 | Identification appareil — P3 | COMPAORE Bobodo Kévin Aymar | Valide |
| IMP-02 | Paramètres — P3 | NANA Amoin Agnès / Cissé Aboubacar Sidiki | Valide |
| IMP-14 | Condition d'utilisation — P3 | SANOU Zossoun Aristide Daouda | Valide |
| IMP-15 | Prevision reseau — P1 | SANOU Zossoun Aristide Daouda | Valide |
| IMP-03 | Compte utilisateur — P3 | SANOU Zossoun Aristide Daouda / SANNA Abdoul Salam | Valide |
| IMP-09 | Comparaison — P3 | SANOU Zossoun Aristide Daouda / SANNA Abdoul Salam | Valide |
| IMP-10 | Dashboard / Carte — P3 | SAWADOGO Wend-kuni Cédric / KOUNANGA Benoit / ZOUNGRANA Wendkuni Brice Yannick / OUEDRAOGO AZIZ | Valide |
| ISS-08 | Synchronisation — P2 | BAMBA Seydou / NANEMA Wendinkonté Dimitri Judicaël | Valide |
| IMP-11 | Données / Export — P2 | COMPAORE Bobodo Kévin Aymar | Valide |
| ISS-09 | GPS — P2 | COMPAORE Bobodo Kévin Aymar | Valide |
| ISS-11 | Dashboard / Carte — P2 | COMPAORE Bobodo Kévin Aymar | Valide |
| ISS-12 | Paramètres — P2 | COMPAORE Bobodo Kévin Aymar | Valide |
| IMP-06 | Référentiel ARCEP — P2 | NIKIEMA Abdoul Fatahou / NONGUIERMA WENDINSOO LEONEL | Valide |
| IMP-07 | Débit / Latence — P2 | SANOU Zossoun Aristide Daouda / TRAORE Oumou Kal / Ilboudo Wendpagnagdé Elsa Fleur | Valide |
| ISS-07 | Streaming — P2 | SAWADOGO Hassan Achraf Ammar | Valide |
| ISS-10 | Historique — P2 | SAWADOGO Hassan Achraf Ammar | Valide |
| IMP-05 | Échelle de score — P2 | TRAORE Abdoulaye / KIEMA François | Valide |
| IMP-12 | Échelle de score — P2 | TRAORE Abdoulaye / KIEMA François | Valide |
| ISS-06 | Débit / Latence — P2 | Wangraoua Aicha Bénédicte Flore Myriam / SAWADOGO Sutongnoma Saturnin | Valide |
| ISS-02 | Identification réseau — P1 | BAMBA Seydou / NANEMA Wendinkonté Dimitri Judicaël | Valide |
| ISS-04 | Serveur — P1 | KOHOUN Damou Daniel / TAMINI Heremave | Valide |
| ISS-01 | Mesures radio — P1 | SAWADOGO Hassan Achraf Ammar | Valide |
| ISS-03 | Identification réseau — P1 | SAWADOGO Hassan Achraf Ammar | Valide |
| ISS-05 | Comparaison — P1 | ZOUNGRANA Wendkuni Brice Yannick / OUEDRAOGO AZIZ | Valide |
