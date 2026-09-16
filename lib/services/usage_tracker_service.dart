import 'dart:async';
import 'dart:io' show Platform;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:logger/logger.dart';

import 'settings_service.dart';

/// IMP-01 — Suivi de la consommation de données de l'application.
///
/// Principe : un échantillonnage périodique des compteurs de trafic natifs
/// (`TrafficStats`, API publique Android — aucune permission requise). Entre
/// deux relevés, la différence de compteurs est le volume réellement
/// transféré ; l'appartenance mobile vs Wi-Fi est déduite du compteur
/// « mobile » natif (interface cellulaire), la part Wi-Fi par différence avec
/// le compteur total.
///
/// Les volumes sont agrégés par jour dans une box Hive (`dataUsage`), avec
/// répartition mobile / Wi-Fi. Le compteur mensuel est recalculé à la volée
/// depuis les jours du mois courant : inutile de stocker un état séparé, le
/// « reset du 1er » est donc automatique.
///
/// iOS n'expose pas ces compteurs : le service reste inactif (`isSupported`
/// false) et l'écran Consommation affiche un message dédié.
class UsageTrackerService {
  final logger = Logger();

  static const String boxName = 'dataUsage';
  static Box? _box;

  /// Période d'échantillonnage quand l'app est au premier plan.
  static const pollInterval = Duration(seconds: 30);

  static UsageTrackerService? _instance;
  static UsageTrackerService get instance => _instance ??= UsageTrackerService();

  Timer? _timer;
  bool _initialized = false;

  // Dernier relevé des compteurs natifs.
  _Snapshot? _last;
  DateTime? _lastAt;

  /// Notifié quand les compteurs du mois changent (écrans + alerte seuil).
  static final ValueNotifier<int> monthlyUsageChanged = ValueNotifier(0);

  static Future<void> initialize() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      if (_box?.isOpen ?? false) return;
      await Hive.initFlutter();
      _box = await Hive.openBox(boxName);
    } catch (e) {
      // Sans stockage local, le suivi se limite à la session courante.
      Logger().e('Ouverture de la box dataUsage impossible: $e');
    }
  }

  bool get isSupported => !kIsWeb && Platform.isAndroid;

  Box get _b {
    final box = _box;
    if (box == null || !box.isOpen) {
      throw StateError('UsageTrackerService doit être initialisé');
    }
    return box;
  }

  // ── Échantillonnage ───────────────────────────────────────────────────────

  /// Démarre l'échantillonnage (appelé au lancement de l'app). Idempotent.
  void startPolling() {
    if (!isSupported || _initialized) return;
    _initialized = true;
    _sample(); // premier relevé de référence, sans volume attribué
    _timer = Timer.periodic(pollInterval, (_) => _sample());
  }

  /// IMP-01c — Relevé immédiat au retour au premier plan (résultat du
  /// didChangeAppLifecycleState). Sans lui, tout le trafic accumulé pendant
  /// que l'app était en arrière-plan serait attribué en bloc au réseau actif
  /// au prochain tick périodique — 2 h de trafic comptées sur le mauvais
  /// réseau. Le relevé au resume fige la coupure à l'instant exact du
  /// changement d'état.
  void onResume() {
    if (!isSupported || !_initialized) return;
    _sample();
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _initialized = false;
  }

  /// IMP-01d — Réintègre le trafic consommé par la collecte passive en
  /// arrière-plan, accumulé nativement par [SignalCollectorService] (compteurs
  /// TrafficStats autour de chaque relève). Le compteur natif est lu et remis
  /// à zéro (« take ») ; le volume est attribué à la journée courante comme
  /// trafic de collecte (répartition mobile/Wi-Fi inconnue en arrière-plan :
  /// compté en mobile uniquement si aucune indication — on reste prudent et on
  /// le compte en Wi-Fi, réseau le plus fréquent au repos ; le total du forfait
  /// reste de toute façon borné par ce que l'opérateur facture réellement).
  Future<void> collectBackgroundUsage() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      final bytes = await MethodChannel('com.yele/telephony')
          .invokeMethod<int>('takeBackgroundUsage');
      if (bytes == null || bytes <= 0) return;
      await _addBytes(bytes, 0); // mobile = 0 → compté en Wi-Fi (indicatif)
      logger.i('Trafic de collecte arrière-plan réintégré: $bytes o');
    } on MissingPluginException {
      // Canal absent (tests) : rien à réintégrer.
    } catch (e) {
      logger.w('Réintégration du trafic de collecte impossible: $e');
    }
  }

  /// Un relevé : différence de compteurs depuis le précédent, attribuée au
  /// type de connexion actif au moment du relevé (mobile ou Wi-Fi). Un
  /// basculement de réseau au milieu d'un intervalle est compté sur le réseau
  /// d'arrivée : l'erreur est bornée à 30 s de trafic, négligeable.
  Future<void> _sample() async {
    final snap = await _readSnapshot();
    if (snap == null) return;
    final prev = _last;
    final prevAt = _lastAt;
    _last = snap;
    _lastAt = DateTime.now();
    if (prev == null || prevAt == null) return;

    final deltaRx = _delta(prev.totalRx, snap.totalRx);
    final deltaTx = _delta(prev.totalTx, snap.totalTx);
    if (deltaRx < 0 || deltaTx < 0) return; // compteur remis à zéro (reboot)
    final total = deltaRx + deltaTx;
    if (total <= 0) return;

    // Type de connexion actif : mobile, Wi-Fi, ou inconnu (ethernet, VPN…).
    final kind = await _activeNetwork();
    final mobile = switch (kind) {
      _NetworkKind.mobile => total,
      _NetworkKind.other => -1,
      _NetworkKind.wifi => 0,
    };

    await _addBytes(total, mobile);
  }

  Future<_NetworkKind> _activeNetwork() async {
    try {
      final results = await Connectivity().checkConnectivity();
      if (results.contains(ConnectivityResult.mobile)) {
        return _NetworkKind.mobile;
      }
      if (results.contains(ConnectivityResult.wifi) ||
          results.contains(ConnectivityResult.ethernet)) {
        return _NetworkKind.wifi;
      }
      return _NetworkKind.other;
    } catch (_) {
      return _NetworkKind.other;
    }
  }

  int _delta(int? before, int? after) {
    if (before == null || after == null || before < 0) return -1;
    return after - before;
  }

  Future<void> _addBytes(int total, int mobile) async {
    final now = DateTime.now();
    final key = _dayKey(now);
    try {
      final raw = _b.get(key);
      final day = raw is Map
          ? Map<String, dynamic>.from(raw)
          : <String, dynamic>{};
      day['total'] = ((day['total'] as num?)?.toInt() ?? 0) + total;
      if (mobile >= 0) {
        day['mobile'] = ((day['mobile'] as num?)?.toInt() ?? 0) + mobile;
        day['wifi'] = ((day['wifi'] as num?)?.toInt() ?? 0) + (total - mobile);
      }
      await _b.put(key, day);
      monthlyUsageChanged.value = monthlyTotalBytes;
      await _checkMonthlyLimit();
    } catch (e) {
      logger.w('Écriture de la consommation impossible: $e');
    }
  }

  /// Relevé des compteurs natifs. null si l'appareil ne les tient pas.
  Future<_Snapshot?> _readSnapshot() async {
    try {
      final info = await MethodChannel('com.yele/telephony')
          .invokeMapMethod<String, dynamic>('getUsageSnapshot');
      if (info == null) return null;
      return _Snapshot(
        totalRx: (info['totalRx'] as num?)?.toInt() ?? -1,
        totalTx: (info['totalTx'] as num?)?.toInt() ?? -1,
      );
    } on MissingPluginException {
      return null;
    } catch (_) {
      return null;
    }
  }

  // ── Lecture des agrégats ──────────────────────────────────────────────────

  static String _dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  DayUsage _readDay(DateTime d) {
    try {
      final raw = _b.get(_dayKey(d));
      if (raw is! Map) return DayUsage.zero;
      final m = Map<String, dynamic>.from(raw);
      return DayUsage(
        total: (m['total'] as num?)?.toInt() ?? 0,
        mobile: (m['mobile'] as num?)?.toInt() ?? 0,
        wifi: (m['wifi'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return DayUsage.zero;
    }
  }

  DayUsage today() => _readDay(DateTime.now());

  DayUsage currentWeek() {
    final now = DateTime.now();
    // Semaine débutant lundi (convention française).
    final monday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    var t = 0, m = 0, w = 0;
    for (var d = monday; !d.isAfter(now); d = d.add(const Duration(days: 1))) {
      final u = _readDay(d);
      t += u.total;
      m += u.mobile;
      w += u.wifi;
    }
    return DayUsage(total: t, mobile: m, wifi: w);
  }

  DayUsage currentMonth() {
    final now = DateTime.now();
    var t = 0, m = 0, w = 0;
    for (var d = DateTime(now.year, now.month, 1);
        !d.isAfter(now);
        d = d.add(const Duration(days: 1))) {
      final u = _readDay(d);
      t += u.total;
      m += u.mobile;
      w += u.wifi;
    }
    return DayUsage(total: t, mobile: m, wifi: w);
  }

  int get monthlyTotalBytes => currentMonth().total;

  // ── Alerte de seuil mensuel ───────────────────────────────────────────────

  /// Dernier mois pour lequel l'alerte a été levée (une seule alerte par
  /// mois, et jamais deux fois de suite à chaque échantillon).
  static String? _lastAlertedMonth;

  /// Alerte locale au franchissement du seuil mensuel configuré dans les
  /// Réglages. Le seuil porte sur le total (mobile + Wi-Fi n'y est pour rien :
  /// seule l'interface mobile compte pour le forfait, mais l'opérateur facture
  /// ce que l'app consomme hors Wi-Fi — on garde le total affiché, l'alerte
  /// porte sur la part mobile quand elle est mesurable).
  Future<void> _checkMonthlyLimit() async {
    try {
      final limitGb = SettingsService().monthlyLimitGb;
      if (limitGb <= 0) return;
      final limitBytes = (limitGb * 1024 * 1024 * 1024).round();
      final month = currentMonth();
      final base = month.mobile > 0 ? month.mobile : month.total;
      if (base < limitBytes) return;

      final now = DateTime.now();
      final monthKey = '${now.year}-${now.month.toString().padLeft(2, '0')}';
      if (_lastAlertedMonth == monthKey) return;
      _lastAlertedMonth = monthKey;
      limitExceeded = true;
      limitExceededNotifier.value = true;
      logger.i('Seuil mensuel de consommation dépassé ($limitGb Go)');
      // Alerte système : la notification reste le seul moyen d'atteindre
      // l'utilisateur qui n'ouvre pas l'écran Consommation au bon moment.
      await _notifyLimitExceeded(limitGb);
    } catch (_) {
      // Réglages non initialisés (tests) : pas d'alerte.
    }
  }

  /// Notification système de dépassement (Android) : passe par le canal
  /// natif — Flutter seul ne peut pas poster de notification sans plugin
  /// externe. Silencieux en cas d'échec (permission refusée, tests…).
  Future<void> _notifyLimitExceeded(double limitGb) async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      final used = formatBytes(currentMonth().total);
      await MethodChannel('com.yele/telephony').invokeMethod(
        'notifyLimitExceeded',
        {
          'title': 'Yélé — seuil de consommation atteint',
          'body': 'Vous avez consommé $used ce mois-ci, soit plus que le '
              'seuil de ${formatGb(limitGb)} Go configuré dans les '
              'réglages.',
        },
      );
    } on MissingPluginException {
      // Tests ou canal indisponible : l'alerte reste visible dans l'écran.
    } catch (e) {
      logger.w('Notification de seuil impossible: $e');
    }
  }

  /// Vrai si le seuil du mois courant a été franchi (lus par l'écran
  /// Consommation pour afficher le bandeau d'alerte).
  static bool limitExceeded = false;
  static final ValueNotifier<bool> limitExceededNotifier =
      ValueNotifier(false);

  /// Série journalière du mois courant (1er → aujourd'hui), pour le graphique.
  List<DayUsage> monthSeries() {
    final now = DateTime.now();
    final out = <DayUsage>[];
    for (var d = DateTime(now.year, now.month, 1);
        !d.isAfter(now);
        d = d.add(const Duration(days: 1))) {
      out.add(_readDay(d));
    }
    return out;
  }

  /// Purge des jours de plus de 13 mois (taille de la box bornée).
  Future<void> pruneOldDays() async {
    try {
      final cutoff = DateTime.now().subtract(const Duration(days: 400));
      final cutoffKey = _dayKey(cutoff);
      final doomed = _b.keys
          .whereType<String>()
          .where((k) => k.compareTo(cutoffKey) < 0)
          .toList();
      await _b.deleteAll(doomed);
    } catch (_) {}
  }
}

/// Instantané des compteurs natifs (octets cumulés depuis le boot).
class _Snapshot {
  final int totalRx, totalTx;
  const _Snapshot({required this.totalRx, required this.totalTx});
}

enum _NetworkKind { mobile, wifi, other }

/// Volumes d'une journée (ou d'une somme de journées), en octets.
class DayUsage {
  final int total;
  final int mobile;
  final int wifi;

  const DayUsage({required this.total, required this.mobile, required this.wifi});

  static const zero = DayUsage(total: 0, mobile: 0, wifi: 0);
}

/// Formatage d'un seuil en Go : sans décimale si entier, une décimale sinon
/// (« 1 Go », « 0,5 Go ») — toStringAsFixed(0) arrondissait 0,5 à « 1 ».
String formatGb(double gb) =>
    gb % 1 == 0 ? gb.toStringAsFixed(0) : gb.toStringAsFixed(1).replaceAll('.', ',');

/// Formatage lisible d'un volume en octets : Ko, Mo ou Go.
String formatBytes(int bytes) {
  if (bytes < 0) return '—';
  const kib = 1024;
  if (bytes < kib * kib) return '${(bytes / kib).round()} Ko';
  if (bytes < kib * kib * kib) {
    final mo = bytes / (kib * kib);
    return '${mo >= 100 ? mo.round() : mo.toStringAsFixed(1)} Mo';
  }
  final go = bytes / (kib * kib * kib);
  return '${go.toStringAsFixed(2)} Go';
}
