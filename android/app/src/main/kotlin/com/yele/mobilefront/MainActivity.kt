package com.yele.mobilefront

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.TrafficStats
import android.os.Build
import android.os.Process
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
