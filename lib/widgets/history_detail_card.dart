import 'package:flutter/material.dart';

import '../models/speed_test_result.dart';
import '../services/reverse_geocoding_service.dart';
import '../theme/yele_theme.dart';

/// Carte de détail d'un test de l'historique (panneau vert sous la ligne
/// dépliable) : serveur, FAI, réseau, latence, signal, streaming, navigation,
/// coordonnées.
///
/// Extrait de [HistoryScreen] (même rendu, aucun changement visuel) pour être
/// testable isolément : le test widget fournit un [SpeedTestResult] et la map
/// d'adresses déjà résolues, sans base locale ni réseau.
class HistoryDetailCard extends StatelessWidget {
  final SpeedTestResult result;

  /// Adresses résolues par géocodage inversé, indexées par clé de cache
  /// ([ReverseGeocodingService.cacheKeyFor]) : valeur null = résolution en
  /// cours, '' = aucune adresse OSM connue à ces coordonnées.
  final Map<String, String?> resolvedAddresses;

  const HistoryDetailCard({
    super.key,
    required this.result,
    required this.resolvedAddresses,
  });

  @override
  Widget build(BuildContext context) {
    Widget line(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('$k :',
                  style: const TextStyle(color: Color(0xFF1F3A00), fontSize: 12)),
              Flexible(
                child: Text(v,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        color: Color(0xFF1F3A00),
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        );

    return Container(
      width: double.infinity,
      color: YeleColors.testMid,
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          line('Serveur', result.server),
          line('FAI', result.operator ?? '—'),
          // Règle métier : le réseau mobile (SIM) n'est montré que pour un test
          // fait avec la carte SIM ; en Wi-Fi la ligne est masquée, même si
          // d'anciens enregistrements contiennent encore ces champs.
          if (!(result.networkType ?? '').toUpperCase().contains('WIFI') &&
              ((result.simOperator ?? '').isNotEmpty ||
                  (result.cellularTech ?? '').isNotEmpty))
            line(
                'Réseau mobile',
                [result.cellularTech, result.simOperator]
                    .where((e) => (e ?? '').isNotEmpty)
                    .join(' · ')),
          line('Réseau', result.location ?? '—'),
          line('Latence', '${result.ping.toStringAsFixed(0)} ms'),
          line('Gigue', '${result.jitter.toStringAsFixed(0)} ms'),
          ..._signalLines(result, line),
          if (result.hasStreamingTest)
            line('Streaming',
                '${result.streamingMaxResolution ?? '—'} · ${result.streamingScore!.toStringAsFixed(0)}/100'),
          if (result.hasBrowsingTest)
            line('Navigation',
                '${(result.browsingAvgLoadMs! / 1000).toStringAsFixed(1)} s · ${result.browsingScore!.toStringAsFixed(0)}/100'),
          if ((result.latitude ?? 0) != 0) ..._coordBlock(result, line),
          if (result.qoeRating != null && result.qoeRating! > 0)
            line('QoE', '${result.qoeRating}/5'),
        ],
      ),
    );
  }

  /// Lignes « Signal » / « Qualité du signal » : métriques radio typées selon
  /// la connexion utilisée pour le test, une métrique par ligne — la puissance
  /// (RSRP/NR RSRP/RSSI) sur « Signal », la qualité (RSRQ/NR RSRQ) sur
  /// « Qualité du signal ». Rien ne s'affiche si rien n'a été mesuré (iOS,
  /// Android < 9, appareils qui n'exposent pas les compteurs).
  List<Widget> _signalLines(
      SpeedTestResult r, Widget Function(String k, String v) line) {
    // Seuils et libellés alignés sur le tableau de référence qualité signal
    // (IUT) : RSRP −80/−95/−105, RSRQ −10/−15/−18, RSSI −65/−75/−85 →
    // Excellent / Bon-Moyen / Acceptable / Mauvais-Faible.
    String qualityLabel(int dbm, {required bool isRsrp}) {
      final t = isRsrp ? [-80, -95, -105] : [-65, -75, -85];
      if (dbm >= t[0]) return 'Excellent';
      if (dbm >= t[1]) return 'Bon/Moyen';
      if (dbm >= t[2]) return 'Acceptable';
      return 'Mauvais/Faible';
    }

    final lines = <Widget>[];

    // Puissance (dBm), avec libellé de qualité.
    if ((r.signalRsrp ?? 0) != 0) {
      lines.add(line('Signal',
          'RSRP ${r.signalRsrp} dBm (${qualityLabel(r.signalRsrp!, isRsrp: true)})'));
    }
    if ((r.signalNrRsrp ?? 0) != 0) {
      lines.add(line('Signal', 'NR RSRP ${r.signalNrRsrp} dBm'));
    }
    if ((r.wifiRssi ?? 0) != 0) {
      lines.add(line('Signal',
          'RSSI ${r.wifiRssi} dBm (${qualityLabel(r.wifiRssi!, isRsrp: false)})'));
    }

    // Qualité (dB), ligne dédiée « Qualité du signal ».
    if ((r.signalRsrq ?? 0) != 0) {
      lines.add(line('Qualité du signal', 'RSRQ ${r.signalRsrq} dB'));
    }
    if ((r.signalNrRsrq ?? 0) != 0) {
      lines.add(line('Qualité du signal', 'NR RSRQ ${r.signalNrRsrq} dB'));
    }

    // Repli : mesure générique seule, si aucune métrique typée n'est
    // disponible — affichée sur « Signal » sans libellé de qualité.
    if (lines.isEmpty && (r.signalDbm ?? 0) != 0) {
      lines.add(line('Signal', '${r.signalDbm} dBm'));
    }
    return lines;
  }

  /// Ligne(s) « Coord. » : adresse lisible (géocodage inversé Nominatim) avec
  /// les coordonnées brutes en sous-texte. Tant que la résolution est en
  /// cours, un indicateur discret s'affiche ; en cas d'échec ou d'absence
  /// d'adresse OSM, on retombe sur les seules coordonnées.
  List<Widget> _coordBlock(
      SpeedTestResult r, Widget Function(String k, String v) line) {
    final key = ReverseGeocodingService.cacheKeyFor(r.latitude!, r.longitude!);
    final address = resolvedAddresses[key];
    final coords =
        '${r.latitude!.toStringAsFixed(4)}, ${r.longitude!.toStringAsFixed(4)}';
    if (address == null) {
      // Résolution en cours.
      return [line('Coord.', '$coords — résolution…')];
    }
    if (address.isEmpty) {
      // Aucune adresse OSM connue à ces coordonnées.
      return [line('Coord.', coords)];
    }
    return [
      line('Coord. (adresse)', address),
      line('Coordonnées', coords),
    ];
  }
}
