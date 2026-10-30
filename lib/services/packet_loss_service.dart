import 'dart:io' show Platform, Process;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:logger/logger.dart';

/// IMP-07 — Perte de paquets vers le serveur de test, en %.
///
/// Méthode principale : la commande `ping` ICMP du système (présente sur
/// Android), [PacketLossService.count] paquets espacés de 200 ms. C'est une
/// vraie perte de paquets, comparable à celle qu'affiche nPerf à côté du
/// ping et de la gigue.
///
/// Repli (iOS, web, ICMP filtré par le réseau) : des sondes HTTP courtes ;
/// une sonde sans réponse sous 2 s compte comme perdue. Ce repli sous-estime
/// la perte réelle, car TCP retransmet les paquets perdus : il ne voit que
/// les pertes assez fortes pour bloquer une requête.
class PacketLossService {
  PacketLossService({this.count = 20});

  final logger = Logger();

  /// Nombre de paquets (ou de sondes) envoyés.
  final int count;

  /// Mesure la perte vers [host]. [httpProbe] envoie une sonde HTTP et lève
  /// une exception si elle échoue ou dépasse son délai. Retourne null si
  /// rien n'a pu être mesuré.
  Future<double?> measure(String host,
      {required Future<void> Function() httpProbe}) async {
    if (!kIsWeb && Platform.isAndroid && host.isNotEmpty) {
      final icmp = await _icmpLoss(host);
      if (icmp != null) return icmp;
    }
    return _httpLoss(httpProbe);
  }

  Future<double?> _icmpLoss(String host) async {
    try {
      final res = await Process.run(
        'ping',
        ['-c', '$count', '-i', '0.2', '-W', '1', host],
      ).timeout(Duration(seconds: count + 10));
      final loss = parsePingLossPercent(res.stdout.toString());
      // 100 % peut vouloir dire « ICMP filtré » plutôt que « réseau coupé » :
      // on retombe alors sur les sondes HTTP.
      if (loss != null && loss < 100) return loss;
    } catch (e) {
      logger.w('ping ICMP indisponible : $e');
    }
    return null;
  }

  Future<double?> _httpLoss(Future<void> Function() probe) async {
    var lost = 0;
    for (var i = 0; i < count; i++) {
      try {
        await probe();
      } catch (_) {
        lost++;
      }
    }
    return lost * 100 / count;
  }
}

/// Lit le pourcentage de perte dans la sortie de `ping`
/// (« 20 packets transmitted, 19 received, 5% packet loss, time 3805ms »).
/// Retourne null si la ligne de synthèse est absente.
double? parsePingLossPercent(String stdout) {
  final m = RegExp(r'([\d.]+)% packet loss').firstMatch(stdout);
  return m == null ? null : double.tryParse(m.group(1)!);
}

/// Affichage commun (bilan, historique) : « 0 % », « 2,5 % ».
String formatPacketLoss(double percent) {
  final text = percent == percent.roundToDouble()
      ? percent.toStringAsFixed(0)
      : percent.toStringAsFixed(1);
  return '${text.replaceAll('.', ',')} %';
}
