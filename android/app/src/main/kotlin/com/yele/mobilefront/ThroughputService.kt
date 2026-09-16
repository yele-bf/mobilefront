package com.yele.mobilefront

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import android.net.TrafficStats
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.Process
import android.provider.Settings
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

/**
 * Débit temps réel de l'application, affiché en permanence dans la barre
 * d'état (notification de premier plan).
 *
 * Principe : toutes les [POLL_MS] millisecondes, on relit les compteurs de
 * trafic de l'UID de l'application ; la différence entre deux relevés, divisée
 * par le temps écoulé, donne le débit instantané (réception + émission).
 *
 * Le service est désactivé par défaut : c'est le seul élément de l'app qui
 * consomme des ressources en continu. L'utilisateur l'active depuis les
 * Réglages → « Suivi de consommation », et l'arrête au même endroit ou depuis
 * l'action « Arrêter » de la notification.
 *
 * Le service tourne en natif (comme [SignalCollectorService]) : il survit à la
 * fermeture de l'application et ne dépend pas du canal de méthode Flutter.
 */
class ThroughputService : Service() {

    companion object {
        const val ACTION_START = "com.yele.mobilefront.START_THROUGHPUT"
        const val ACTION_STOP = "com.yele.mobilefront.STOP_THROUGHPUT"

        /** Volume déjà consommé ce mois (octets), transmis au démarrage. */
        const val EXTRA_USAGE_BYTES = "usage_bytes"

        const val PREFS = "yele_background"
        const val KEY_ENABLED = "throughput_enabled"

        /** Dernier volume connu (octets) : sert au redémarrage automatique
         *  après octroi de la permission de notification. */
        const val KEY_LAST_USAGE = "throughput_last_usage"

        /** Instance vivante, pour la resynchronisation depuis MainActivity. */
        @Volatile
        var active: ThroughputService? = null
            private set

        /** Période de mesure : 1 s, bon compromis réactivité/batterie. */
        const val POLL_MS = 1_000L

        /** Dernier volume total (rx + tx) lu — partagé vers Flutter si besoin. */
        @Volatile
        var lastTotalBytes: Long = 0L
            private set

        private const val CHANNEL_ID = "yele_throughput"
        private const val NOTIFICATION_ID = 4202

        /** Drapeau de surimpression, lu au démarrage (Réglages → modale). */
        const val KEY_OVERLAY = "throughput_overlay"

        /** Vrai tant que le service tourne ; lu par l'interface via le canal. */
        @Volatile
        var isRunning: Boolean = false
            private set

        fun prefs(context: Context): android.content.SharedPreferences =
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    }

    private val handler = Handler(Looper.getMainLooper())

    private var lastRx = TrafficStats.UNSUPPORTED.toLong()
    private var lastTx = TrafficStats.UNSUPPORTED.toLong()

    /** Horodatage du dernier relevé : SystemClock.elapsedRealtime() — une
     *  seule horloge. (Bug corrigé : onStartCommand initialisait lastAt avec
     *  uptimeMillis() et measure() relisait currentTimeMillis() ; l'écart
     *  entre les deux horloges donnait un elapsed de ~1,7 milliard de ms,
     *  donc un débit toujours égal à 0.) */
    private var lastAt = 0L

    /** Volume de référence (octets), resynchronisé depuis les compteurs de
     *  l'application Flutter. */
    private var baseBytes = 0L

    /** Trafic compté par le service depuis son démarrage (ou la dernière
     *  resynchronisation). */
    private var sessionBytes = 0L

    /** Volume total affiché = base (suivi Flutter) + trafic de la session. */
    private val totalBytes: Long get() = baseBytes + sessionBytes

    /// Compteur en surimpression (taille de l'horloge) — voir
    /// [SpeedOverlayView] pour la raison d'être.
    private var overlayView: SpeedOverlayView? = null
    private var overlayAdded = false

    /** Boucle de mesure : se replanifie tant que le service vit. */
    private val tick = object : Runnable {
        override fun run() {
            measure()
            handler.postDelayed(this, POLL_MS)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        active = this
    }

    /// Resynchronise la base « Données utilisées » sur les compteurs de
    /// l'application (même source que l'écran Consommation) : sans cela la
    /// pastille et l'app divergent — le service compte tout le trafic de
    /// l'UID en continu, l'app n'échantillonne qu'au premier plan.
    fun resyncUsage(usageBytes: Long) {
        baseBytes = usageBytes
        sessionBytes = 0L
        prefs(this).edit().putLong(KEY_LAST_USAGE, usageBytes).apply()
        if (isRunning) {
            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .notify(NOTIFICATION_ID, buildNotification(0, 0))
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopMeasuring()
            return START_NOT_STICKY
        }

        // Android 14+ (targetSdk 34+) exige que le type déclaré ici corresponde
        // exactement au manifeste (dataSync) ET que la permission
        // FOREGROUND_SERVICE_DATA_SYNC soit accordée — sinon startForeground
        // lève une exception et l'application plante. Le try/finally garantit
        // qu'un échec ne laisse jamais l'app dans un état incohérent.
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startForeground(
                    NOTIFICATION_ID, buildNotification(0, 0),
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
                )
            } else {
                startForeground(NOTIFICATION_ID, buildNotification(0, 0))
            }
        } catch (e: Exception) {
            // Permission de notification retirée en vol, ou restriction
            // constructeur : on arrête proprement au lieu de planter.
            android.util.Log.w("YeleThroughput", "startForeground impossible: $e")
            stopSelf()
            return START_NOT_STICKY
        }
        isRunning = true
        prefs(this).edit().putBoolean(KEY_ENABLED, true).apply()

        // Base du volume affiché : le suivi de consommation Flutter (même
        // source que l'écran Consommation) via l'extra START usage — sinon
        // la dernière base connue, sinon 0.
        lastRx = TrafficStats.getUidRxBytes(Process.myUid())
        lastTx = TrafficStats.getUidTxBytes(Process.myUid())
        val saved = intent?.getLongExtra(EXTRA_USAGE_BYTES, -1L) ?: -1L
        baseBytes = if (saved >= 0) {
            prefs(this).edit().putLong(KEY_LAST_USAGE, saved).apply()
            saved
        } else {
            prefs(this).getLong(KEY_LAST_USAGE, 0L)
        }
        sessionBytes = 0L
        lastAt = android.os.SystemClock.elapsedRealtime()

        // Compteur en surimpression : ajouté dès que la permission
        // SYSTEM_ALERT_WINDOW est accordée (avant : la bitmap de notification
        // était forcée par Android à la taille du slot d'icône, trop petite
        // pour être lisible — voir SpeedOverlayView).
        ensureOverlay()

        handler.removeCallbacks(tick)
        handler.post(tick)

        // START_STICKY : si Android tue le processus, le service est recréé —
        // l'utilisateur l'a demandé explicitement.
        return START_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacks(tick)
        isRunning = false
        active = null
        removeOverlay()
        super.onDestroy()
    }

    private fun stopMeasuring() {
        prefs(this).edit().putBoolean(KEY_ENABLED, false).apply()
        handler.removeCallbacks(tick)
        isRunning = false
        removeOverlay()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    /// Ajoute le compteur en surimpression si la permission
    /// SYSTEM_ALERT_WINDOW est accordée. Retourne true si l'overlay est
    /// actif (ou l'était déjà).
    private fun ensureOverlay(): Boolean {
        if (!Settings.canDrawOverlays(this)) return false
        if (overlayAdded && overlayView != null) return true
        try {
            val wm = getSystemService(Context.WINDOW_SERVICE) as android.view.WindowManager
            val metrics = resources.displayMetrics
            val sbh = run {
                val id = resources.getIdentifier("status_bar_height", "dimen", "android")
                if (id != 0) resources.getDimensionPixelSize(id)
                else Math.ceil(24.0 * metrics.density).toInt()
            }
            val params = android.view.WindowManager.LayoutParams(
                android.view.WindowManager.LayoutParams.WRAP_CONTENT,
                sbh,
                android.view.WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
                android.view.WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    android.view.WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                    android.view.WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
                android.graphics.PixelFormat.TRANSLUCENT,
            )
            // Juste après l'horloge, côté gauche (même convention que les
            // speed-meters : compteur à gauche de la barre d'état).
            params.gravity = android.view.Gravity.TOP or android.view.Gravity.START
            params.x = (90 * metrics.density).toInt()
            params.y = 0
            val view = SpeedOverlayView(this)
            wm.addView(view, params)
            overlayView = view
            overlayAdded = true
            return true
        } catch (e: Exception) {
            android.util.Log.w("YeleThroughput", "Overlay impossible: $e")
            overlayAdded = false
            overlayView = null
            return false
        }
    }

    private fun removeOverlay() {
        if (!overlayAdded) return
        try {
            overlayView?.let { (getSystemService(Context.WINDOW_SERVICE) as android.view.WindowManager)
                .removeViewImmediate(it) }
        } catch (_: Exception) {
        }
        overlayView = null
        overlayAdded = false
    }

    /// Retourne le formatage compact du débit — utilisé par l'overlay ET la
    /// notification (mêmes libellés partout).
    private fun speedLabel(kbps: Long): String = fmt(kbps)

    /** Relit les compteurs et met à jour la notification avec le débit. */
    private fun measure() {
        val rx = TrafficStats.getUidRxBytes(Process.myUid())
        val tx = TrafficStats.getUidTxBytes(Process.myUid())
        val now = android.os.SystemClock.elapsedRealtime()


        var downKbps = 0L
        var upKbps = 0L
        if (rx != TrafficStats.UNSUPPORTED.toLong() && lastRx != TrafficStats.UNSUPPORTED.toLong() &&
            tx != TrafficStats.UNSUPPORTED.toLong() && lastTx != TrafficStats.UNSUPPORTED.toLong()
        ) {
            val elapsedMs = (now - lastAt).coerceAtLeast(1)
            downKbps = ((rx - lastRx) * 8_000L / elapsedMs / 1_000L).coerceAtLeast(0)
            upKbps = ((tx - lastTx) * 8_000L / elapsedMs / 1_000L).coerceAtLeast(0)
            // Trafic de la session : delta des compteurs depuis le dernier
            // tick, ajouté à la base resynchronisée depuis l'app.
            sessionBytes +=
                (rx - lastRx).coerceAtLeast(0) + (tx - lastTx).coerceAtLeast(0)
        }

        lastRx = rx
        lastTx = tx
        lastAt = now

        if (isRunning) {
            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .notify(NOTIFICATION_ID, buildNotification(downKbps, upKbps))
            // L'overlay suit le drapeau en temps réel : désactivé côté
            // Réglages, il disparaît au tick suivant (pas besoin de
            // redémarrer le service).
            if (prefs(this).getBoolean(KEY_OVERLAY, false)) {
                overlayView?.update(fmt(downKbps))
            } else removeOverlay()
        }
    }

    // ── Notification ─────────────────────────────────────────────────────────

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Débit temps réel",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Affichage du débit de l'application dans la barre d'état"
            setShowBadge(false)
        }
        (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .createNotificationChannel(channel)
    }

    /** Formatage compact : « 12,4 Mb/s » au-dessus de 1 000 Kb/s. */
    private fun fmt(kbps: Long): String =
        if (kbps >= 1_000) String.format("%.1f Mb/s", kbps / 1_000.0)
        else "$kbps Kb/s"

    /** Formatage d'un volume en octets : Ko, Mo (1 déc.) ou Go (2 déc.).
     *  Base 1024 (Ko/Mio) — IDENTIQUE à formatBytes() côté Dart : l'ancienne
     *  version comptait en base 1000, d'où l'écart apparent entre la pastille
     *  (222,5 Mo) et l'app (212 Mo) alors que les deux valeurs étaient les
     *  mêmes exprimées dans des unités différentes. */
    private fun fmtBytes(bytes: Long): String = when {
        bytes >= 1_073_741_824 -> String.format("%.2f Go", bytes / 1_073_741_824.0)
        bytes >= 1_048_576 -> String.format("%.1f Mo", bytes / 1_048_576.0)
        bytes >= 1_024 -> "${bytes / 1_024} Ko"
        else -> "$bytes o"
    }

    /// Pastille de débit dans la barre d'état : une bitmap « 123 Kb/s »
    /// dessinée à la volée remplace l'icône système (qui était une flèche de
    /// téléchargement sans signification). La bitmap est affichée telle
    /// quelle (pas de teinte monochrome) : le compteur reste lisible même
    /// notification repliée.
    private fun speedIcon(downKbps: Long): android.graphics.drawable.Icon? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return null
        val density = resources.displayMetrics.density
        // Hauteur réelle de la zone d'icône de la barre d'état, lue dans les
        // ressources système (« status_bar_icon_size ») — sinon 24 dp.
        val hPx = run {
            val id = resources.getIdentifier("status_bar_icon_size", "dimen", "android")
            if (id != 0) resources.getDimensionPixelSize(id)
            else (24 * density).toInt()
        }.coerceAtLeast(1)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        }
        // On règle la taille de police pour que la HAUTEUR RÉELLE DES CHIFFRES
        // (cap height, mesurée sur « 0 ») remplisse TOUTE la hauteur de la
        // zone d'icône — même taille apparente que l'horloge. Un simple
        // textSize = h laissait ~30 % de blanc (ascendantes/descendantes de
        // la police), d'où une pastille visuellement minuscule.
        paint.textSize = 100f
        val probe = android.graphics.Rect()
        paint.getTextBounds("0", 0, 1, probe)
        paint.textSize = 100f * hPx / probe.height().coerceAtLeast(1)
        val label = fmt(downKbps)
        val w = paint.measureText(label).toInt() + 2
        val bmp = Bitmap.createBitmap(w, hPx, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        paint.getTextBounds("0", 0, 1, probe)
        // Ligne de base calée pour que les chiffres couvrent exactement
        // 0..hPx verticalement, sans marge.
        canvas.drawText(label, 1f, -probe.top.toFloat(), paint)
        return android.graphics.drawable.Icon.createWithBitmap(bmp)
    }

    private fun buildNotification(downKbps: Long, upKbps: Long): Notification {
        val openApp = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val stop = PendingIntent.getService(
            this, 2,
            Intent(this, ThroughputService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

        lastTotalBytes = totalBytes

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
        // Pastille texte dans la barre d'état (API 23+) ; repli : icône flèche.
        val icon = speedIcon(downKbps)
        if (icon != null) {
            val compat = androidx.core.graphics.drawable.IconCompat.createFromIcon(this, icon)!!
            builder.setSmallIcon(compat)
        } else builder.setSmallIcon(android.R.drawable.stat_sys_download)

        return builder
            .setContentTitle("Yélé — débit temps réel")
            .setContentText("↓ ${fmt(downKbps)}   ↑ ${fmt(upKbps)}   ·   Données : ${fmtBytes(totalBytes)}")
            .setStyle(
                NotificationCompat.BigTextStyle()
                    .bigText(
                        "↓ ${fmt(downKbps)}   ↑ ${fmt(upKbps)}\n" +
                            "Données utilisées (app) : ${fmtBytes(totalBytes)}",
                    ),
            )
            .setContentIntent(openApp)
            .addAction(0, "Arrêter", stop)
            .setOngoing(true)
            .setSilent(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }
}
