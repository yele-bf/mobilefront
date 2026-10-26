# Changelog

## [Non publiée]

### Ajouté

- IMP-06 : scores Navigation et Streaming recalculés depuis les seuils ARCEP (référentiel dans `lib/constants/arcep_seuils.dart`) — navigation : part de pages chargées sous 30 s, pénalité de confort rapportée au seuil ; streaming : moyenne des paliers servis réduite par les seuils (démarrage ≤ 5 s, rebuffering ≤ 10 %, aucune interruption, ≥ 480p).
- ISS-01 : collecte et affichage du signal radio (RSRP/RSRQ LTE, SS-RSRP/SS-RSRQ 5G SA, RSSI Wi-Fi), stocké avec chaque mesure (Hive 36 à 41) et transmis au backend.
- ISS-07 : test de streaming sur les trois paliers 720p/1080p/2160p (lecteur neuf par palier, qualité réellement servie mesurée), moteur HLS à qualité verrouillée sélectionnable à chaud et tableau de résultats à trois colonnes.
- ISS-10 : adresse lisible (géocodage inversé Nominatim, cache mémoire + disque, 1 requête/s) dans le détail de l'historique, avec repli sur les coordonnées.

### Corrigé

- ISS-02 : détecter l'opérateur et l'emplacement de la SIM utilisée pour les données mobiles sur Android.
- ISS-04 : afficher le nom du serveur réellement configuré au lieu de l'étiquette statique « YELE SERVER OUAGADOUGOU ».
- ISS-03 : ne plus afficher l'opérateur de la SIM ni la techno cellulaire pendant un test Wi-Fi, ni les enregistrer dans le résultat (l'historique masque aussi ces champs sur les anciens enregistrements).
