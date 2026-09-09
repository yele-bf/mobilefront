import 'package:flutter/services.dart';

/// Compteur d'octets reçus/émis par l'application, lu via `TrafficStats`
/// (Android).
///
/// Sert à mesurer la consommation de données d'un test (IMP-01) : on relève
/// les compteurs avant et après le test, la différence est le volume réellement
/// transféré (rx + tx). Le trafic du WebView est inclus : sur Android, la pile
/// réseau de Chromium tourne dans le processus de l'application, donc sous le
/// même UID.
///
/// iOS n'expose aucun équivalent propre : [rxBytes]/[txBytes] y retournent
/// null et la « données consommées » affiche « — ».
class TrafficStatsService {
  static const MethodChannel _channel = MethodChannel('com.yele/telephony');

  /// Octets reçus par l'application depuis le démarrage de l'appareil.
  /// null si la plateforme ne sait pas le fournir.
  Future<int?> rxBytes() async => _readCounter('getRxBytes');

  /// Octets émis par l'application depuis le démarrage de l'appareil.
  /// null si la plateforme ne sait pas le fournir.
  Future<int?> txBytes() async => _readCounter('getTxBytes');

  Future<int?> _readCounter(String method) async {
    try {
      final value = await _channel.invokeMethod<int>(method);
      if (value == null || value < 0) return null;
      return value;
    } catch (_) {
      // Canal absent (iOS, tests) ou compteur indisponible.
      return null;
    }
  }

  /// Volume transféré entre deux relevés, en kibioctets. -1 si non mesurable.
  static int kibBetween(int? before, int? after) {
    if (before == null || after == null || after < before) return -1;
    return ((after - before) / 1024).round();
  }
}

/// IMP-01 — Capture de la consommation data d'un test complet.
///
/// Usage : [start] juste avant le début du test, [stopKiB] à la fin ; la
/// valeur retournée est le total rx + tx en kibioctets, ou -1 si l'appareil
/// ne tient pas les compteurs (iOS, émulateur exotique…).
class DataUsageCapture {
  final TrafficStatsService _stats;
  int? _rxBefore;
  int? _txBefore;

  DataUsageCapture([TrafficStatsService? stats]) : _stats = stats ?? TrafficStatsService();

  /// Relevé initial des compteurs rx et tx.
  Future<void> start() async {
    _rxBefore = await _stats.rxBytes();
    _txBefore = await _stats.txBytes();
  }

  /// Total consommé depuis [start] (réception + émission), en KiB.
  /// -1 si l'un des compteurs n'a pas pu être lu.
  Future<int> stopKiB() async {
    final rxAfter = await _stats.rxBytes();
    final txAfter = await _stats.txBytes();
    final rx = TrafficStatsService.kibBetween(_rxBefore, rxAfter);
    final tx = TrafficStatsService.kibBetween(_txBefore, txAfter);
    if (rx < 0 && tx < 0) return -1;
    // Un seul compteur valide reste significatif : on le garde.
    if (rx < 0) return tx;
    if (tx < 0) return rx;
    return rx + tx;
  }
}
