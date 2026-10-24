package com.yele.mobilefront

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.wifi.WifiManager
import android.os.Build
import android.telephony.CellInfoLte
import android.telephony.CellInfoNr
import android.telephony.CellSignalStrengthLte
import android.telephony.CellSignalStrengthNr
import android.telephony.TelephonyManager
import org.json.JSONObject

/**
 * Extraction des métriques de signal radio, partagée entre le test actif
 * (MainActivity via le canal de méthode) et la collecte passive
 * (SignalCollectorService), pour que les deux chemins produisent les mêmes
 * champs, avec la même convention d'indisponibilité.
 *
 * Clés produites (toutes optionnelles — absentes si l'appareil ne les fournit pas) :
 *  - signalDbm / signalLevel : mesure générique toutes technos (Android 9+) ;
 *  - signalRsrp / signalRsrq : LTE / 4G, référence de la cellule qui sert les
 *    données (RSRP en dBm, RSRQ en dB) ;
 *  - signalNrRsrp / signalNrRsrq : 5G SA (SS-RSRP / SS-RSRQ). En 5G NSA,
 *    l'ancre du téléphone reste en LTE : ce sont alors les champs LTE qui
 *    sont renseignés, et c'est attendu ;
 *  - wifiRssi : RSSI (dBm) du point d'accès Wi-Fi associé.
 *
 * Une valeur indisponible est simplement ABSENTE (et jamais 0) : le backend
 * et le dashboard distinguent ainsi « non mesuré » d'une vraie mesure.
 */
object SignalMetrics {

    /** Liste des clés cellulaires produites par [cellSignal]. */
    val CELL_KEYS = listOf(
        "signalDbm", "signalLevel",
        "signalRsrp", "signalRsrq",
        "signalNrRsrp", "signalNrRsrq",
    )

    /**
     * Métriques de signal cellulaire. Le RSSI/level générique vient de
     * [TelephonyManager.getSignalStrength] ; les métriques typées LTE/NR
     * viennent de la liste des cellules visibles ([TelephonyManager.getAllCellInfo]),
     * dont la première cellule servante correspond au lien de données.
     */
    fun cellSignal(tm: TelephonyManager): JSONObject {
        val out = JSONObject()

        // 1) Mesure générique : marche pour 2G/3G, et sert de repli 4G/5G
        // quand l'appareil ne détaille pas RSRP/RSRQ.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            try {
                tm.signalStrength?.cellSignalStrengths?.firstOrNull()?.let { s ->
                    out.put("signalDbm", s.dbm)
                    out.put("signalLevel", s.level) // 0 (nul) à 4 (excellent)
                }
            } catch (_: Exception) {
            }
        }

        // 2) Métriques typées par technologie. allCellInfo exige la
        // permission de localisation : sans elle, liste vide ou exception,
        // et on garde la seule mesure générique.
        try {
            for (ci in tm.allCellInfo ?: emptyList()) {
                if (ci is CellInfoLte) {
                    val ss: CellSignalStrengthLte = ci.cellSignalStrength
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        val rsrp = ss.rsrp   // dBm, Integer.MAX_VALUE si inconnu
                        val rsrq = ss.rsrq   // dB, Integer.MAX_VALUE si inconnu
                        if (rsrp != Int.MAX_VALUE && !out.has("signalRsrp")) {
                            out.put("signalRsrp", rsrp)
                        }
                        if (rsrq != Int.MAX_VALUE && !out.has("signalRsrq")) {
                            out.put("signalRsrq", rsrq)
                        }
                    }
                } else if (ci is CellInfoNr) {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        val ss = ci.cellSignalStrength as? CellSignalStrengthNr
                        val ssRsrp = ss?.ssRsrp ?: Int.MAX_VALUE
                        val ssRsrq = ss?.ssRsrq ?: Int.MAX_VALUE
                        if (ssRsrp != Int.MAX_VALUE) out.put("signalNrRsrp", ssRsrp)
                        if (ssRsrq != Int.MAX_VALUE) out.put("signalNrRsrq", ssRsrq)
                    }
                }
            }
        } catch (_: SecurityException) {
            // Localisation refusée : pas de détail par cellule.
        } catch (_: Exception) {
            // Constructeur récalcitrant : on garde le générique.
        }
        return out
    }

    /**
     * RSSI du point d'accès Wi-Fi associé, ou null si l'appareil n'est pas
     * associé (Wi-Fi coupé, ou valeur hors plage physique) — un RSSI de 0 ou
     * -127 signifie « pas de mesure fiable », on le traite comme absent.
     */
    @Suppress("DEPRECATION") // connectionInfo : déprécié API 31, toujours fonctionnel ;
    // le remplacement NetworkCallback est asynchrone, inadapté à une lecture ponctuelle.
    fun wifiRssi(context: Context): Int? {
        return try {
            val wm = context.applicationContext
                .getSystemService(Context.WIFI_SERVICE) as? WifiManager
                ?: return null
            val info = wm.connectionInfo ?: return null
            val rssi = info.rssi
            if (wm.isWifiEnabled && rssi in -110..-1) rssi else null
        } catch (_: Exception) {
            null
        }
    }

    /** Vrai si le lien Internet actif de l'appareil est le Wi-Fi. */
    fun isOnWifi(context: Context): Boolean {
        return try {
            val cm = context.applicationContext
                .getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
                ?: return false
            val caps = cm.getNetworkCapabilities(cm.activeNetwork) ?: return false
            caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) &&
                caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)
        } catch (_: Exception) {
            false
        }
    }
}
