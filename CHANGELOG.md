# Changelog

## [Non publiée]

### Ajouté

- IMP-01 : formalisation de la consommation data par test (fiche + ligne de registre). Mesure via `TrafficStats` Android (rx+tx) dans `TrafficStatsService`/`DataUsageCapture`, branchée sur débit et streaming (classique/HLS), affichée dans score/historique, exportée CSV/JSON, suivi mensuel dans Réglages. iOS non mesurable (« — »). Validation par lecture de code (test APK terrain non réalisé dans cet environnement).
- Preuves : six captures de validation terrain (ISS-01, ISS-03, ISS-07, ISS-10) versionnées dans `docs/preuves/`, et règle de preuve au CONTRIBUTING §6.1 (une image, pas un récit ; `A/B` = l'un ou l'autre suffit, `A + B` = les deux ; 5G non déployée au Burkina Faso, ISS-01 validée sur capture 4G).
- IMP-06 : scores Navigation et Streaming recalculés depuis les seuils ARCEP (référentiel dans `lib/constants/arcep_seuils.dart`) — navigation : part de pages chargées sous 30 s, pénalité de confort rapportée au seuil ; streaming : moyenne des paliers servis réduite par les seuils (démarrage ≤ 5 s, rebuffering ≤ 10 %, aucune interruption, ≥ 480p).
- ISS-01 : collecte et affichage du signal radio (RSRP/RSRQ LTE, SS-RSRP/SS-RSRQ 5G SA, RSSI Wi-Fi), stocké avec chaque mesure (Hive 36 à 41) et transmis au backend.
- ISS-07 : test de streaming sur les trois paliers 720p/1080p/2160p (lecteur neuf par palier, qualité réellement servie mesurée), moteur HLS à qualité verrouillée sélectionnable à chaud et tableau de résultats à trois colonnes.
- ISS-10 : adresse lisible (géocodage inversé Nominatim, cache mémoire + disque, 1 requête/s) dans le détail de l'historique, avec repli sur les coordonnées.

### Corrigé

- ISS-02 : détecter l'opérateur et l'emplacement de la SIM utilisée pour les données mobiles sur Android.
- ISS-04 : afficher le nom du serveur réellement configuré au lieu de l'étiquette statique « YELE SERVER OUAGADOUGOU ».
- ISS-03 : ne plus afficher l'opérateur de la SIM ni la techno cellulaire pendant un test Wi-Fi, ni les enregistrer dans le résultat (l'historique masque aussi ces champs sur les anciens enregistrements).
- Garde-fou : le contrôle « le Sous-ID a une ligne au registre » ne porte plus que
  sur le **sujet** du commit (une PR de documentation qui nomme un Sous-ID dans
  le corps n'est plus refusée à tort), et les deux lignes d'exemple datées du
  registre sont retirées — elles satisfaisaient ce contrôle pour `IMP-11` et
  `ISS-12`. Règle écrite au CONTRIBUTING §5.

