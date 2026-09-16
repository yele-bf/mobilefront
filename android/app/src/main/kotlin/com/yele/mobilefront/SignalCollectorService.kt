package com.yele.mobilefront

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.Process
import android.net.TrafficStats
import android.telephony.TelephonyManager
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

/**
 * Collecte passive de couverture réseau, en service de premier plan.
 *
 * Toutes les [KEY_INTERVAL] minutes, relève la position, la technologie radio,
 * l'opérateur et la puissance du signal, puis envoie le point au backend. Une
 * relève coûte environ un kilo-octet : c'est ce qui permet une cadence élevée
 * là où un speedtest complet consommerait des dizaines de mégaoctets.
 *
 * Le service est volontairement écrit en natif plutôt qu'en isolate Dart :
 * TelephonyManager et le fournisseur de position sont des API Android, et un
 * isolate d'arrière-plan n'aurait pas accès au canal de méthode de
 * MainActivity, en plus d'entrer en conflit avec la base Hive de l'interface.
 *
 * La notification permanente n'est pas décorative : Android l'impose en
 * contrepartie du droit de tourner en continu, et elle donne à l'utilisateur
 * le moyen d'arrêter la collecte à tout moment.
 */
class SignalCollectorService : Service() {

    companion object {
        const val ACTION_START = "com.yele.mobilefront.START_COLLECT"
        const val ACTION_STOP = "com.yele.mobilefront.STOP_COLLECT"

        const val PREFS = "yele_background"
        const val KEY_ENABLED = "collect_enabled"
        const val KEY_INTERVAL = "collect_interval_min"
        const val KEY_API_BASE = "api_base_url"
        const val KEY_LAST_AT = "last_collect_at"
        const val KEY_COUNT = "collect_count"
        // IMP-13 : UUID d'appareil anonyme (généré côté Dart, repris ici pour
        // que les relèves passives soient traçables au même appareil).
        const val KEY_DEVICE_ID = "device_id"

        // IMP-01d — Comptage du trafic de la collecte en arrière-plan : le
        // suivi de consommation (UsageTrackerService côté Dart) ne voit que le
        // trafic quand l'app est au premier plan. Le service relève ici les
        // compteurs UID (TrafficStats) autour de chaque relève et persiste le
        // delta dans les prefs ; l'app le réintègre dans la box Hive au
        // démarrage / au retour au premier plan.
        const val KEY_BG_USAGE_BYTES = "bg_usage_bytes"

        const val DEFAULT_INTERVAL_MIN = 15

        /**
         * Repli MCC+MNC vers le nom d'opérateur, pour les téléphones qui ne
         * renseignent pas le nom. Même table que NetworkInfoService côté Dart ;
         * limitée au Burkina Faso, pays de déploiement.
         */
        val OPERATORS_BY_MCC_MNC = mapOf(
            "61301" to "Telmob (Onatel)",
            "61302" to "Orange Burkina Faso",
            "61303" to "Telecel Faso",
        )

        private const val CHANNEL_ID = "yele_collect"
        private const val NOTIFICATION_ID = 4201

        /** Vrai tant que le service tourne ; lu par l'interface via le canal. */
        @Volatile
        var isRunning: Boolean = false
            private set

        fun prefs(context: Context): SharedPreferences =
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    }

    private val handler = Handler(Looper.getMainLooper())
    private var intervalMin = DEFAULT_INTERVAL_MIN
    private var lastSummary = "En attente de la première relève…"

    /** Vrai pendant qu'une relève est en cours, pour éviter les chevauchements. */
    private var collecting = false

    /** Boucle de relève : se replanifie elle-même tant que le service vit. */
    private val tick = object : Runnable {
        override fun run() {
            collectAndSend()
            handler.postDelayed(this, intervalMin * 60_000L)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopCollecting()
            return START_NOT_STICKY
        }

        intervalMin = prefs(this).getInt(KEY_INTERVAL, DEFAULT_INTERVAL_MIN)
            .coerceIn(5, 24 * 60)

        startForeground(NOTIFICATION_ID, buildNotification())
        isRunning = true
        prefs(this).edit().putBoolean(KEY_ENABLED, true).apply()

        // Première relève immédiate : sans elle, l'utilisateur qui active la
        // collecte ne verrait rien se produire pendant un quart d'heure et
        // croirait la fonction inopérante.
        handler.removeCallbacks(tick)
        handler.post(tick)

        // START_STICKY : si Android tue le processus faute de mémoire, le
        // service est recréé — c'est l'engagement « tant que l'utilisateur
        // n'arrête pas lui-même ».
        return START_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacks(tick)
        isRunning = false
        super.onDestroy()
    }

    private fun stopCollecting() {
        prefs(this).edit().putBoolean(KEY_ENABLED, false).apply()
        handler.removeCallbacks(tick)
        isRunning = false
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    // ── Notification ─────────────────────────────────────────────────────────

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Collecte de couverture",
            // IMPORTANCE_LOW : notification visible et permanente, mais sans
            // son ni vibration — elle reste affichée des heures durant.
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Mesure passive de la couverture réseau en arrière-plan"
            setShowBadge(false)
        }
        (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification {
        val openApp = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val stop = PendingIntent.getService(
            this, 1,
            Intent(this, SignalCollectorService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Yélé — collecte de couverture")
            .setContentText(lastSummary)
            .setStyle(NotificationCompat.BigTextStyle().bigText(lastSummary))
            .setSmallIcon(android.R.drawable.stat_sys_upload_done)
            .setContentIntent(openApp)
            .addAction(0, "Arrêter", stop)
            .setOngoing(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun updateNotification(summary: String) {
        lastSummary = summary
        if (!isRunning) return
        (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .notify(NOTIFICATION_ID, buildNotification())
    }

    // ── Relève ───────────────────────────────────────────────────────────────

    private fun collectAndSend() {
        // Une relève peut durer jusqu'à 30 s (attente du correctif GPS) alors
        // que le service peut être redémarré entre-temps — un changement de
        // cadence dans les réglages suffit. Sans ce garde-fou, deux relèves se
        // chevauchent et le même point part deux fois.
        if (collecting) return
        collecting = true

        // IMP-01d — Instantané des compteurs réseau de l'app avant la relève.
        val rxBefore = TrafficStats.getUidRxBytes(Process.myUid())
        val txBefore = TrafficStats.getUidTxBytes(Process.myUid())

        requestLocation { location ->
            val sample = buildSample(location)
            val tech = sample.optString("cellularTech", "").ifEmpty { "réseau inconnu" }
            val dbm = if (sample.has("signalDbm")) "${sample.getInt("signalDbm")} dBm" else "signal n.d."

            if (location == null) {
                // Un point sans position n'a aucune valeur sur une carte de
                // couverture : on ne l'envoie pas, mais on le signale.
                collecting = false
                updateNotification("Position indisponible — relève ignorée")
                return@requestLocation
            }

            Thread {
                val ok = postSample(sample)
                // IMP-01d — Volume consommé par cette relève (requête HTTP de
                // télémétrie, ~1 Ko) : persisté, réintégré par l'app.
                val rxAfter = TrafficStats.getUidRxBytes(Process.myUid())
                val txAfter = TrafficStats.getUidTxBytes(Process.myUid())
                var delta = 0L
                if (rxBefore != TrafficStats.UNSUPPORTED.toLong() &&
                    txBefore != TrafficStats.UNSUPPORTED.toLong() &&
                    rxAfter >= rxBefore && txAfter >= txBefore
                ) {
                    delta = (rxAfter - rxBefore) + (txAfter - txBefore)
                }
                handler.post {
                    collecting = false
                    if (ok) {
                        val p = prefs(this)
                        p.edit()
                            .putLong(KEY_LAST_AT, System.currentTimeMillis())
                            .putInt(KEY_COUNT, p.getInt(KEY_COUNT, 0) + 1)
                            .apply()
                        // IMP-01d — On ne compte que les relèves envoyées avec
                        // succès (une relève ignorée sans position ne consomme
                        // rien ; un échec d'envoi sera compté à la relève
                        // suivante qui réessaiera).
                        if (ok && delta > 0) {
                            val usage = p.getLong(KEY_BG_USAGE_BYTES, 0L) + delta
                            p.edit().putLong(KEY_BG_USAGE_BYTES, usage).apply()
                        }
                        updateNotification("Dernière relève : $tech, $dbm")
                    } else {
                        updateNotification("Envoi impossible — nouvelle tentative dans ${intervalMin} min")
                    }
                }
            }.start()
        }
    }

    /** Construit le point de mesure passif à envoyer. */
    private fun buildSample(location: Location?): JSONObject {
        val json = JSONObject()
        json.put("type", "passive")

        // IMP-13 : identifiant d'appareil anonyme, absent si non encore propagé.
        prefs(this).getString(KEY_DEVICE_ID, null)?.let { json.put("deviceId", it) }

        location?.let {
            json.put("latitude", it.latitude)
            json.put("longitude", it.longitude)
            json.put("accuracy", it.accuracy)
        }

        val tm = getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
        if (tm != null) {
            try {
                val mccMnc = tm.networkOperator?.trim()?.takeIf { it.isNotEmpty() }
                mccMnc?.let { json.put("mccMnc", it) }

                // Beaucoup de téléphones ne provisionnent pas le nom de
                // l'opérateur et renvoient son code MCC+MNC à la place. Envoyé
                // tel quel, « 61301 » se retrouverait traité comme un opérateur
                // à part entière dans toutes les statistiques.
                val name = tm.networkOperatorName?.trim()?.takeIf { it.isNotEmpty() }
                val resolved = operatorName(name, mccMnc)
                resolved?.let { json.put("simOperator", it) }
            } catch (_: Exception) {
                // Permission ou constructeur récalcitrant : champs omis.
            }

            try {
                @Suppress("DEPRECATION")
                val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    tm.dataNetworkType
                } else {
                    tm.networkType
                }
                techLabel(type)?.let { json.put("cellularTech", it) }
            } catch (_: Exception) {
            }

            // Puissance du signal : API disponible à partir d'Android 9.
            // En dessous, le champ est simplement absent.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                try {
                    tm.signalStrength?.cellSignalStrengths?.firstOrNull()?.let { s ->
                        json.put("signalDbm", s.dbm)
                        json.put("signalLevel", s.level) // 0 (nul) à 4 (excellent)
                    }
                } catch (_: Exception) {
                }
            }
        }
        return json
    }

    /**
     * Envoie le point sur l'endpoint de télémétrie existant, avec des débits à
     * zéro. Le backend distingue les deux natures de mesure par le champ
     * `type` de `extra` ; côté analyse, les points passifs sont déjà écartés
     * des statistiques de débit par le filtre `dl > 0`.
     */
    private fun postSample(sample: JSONObject): Boolean {
        val base = prefs(this).getString(KEY_API_BASE, null) ?: return false
        return try {
            val url = URL("$base/results/telemetry")
            val body = listOf(
                "ispinfo" to "",
                "dl" to "0",
                "ul" to "0",
                "ping" to "0",
                "jitter" to "0",
                "log" to "Yélé collecte passive",
                "extra" to sample.toString(),
            ).joinToString("&") { (k, v) ->
                "${URLEncoder.encode(k, "UTF-8")}=${URLEncoder.encode(v, "UTF-8")}"
            }

            val payload = body.toByteArray(Charsets.UTF_8)

            (url.openConnection() as HttpURLConnection).run {
                requestMethod = "POST"
                connectTimeout = 20_000
                readTimeout = 20_000
                doOutput = true
                setRequestProperty(
                    "Content-Type", "application/x-www-form-urlencoded; charset=UTF-8"
                )
                // Mode « longueur fixe » : indispensable ici, pas seulement une
                // optimisation. Sans lui, HttpURLConnection met le corps en
                // tampon et réémet silencieusement la requête quand il juge la
                // connexion instable — le serveur enregistre alors deux fois la
                // même relève, alors que le client ne voit qu'une réponse.
                setFixedLengthStreamingMode(payload.size)
                outputStream.use { it.write(payload) }
                val code = responseCode
                disconnect()
                code in 200..299
            }
        } catch (_: Exception) {
            // Réseau absent ou serveur endormi : la relève suivante réessaiera.
            false
        }
    }

    // ── Position ─────────────────────────────────────────────────────────────

    /**
     * Demande une position fraîche, avec repli sur la dernière position connue
     * au bout de [LOCATION_TIMEOUT_MS]. Un correctif GPS peut être long en
     * intérieur ; attendre indéfiniment maintiendrait la puce allumée et
     * viderait la batterie.
     */
    private fun requestLocation(onResult: (Location?) -> Unit) {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION)
            != PackageManager.PERMISSION_GRANTED
        ) {
            onResult(null)
            return
        }

        val lm = getSystemService(Context.LOCATION_SERVICE) as? LocationManager
        if (lm == null) {
            onResult(null)
            return
        }

        val provider = when {
            lm.isProviderEnabled(LocationManager.GPS_PROVIDER) -> LocationManager.GPS_PROVIDER
            lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER) -> LocationManager.NETWORK_PROVIDER
            else -> null
        }
        if (provider == null) {
            onResult(null)
            return
        }

        var settled = false
        val listener = object : LocationListener {
            override fun onLocationChanged(location: Location) {
                if (settled) return
                settled = true
                try {
                    lm.removeUpdates(this)
                } catch (_: Exception) {
                }
                onResult(location)
            }

            // Surcharges obsolètes mais requises sur les anciennes versions.
            override fun onStatusChanged(p: String?, s: Int, e: Bundle?) {}
            override fun onProviderEnabled(p: String) {}
            override fun onProviderDisabled(p: String) {}
        }

        try {
            lm.requestLocationUpdates(provider, 0L, 0f, listener, Looper.getMainLooper())
        } catch (_: SecurityException) {
            onResult(null)
            return
        }

        handler.postDelayed({
            if (settled) return@postDelayed
            settled = true
            try {
                lm.removeUpdates(listener)
            } catch (_: Exception) {
            }
            val fallback = try {
                lm.getLastKnownLocation(provider)
            } catch (_: SecurityException) {
                null
            }
            onResult(fallback)
        }, LOCATION_TIMEOUT_MS)
    }

    /**
     * Nom d'opérateur exploitable, ou null si rien n'est déterminable.
     *
     * [reported] est le nom remonté par le système : il est parfois vide,
     * parfois égal au code MCC+MNC. Dans ces deux cas on retombe sur la table
     * locale, seule source fiable d'un libellé lisible.
     */
    private fun operatorName(reported: String?, mccMnc: String?): String? {
        val known = OPERATORS_BY_MCC_MNC[mccMnc]
        if (reported == null) return known
        // Un nom entièrement numérique est un code, pas un nom commercial.
        if (reported.all { it.isDigit() }) return known ?: reported
        return reported
    }

    private fun techLabel(type: Int): String? = when (type) {
        TelephonyManager.NETWORK_TYPE_GPRS,
        TelephonyManager.NETWORK_TYPE_EDGE,
        TelephonyManager.NETWORK_TYPE_CDMA,
        TelephonyManager.NETWORK_TYPE_1xRTT,
        TelephonyManager.NETWORK_TYPE_IDEN,
        TelephonyManager.NETWORK_TYPE_GSM -> "2G"

        TelephonyManager.NETWORK_TYPE_UMTS,
        TelephonyManager.NETWORK_TYPE_EVDO_0,
        TelephonyManager.NETWORK_TYPE_EVDO_A,
        TelephonyManager.NETWORK_TYPE_HSDPA,
        TelephonyManager.NETWORK_TYPE_HSUPA,
        TelephonyManager.NETWORK_TYPE_HSPA,
        TelephonyManager.NETWORK_TYPE_EVDO_B,
        TelephonyManager.NETWORK_TYPE_EHRPD,
        TelephonyManager.NETWORK_TYPE_HSPAP,
        TelephonyManager.NETWORK_TYPE_TD_SCDMA -> "3G"

        TelephonyManager.NETWORK_TYPE_LTE,
        TelephonyManager.NETWORK_TYPE_IWLAN -> "4G"

        TelephonyManager.NETWORK_TYPE_NR -> "5G"

        else -> null
    }
}

private const val LOCATION_TIMEOUT_MS = 30_000L
