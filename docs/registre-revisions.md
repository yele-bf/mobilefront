
# Registre des rÃ©visions â `yele-bf/<DÃPÃT>`

> Une ligne par contribution **mergÃ©e** (CONTRIBUTING Â§5). Le hash de commit est
> complÃ©tÃ© **aprÃ¨s** le merge. Vocabulaire de statut : `Ã faire | En cours |
> Transmis | ValidÃ© | RejetÃ© | Ã re-vÃ©rifier`.
>
> **Aucune ligne d'exemple** : `guard` exige une ligne datÃ©e par Sous-ID citÃ©, donc
> une ligne factice rendrait le garde-fou menteur. Une contribution qui n'a pas de
> hash de merge n'a pas sa place ici.
>
> **Preuves** : les captures de validation sont versionnÃ©es dans `docs/preuves/`
> (voir son README) et citÃ©es ici par leur chemin. Un `ValidÃ©` dont la preuve
> n'est pas joignable n'est pas recevable (CONTRIBUTING Â§6.1).

| Date | Sous-ID (V14) | Type | Agent | Owner (classeur) | Branche / PR | Commit | Validation | Statut |
|---|---|---|---|---|---|---|---|---|
| 2026-10-14 | ISS-12 | fix | COMPAORE Bobodo KÃ©vin Aymar | COMPAORE Bobodo KÃ©vin Aymar | `iss/ISS-12-reglages` (antÃ©rieur au garde-fou) | `709dd26` | Chrome + APK rÃ©el | ValidÃ© |
| 2026-10-20 | ISS-02 | fix | BAMBA Seydou | BAMBA Seydou / NANEMA WendinkontÃ© Dimitri JudicaÃ«l | `iss/ISS-02-identification-reseau` (#30) | `5ca52d9` | APK rÃ©el double SIM le 24/10/2026 : donnÃ©es Orange â SIM 2, donnÃ©es TÃ©lÃ©cel â SIM 1 | ValidÃ© |
| 2026-10-23 | ISS-04 | fix | TAMINI Heremave | KOHOUN Damou Daniel / TAMINI Heremave | `iss/ISS-04-serveur-reel` (#35) | `a84aa4f` | Local Chrome : serveur affichÃ© = hÃ´te de `API_BASE_URL` ; test de dÃ©bit non lancÃ© | ValidÃ© |
| 2026-10-24 | ISS-03 | fix | SAWADOGO Hassan Achraf Ammar | SAWADOGO Hassan Achraf Ammar | `iss/ISS-03-reseau-wifi` (#32) | `5b98edf` | APK rÃ©el Wi-Fi et 4G le 25/10/2026 (Hicel STAR 1) : historique et bilan sans ligne Â« RÃ©seau mobile Â» en Wi-Fi, contre-Ã©preuve 4G ; `docs/preuves/ISS-03_*.png` â validÃ© le 26/10 | ValidÃ© |
| 2026-10-24 | ISS-01 | feat | SAWADOGO Hassan Achraf Ammar | SAWADOGO Hassan Achraf Ammar | `feature/signal-rsrp-rsrq` (#31) | `96b75e8` | APK rÃ©el 4G le 25/10/2026 (Hicel STAR 1) : RSRP â106 dBm et RSRQ â20 dB sur deux lignes ; 5G non dÃ©ployÃ©e au Burkina Faso (NSA = ancre LTE) ; `docs/preuves/ISS-01_4G_RSRP-RSRQ.png` â validÃ© le 26/10 | ValidÃ© |
| 2026-10-24 | ISS-10 | feat | SAWADOGO Hassan Achraf Ammar | SAWADOGO Hassan Achraf Ammar | `iss/ISS-10-historique-adresse` (#34) | `8f610f5` | APK rÃ©el + GPS le 25/10/2026 : Â« Piis Zuure, Tampouy, Ouagadougou, Centre Â» Ã  cÃ´tÃ© de 12.3855 / â1.5700 ; `docs/preuves/ISS-10_adresse.png` â validÃ© le 26/10 | ValidÃ© |
| 2026-10-24 | ISS-07 | feat | SAWADOGO Hassan Achraf Ammar | SAWADOGO Hassan Achraf Ammar | `iss/ISS-07-streaming-trois-resolutions` (#33) | `93d6a33` | APK rÃ©el : tableau HLS 720p/1080p/2160p (89,31 / 91,98 / 48,06 %, mini 0,65 / 0,99 / 2,83 Mb/s) le 25/10/2026 ; Chrome non fourni, un support suffit (Â§6.1) ; `docs/preuves/ISS-07_HLS_trois-paliers.png` â validÃ© le 26/10 | ValidÃ© |
| 2026-10-26 | IMP-06 | feat | NIKIEMA Abdoul Fatahou | NIKIEMA Abdoul Fatahou / NONGUIERMA WENDINSOO LEONEL | `feat/IMP-06-seuils-arcep` | `8d67bdf` | Analyse sans avertissement + 88 tests verts (63 sur `main`, +25) dont les cas limites autour des seuils (29,9/30,1 s ; 4,999/5,001 s ; 9,9/10,1 % ; 479/480p ; 0/1 interruption) ; non vÃ©rifiÃ© sur APK ni Chrome (support Â« local : jeux de valeurs Â») | Transmis |
| 2026-10-28 | IMP-02 | feat | NANA Amoin Agnès | NANA Amoin Agnès / Cissé Aboubacar Sidiki | `imp/IMP-02-parametres` (#48) | `98e5580` | Local Chrome + APK réel sur TECNO CAMON 20 Pro | En cours |
| 2026-10-28 | IMP-05 | docs | TRAORE Abdoulaye | TRAORE Abdoulaye / KIEMA François | `imp/IMP-05-echelle-score` | `—` | Local : échelle définie et documentée dans `docs/echelle-score.md`, tables de valeurs recalculées ; conformité des 3 vues non vérifiée (dashboard non branché) | En cours |

## Nomenclature V14 vs V11 vs V4 (Ã  lire avant de citer un Sous-ID)

- **V14 (19/10/2026) = V11 + IMP-14** (conditions d'utilisation au premier lancement, P3, `mobilefront`) **+ IMP-15** (prÃ©vision de la qualitÃ© rÃ©seau, P1, `New_web`) : 27 items.

- **BaromÃ¨tre de comparaison = IMP-09 en V11** (il s'appelait **IMP-11 en V4**).
  Deux commits dÃ©jÃ  poussÃ©s portent l'ancien libellÃ© et doivent Ãªtre rÃ©fÃ©rencÃ©s
  comme **IMP-09** : `16d2a89` (mobilefront), `836b4cf` (mobiletest).
- **IMP-11 en V11 = export CSV/JSON** des mesures depuis le dashboard ou l'API :
  **pas encore implÃ©mentÃ©** (pÃ©rimÃ¨tre `mobiletest` + `New_web`). Ne jamais
  citer `IMP-11` pour le baromÃ¨tre.

## Ãtat connu au 14/10/2026 (audit des commits dÃ©jÃ  poussÃ©s)

Cette section est documentaire : elle reflÃ¨te l'historique **antÃ©rieur** Ã  la
mise en place du garde-fou, dont les commits ne respectent pas encore le Â§2.

| Sous-ID | Commits poussÃ©s | Validation | Statut |
|---|---|---|---|
| IMP-09 | `16d2a89` (mobilefront), `836b4cf` (mobiletest) â libellÃ© Â« IMP-11 Â» au moment du commit | Local (Ã©cran rÃ©sultat + base) | ValidÃ© |
| IMP-01 | `â` | Lecture de code (APK rÃ©el non vÃ©rifiÃ© sur appareil/forfait) | ValidÃ© |
| IMP-04 | `f9c2f0e` | APK rÃ©el | ValidÃ© |
| IMP-08 | `1f6f62a` | APK rÃ©el | ValidÃ© |
| IMP-11 | `cd8cd20`, `1717b44` | APK rÃ©el (formalisation) | ValidÃ© |
| IMP-13 | `fb7cccd`, `7f81eac` | APK rÃ©el | ValidÃ© |
| ISS-09 | `1a889e3` | APK (GPS off) | ValidÃ© |
| ISS-12 | `709dd26` | Chrome + APK | ValidÃ© |

## Suivi des 27 items V14 (tableau d'avancement â **ne vaut pas preuve de contribution**, Â§5)

> **ISS-08 dÃ©classÃ© le 27/10/2026** â l'item n'est plus suivi : la solution
> YELE dÃ©jÃ  portÃ©e par les quatre dÃ©pÃ´ts couvre mieux l'objectif. DÃ©cision
> d'Ã©quipe aprÃ¨s dÃ©monstration de l'implÃ©mentation en local ; le classeur V14
> reste inchangÃ©.

| Sous-ID | IntitulÃ© (V14) | Owner (classeur) | Statut classeur |
|---|---|---|---|
| IMP-01 | Consommation data â P3 | COMPAORE Bobodo KÃ©vin Aymar | Valide |
| IMP-04 | Permissions â P3 | COMPAORE Bobodo KÃ©vin Aymar | Valide |
| IMP-08 | Consommation data â P3 | COMPAORE Bobodo KÃ©vin Aymar | Valide |
| IMP-13 | Identification appareil â P3 | COMPAORE Bobodo KÃ©vin Aymar | Valide |
| IMP-02 | ParamÃ¨tres â P3 | NANA Amoin AgnÃ¨s / CissÃ© Aboubacar Sidiki | Valide |
| IMP-14 | Condition d'utilisation â P3 | SANOU Zossoun Aristide Daouda | Valide |
| IMP-15 | Prevision reseau â P1 | SANOU Zossoun Aristide Daouda | Valide |
| IMP-03 | Compte utilisateur â P3 | SANOU Zossoun Aristide Daouda / SANNA Abdoul Salam | Valide |
| IMP-09 | Comparaison â P3 | SANOU Zossoun Aristide Daouda / SANNA Abdoul Salam | Valide |
| IMP-10 | Dashboard / Carte â P3 | SAWADOGO Wend-kuni CÃ©dric / KOUNANGA Benoit / ZOUNGRANA Wendkuni Brice Yannick / OUEDRAOGO AZIZ | Valide |
| ISS-08 | Synchronisation â P2 | BAMBA Seydou / NANEMA WendinkontÃ© Dimitri JudicaÃ«l | **DÃ©classÃ©** (27/10) |
| IMP-11 | DonnÃ©es / Export â P2 | COMPAORE Bobodo KÃ©vin Aymar | Valide |
| ISS-09 | GPS â P2 | COMPAORE Bobodo KÃ©vin Aymar | Valide |
| ISS-11 | Dashboard / Carte â P2 | COMPAORE Bobodo KÃ©vin Aymar | Valide |
| ISS-12 | ParamÃ¨tres â P2 | COMPAORE Bobodo KÃ©vin Aymar | Valide |
| IMP-06 | RÃ©fÃ©rentiel ARCEP â P2 | NIKIEMA Abdoul Fatahou / NONGUIERMA WENDINSOO LEONEL | Valide |
| IMP-07 | DÃ©bit / Latence â P2 | SANOU Zossoun Aristide Daouda / TRAORE Oumou Kal / Ilboudo WendpagnagdÃ© Elsa Fleur | Valide |
| ISS-07 | Streaming â P2 | SAWADOGO Hassan Achraf Ammar | Valide |
| ISS-10 | Historique â P2 | SAWADOGO Hassan Achraf Ammar | Valide |
| IMP-05 | Ãchelle de score â P2 | TRAORE Abdoulaye / KIEMA FranÃ§ois | Valide |
| IMP-12 | Ãchelle de score â P2 | TRAORE Abdoulaye / KIEMA FranÃ§ois | Valide |
| ISS-06 | DÃ©bit / Latence â P2 | Wangraoua Aicha BÃ©nÃ©dicte Flore Myriam / SAWADOGO Sutongnoma Saturnin | Valide |
| ISS-02 | Identification rÃ©seau â P1 | BAMBA Seydou / NANEMA WendinkontÃ© Dimitri JudicaÃ«l | Valide |
| ISS-04 | Serveur â P1 | KOHOUN Damou Daniel / TAMINI Heremave | Valide |
| ISS-01 | Mesures radio â P1 | SAWADOGO Hassan Achraf Ammar | Valide |
| ISS-03 | Identification rÃ©seau â P1 | SAWADOGO Hassan Achraf Ammar | Valide |
| ISS-05 | Comparaison â P1 | ZOUNGRANA Wendkuni Brice Yannick / OUEDRAOGO AZIZ | Valide |
