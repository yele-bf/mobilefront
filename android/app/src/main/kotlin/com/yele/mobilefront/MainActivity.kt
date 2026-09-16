package com.yele.mobilefront

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.TrafficStats
import android.os.Build
import android.os.Process
import android.provider.Settings
import android.telephony.TelephonyManager
import androidx.annotation.NonNull
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.yele/telephony"
    private val phonePermissionRequestCode = 1001
    private val notificationPermissionRequestCode = 1002

    private companion object {
        const val ALERT_CHANNEL_ID = "yele_alerts"
        const val ALERT_NOTIFICATION_ID = 4203
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getTelephony" -> result.success(telephonyInfo())
                    "getDeviceMarketingName" -> result.success(deviceMarketingName())
                    "requestPhonePermission" -> result.success(ensurePhonePermission())
                    "hasPhonePermission" -> result.success(hasPhonePermission())
                    "checkNotificationPermission" -> result.success(hasNotificationPermission())
                    "requestNotificationPermission" -> result.success(requestNotificationPermission())
                    "getRxBytes" -> result.success(rxBytes())
                    "getTxBytes" -> result.success(txBytes())
                    // IMP-01 : compteurs cumulés par type de réseau, pour le
                    // suivi de consommation (mobile vs Wi-Fi) et le débit
                    // temps réel.
                    "getUsageSnapshot" -> result.success(usageSnapshot())
                    "notifyLimitExceeded" -> {
                        notifyLimitExceeded(
                            call.argument<String>("title") ?: "Yélé",
                            call.argument<String>("body") ?: "",
                        )
                        result.success(true)
                    }
                    "startThroughputService" -> {
                        // Volume déjà consommé ce mois (suivi Flutter) : la
                        // notification « débit temps réel » l'affiche en
                        // complément du débit instantané. NB : Dart envoie un
                        // int Java 32 bits quand la valeur est petite — on lit
                        // un Number et on convertit, sinon ClassCastException
                        // et le toggle échoue malgré la permission accordée.
                        val usage = (call.argument<Any>("usageBytes") as? Number)?.toLong() ?: 0L
                        result.success(startThroughputService(usage))
                    }
                    "stopThroughputService" -> {
                        stopThroughputService()
                        result.success(true)
                    }
                    // Resynchronise la base « Données utilisées » de la
                    // pastille sur les compteurs de l'app (même source que
                    // l'écran Consommation) — évite toute divergence.
                    "resyncThroughputUsage" -> {
                        val usage = (call.argument<Any>("usageBytes") as? Number)?.toLong() ?: 0L
                        ThroughputService.active?.resyncUsage(usage)
                        result.success(true)
                    }
                    "isThroughputRunning" -> result.success(ThroughputService.isRunning)
                    // Grand compteur en surimpression (taille de l'horloge) :
                    // l'icône de notification est limitée par Android à la
                    // taille du slot d'icônes (~17 dp), illisible. L'overlay
                    // nécessite la permission spéciale SYSTEM_ALERT_WINDOW.
                    "canDrawOverlays" -> result.success(
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
                            Settings.canDrawOverlays(this) else true
                    )
                    "requestOverlayPermission" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
                            !Settings.canDrawOverlays(this)
                        ) {
                            startActivity(
                                Intent(
                                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                    android.net.Uri.parse("package:$packageName"),
                                )
                            )
                        }
                        result.success(true)
                    }
                    "setThroughputOverlay" -> {
                        val enable = call.argument<Boolean>("enabled") ?: false
                        if (enable) {
                            ThroughputService.prefs(this).edit()
                                .putBoolean(ThroughputService.KEY_OVERLAY, true).apply()
                            ThroughputService.active?.let { svc ->
                                // ensureOverlay est privé : on redémarre le
                                // service, qui recrée l'overlay au démarrage.
                                val intent = Intent(this, ThroughputService::class.java)
                                    .setAction(ThroughputService.ACTION_START)
                                    .putExtra(
                                        ThroughputService.EXTRA_USAGE_BYTES,
                                        ThroughputService.lastTotalBytes,
                                    )
                                ContextCompat.startForegroundService(this, intent)
                            }
                        } else {
                            ThroughputService.prefs(this).edit()
                                .putBoolean(ThroughputService.KEY_OVERLAY, false).apply()
                            // Retirer l'overlay sans tuer le service : simple
                            // hack — onDestroy le retire ; on ne le force pas
                            // ici (le service s'arrêtera bientôt ou l'overlay
                            // restera jusqu'au prochain arrêt/relance).
                        }
                        result.success(true)
                    }
                    "getThroughputOverlay" -> result.success(
                        ThroughputService.prefs(this)
                            .getBoolean(ThroughputService.KEY_OVERLAY, false)
                    )
                    "startCollect" -> {
                        val interval = call.argument<Int>("intervalMinutes")
                            ?: SignalCollectorService.DEFAULT_INTERVAL_MIN
                        val apiBase = call.argument<String>("apiBaseUrl")
                        val deviceId = call.argument<String>("deviceId")
                        result.success(startCollect(interval, apiBase, deviceId))
                    }
                    "stopCollect" -> {
                        stopCollect()
                        result.success(true)
                    }
                    "getCollectStatus" -> result.success(collectStatus())
                    // IMP-01d — Volume de trafic consommé par la collecte
                    // passive en arrière-plan (accumulé par le service natif).
                    "takeBackgroundUsage" -> result.success(takeBackgroundUsage())
                    else -> result.notImplemented()
                }
            }
    }

    /// Retourne true si READ_PHONE_STATE est déjà accordée ; sinon déclenche la
    /// demande runtime (le résultat sera disponible aux prochaines lectures).
    private fun ensurePhonePermission(): Boolean {
        val granted = hasPhonePermission()
        if (!granted) {
            ActivityCompat.requestPermissions(
                this, arrayOf(Manifest.permission.READ_PHONE_STATE), phonePermissionRequestCode
            )
        }
        return granted
    }

    /// Vrai si READ_PHONE_STATE est déjà accordée (lecture de l'état sans
    /// déclencher la demande système).
    private fun hasPhonePermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            this, Manifest.permission.READ_PHONE_STATE
        ) == PackageManager.PERMISSION_GRANTED
    }

    /// La permission de notification n'existe qu'à partir d'Android 13
    /// (TIRAMISU). Avant, elle est considérée comme accordée d'office.
    private fun hasNotificationPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        return ContextCompat.checkSelfPermission(
            this, Manifest.permission.POST_NOTIFICATIONS
        ) == PackageManager.PERMISSION_GRANTED
    }

    /// Demande l'autorisation de notification (Android 13+). Retourne vrai
    /// seulement si elle est accordée après la demande ; la réponse système
    /// étant asynchrone, un false immédiat signifie « demande affichée ».
    private fun requestNotificationPermission(): Boolean {
        if (hasNotificationPermission()) return true
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ActivityCompat.requestPermissions(
                this, arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                notificationPermissionRequestCode,
            )
        }
        return false
    }

    /// Octets reçus par l'application depuis le démarrage de l'appareil, ou -1
    /// si l'appareil ne tient pas ce compteur. Inclut le trafic du WebView : la
    /// pile réseau de Chromium tourne dans le processus de l'app, donc sous le
    /// même UID.
    private fun rxBytes(): Long {
        val bytes = TrafficStats.getUidRxBytes(Process.myUid())
        return if (bytes == TrafficStats.UNSUPPORTED.toLong()) -1L else bytes
    }

    /// IMP-01 : octets émis par l'application depuis le démarrage, ou -1 si le
    /// compteur n'est pas tenu. Même périmètre que [rxBytes] (trafic de l'app,
    /// WebView inclus).
    private fun txBytes(): Long {
        val bytes = TrafficStats.getUidTxBytes(Process.myUid())
        return if (bytes == TrafficStats.UNSUPPORTED.toLong()) -1L else bytes
    }

    /// IMP-01 — Instantané des compteurs de trafic de l'application (tous
    /// réseaux confondus). La répartition mobile vs Wi-Fi est faite côté Dart
    /// par le type de connexion au moment de chaque échantillon
    /// (connectivity_plus) : l'API publique TrafficStats ne sait pas séparer
    /// les compteurs par interface pour un UID donné.
    private fun usageSnapshot(): Map<String, Long> = mapOf(
        "totalRx" to safeCounter { TrafficStats.getUidRxBytes(Process.myUid()) },
        "totalTx" to safeCounter { TrafficStats.getUidTxBytes(Process.myUid()) },
    )

    private inline fun safeCounter(read: () -> Long): Long =
        try {
            val v = read()
            if (v == TrafficStats.UNSUPPORTED.toLong()) -1L else v
        } catch (_: Exception) {
            -1L
        }

    // ── Service de débit temps réel (barre d'état) ──────────────────────────

    /// Démarre le service de débit temps réel. Retourne false si la permission
    /// de notification manque : sans elle, le service de premier plan serait
    /// tué aussitôt.
    private fun startThroughputService(usageBytes: Long): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(
                this, Manifest.permission.POST_NOTIFICATIONS
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            // Mémorise la demande : dès que la permission est accordée
            // (onRequestPermissionsResult), le service démarre tout seul.
            ThroughputService.prefs(this).edit()
                .putBoolean(ThroughputService.KEY_ENABLED, true)
                .putLong(ThroughputService.KEY_LAST_USAGE, usageBytes)
                .apply()
            ActivityCompat.requestPermissions(
                this, arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                notificationPermissionRequestCode,
            )
            return false
        }
        val intent = Intent(this, ThroughputService::class.java)
            .setAction(ThroughputService.ACTION_START)
            .putExtra(ThroughputService.EXTRA_USAGE_BYTES, usageBytes)
        ContextCompat.startForegroundService(this, intent)
        return true
    }

    /// Retour du dialogue système de permission : si l'utilisateur vient
    /// d'accorder les notifications alors que le débit temps réel était
    /// demandé, on redémarre le service automatiquement. Sans cela, le
    /// toggle échouait (permission refusée au premier essai) et rien ne
    /// repartait après l'octroi — l'utilisateur devait désactiver/réactiver
    /// à la main, sans effet.
    override fun onRequestPermissionsResult(
        requestCode: Int, permissions: Array<out String>, grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != notificationPermissionRequestCode) return
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        if (!granted) {
            // Refus : on purge la demande en attente pour ne jamais démarrer
            // le service automatiquement plus tard.
            ThroughputService.prefs(this).edit()
                .putBoolean(ThroughputService.KEY_ENABLED, false).apply()
        } else if (ThroughputService.prefs(this)
            .getBoolean(ThroughputService.KEY_ENABLED, false)
        ) {
            startThroughputService(
                ThroughputService.prefs(this).getLong(ThroughputService.KEY_LAST_USAGE, 0L)
            )
        }
    }

    private fun stopThroughputService() {
        val intent = Intent(this, ThroughputService::class.java)
            .setAction(ThroughputService.ACTION_STOP)
        try {
            startService(intent)
        } catch (_: Exception) {
            // Service déjà arrêté : rien à faire.
        }
    }

    // ── Collecte passive en arrière-plan ────────────────────────────────────

    /// Démarre le service de collecte. Retourne false si la notification est
    /// refusée : sans elle, Android tue immédiatement un service de premier
    /// plan, et la collecte s'arrêterait sans que l'utilisateur comprenne.
    private fun startCollect(intervalMinutes: Int, apiBaseUrl: String?, deviceId: String?): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(
                this, Manifest.permission.POST_NOTIFICATIONS
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            ActivityCompat.requestPermissions(
                this, arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                notificationPermissionRequestCode,
            )
            return false
        }

        SignalCollectorService.prefs(this).edit()
            .putInt(SignalCollectorService.KEY_INTERVAL, intervalMinutes)
            .apply {
                if (apiBaseUrl != null) {
                    putString(SignalCollectorService.KEY_API_BASE, apiBaseUrl)
                }
                // IMP-13 : l'UUID d'appareil est propagé au service de collecte
                // (généré côté Dart, stocké anonymement dans les prefs natives).
                if (!deviceId.isNullOrEmpty()) {
                    putString(SignalCollectorService.KEY_DEVICE_ID, deviceId)
                }
            }
            .apply()

        val intent = Intent(this, SignalCollectorService::class.java)
            .setAction(SignalCollectorService.ACTION_START)
        ContextCompat.startForegroundService(this, intent)
        return true
    }

    private fun stopCollect() {
        val intent = Intent(this, SignalCollectorService::class.java)
            .setAction(SignalCollectorService.ACTION_STOP)
        try {
            startService(intent)
        } catch (e: Exception) {
            // Service déjà arrêté : on met simplement l'état à jour.
            SignalCollectorService.prefs(this).edit()
                .putBoolean(SignalCollectorService.KEY_ENABLED, false).apply()
        }
    }

    /// IMP-01 — Alerte locale de dépassement du seuil mensuel de
    /// consommation. Poste une notification système (canal dédié, Importance
    /// haute pour apparaître en bannière) — sans elle, l'alerte ne serait
    /// visible que dans l'écran Consommation, que l'utilisateur n'ouvre pas
    /// spontanément. Best effort : silencieux si la permission de
    /// notification manque.
    private fun notifyLimitExceeded(title: String, body: String) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                ContextCompat.checkSelfPermission(
                    this, Manifest.permission.POST_NOTIFICATIONS
                ) != PackageManager.PERMISSION_GRANTED
            ) return // sans permission, on ne peut rien poster

            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val channel = NotificationChannel(
                    ALERT_CHANNEL_ID, "Alertes de consommation",
                    NotificationManager.IMPORTANCE_HIGH,
                ).apply {
                    description = "Dépassement du seuil mensuel de données"
                }
                nm.createNotificationChannel(channel)
            }

            val openApp = PendingIntent.getActivity(
                this, 0,
                Intent(this, MainActivity::class.java),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            val notification = androidx.core.app.NotificationCompat.Builder(this, ALERT_CHANNEL_ID)
                .setSmallIcon(android.R.drawable.stat_sys_warning)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(androidx.core.app.NotificationCompat.BigTextStyle().bigText(body))
                .setContentIntent(openApp)
                .setAutoCancel(true)
                .build()
            nm.notify(ALERT_NOTIFICATION_ID, notification)
        } catch (_: Exception) {
        }
    }

    /// IMP-01d — Retourne le volume de trafic accumulé par la collecte
    /// passive en arrière-plan (octets), et remet le compteur à zéro : le
    /// volume est ensuite attribué côté Dart au jour courant de la box Hive.
    private fun takeBackgroundUsage(): Long {
        val p = SignalCollectorService.prefs(this)
        val v = p.getLong(SignalCollectorService.KEY_BG_USAGE_BYTES, 0L)
        if (v != 0L) p.edit().putLong(SignalCollectorService.KEY_BG_USAGE_BYTES, 0L).apply()
        return v
    }

    /// Retourne { running, intervalMinutes, lastCollectAt, count }.
    private fun collectStatus(): Map<String, Any?> {
        val p = SignalCollectorService.prefs(this)
        return mapOf(
            "running" to SignalCollectorService.isRunning,
            "enabled" to p.getBoolean(SignalCollectorService.KEY_ENABLED, false),
            "intervalMinutes" to p.getInt(
                SignalCollectorService.KEY_INTERVAL,
                SignalCollectorService.DEFAULT_INTERVAL_MIN,
            ),
            "lastCollectAt" to p.getLong(SignalCollectorService.KEY_LAST_AT, 0L),
            "count" to p.getInt(SignalCollectorService.KEY_COUNT, 0),
        )
    }

    /// IMP-13 / retour produit : nom commercial du téléphone.
    ///
    /// `Build.MODEL` renvoie souvent un code constructeur (ex. « A059 » pour un
    /// Nothing Phone (3a), « SM-A057F » pour un Galaxy A05s). Le nom marketing
    /// existe pourtant dans les propriétés système `ro.product.marketname`
    /// (Samsung, Xiaomi, Oppo, Tecno, Infinix…) ou `ro.vendor.oplus.marketname`
    /// (Oppo/OnePlus/Realme). On les lit par réflexion sur SystemProperties —
    /// API interne mais stable, en repli sur Build.MODEL.
    private fun deviceMarketingName(): String? {
        val props = listOf(
            "ro.product.marketname",
            "ro.vendor.oplus.marketname",
            "ro.product.odm.marketname",
            "ro.product.system.marketname",
        )
        for (p in props) {
            try {
                val sp = Class.forName("android.os.SystemProperties")
                val get = sp.getMethod("get", String::class.java, String::class.java)
                val v = get.invoke(null, p, "") as? String
                if (!v.isNullOrBlank() && v != "") return v.trim()
            } catch (_: Exception) {
            }
        }
        // Pas de repli sur Build.MODEL ici : c'est souvent un code
        // constructeur (« A059 », « SM-A057F »). On renvoie null pour laisser
        // la table de correspondance Dart proposer le nom commercial.
        return null
    }

    /// Retourne { simOperator, mccMnc, cellularTech } — champs null si indisponible.
    private fun telephonyInfo(): Map<String, Any?> {
        val info = HashMap<String, Any?>()
        info["simOperator"] = null
        info["mccMnc"] = null
        info["cellularTech"] = null

        val tm = getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager ?: return info
        try {
            // Nom de l'opérateur du réseau mobile (SIM enregistrée sur le réseau).
            val name = tm.networkOperatorName?.trim()
            if (!name.isNullOrEmpty()) info["simOperator"] = name

            // MCC+MNC (ex. "61301") — permet un mapping fiable côté Dart.
            val mccMnc = tm.networkOperator?.trim()
            if (!mccMnc.isNullOrEmpty()) info["mccMnc"] = mccMnc
        } catch (e: SecurityException) {
            // Permission manquante : on laisse simOperator/mccMnc à null.
        } catch (e: Exception) {
            // Ignorer toute erreur constructeur.
        }

        // Techno radio : nécessite READ_PHONE_STATE sur Android 10+.
        try {
            @Suppress("DEPRECATION")
            val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                tm.dataNetworkType
            } else {
                tm.networkType
            }
            info["cellularTech"] = techLabel(type)
        } catch (e: SecurityException) {
            // Permission manquante : techno inconnue.
        } catch (e: Exception) {
            // Ignorer.
        }

        return info
    }

    private fun techLabel(type: Int): String? {
        return when (type) {
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
}
