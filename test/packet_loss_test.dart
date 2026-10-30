import 'package:flutter_test/flutter_test.dart';
import 'package:yele/services/packet_loss_service.dart';

/// IMP-07 — perte de paquets.
void main() {
  group('parsePingLossPercent (sortie de ping Android)', () {
    test('perte partielle', () {
      const out = '--- 154.0.0.1 ping statistics ---\n'
          '20 packets transmitted, 19 received, 5% packet loss, time 3805ms\n'
          'rtt min/avg/max/mdev = 41.2/58.6/97.1/12.4 ms';
      expect(parsePingLossPercent(out), 5);
    });

    test('perte décimale et perte nulle', () {
      expect(
          parsePingLossPercent(
              '8 packets transmitted, 7 received, 12.5% packet loss'),
          12.5);
      expect(
          parsePingLossPercent(
              '20 packets transmitted, 20 received, 0% packet loss'),
          0);
    });

    test('sortie sans synthèse : non mesurée', () {
      expect(parsePingLossPercent('ping: unknown host'), isNull);
      expect(parsePingLossPercent(''), isNull);
    });
  });

  group('PacketLossService (repli par sondes HTTP)', () {
    test('compte les sondes en échec', () async {
      var n = 0;
      final loss = await PacketLossService(count: 10).measure('',
          httpProbe: () async {
        n++;
        if (n.isEven) throw Exception('délai dépassé');
      });
      expect(loss, 50);
    });

    test('aucune sonde perdue : 0 %', () async {
      final loss = await PacketLossService(count: 4)
          .measure('', httpProbe: () async {});
      expect(loss, 0);
    });
  });

  test('formatPacketLoss', () {
    expect(formatPacketLoss(0), '0 %');
    expect(formatPacketLoss(2.5), '2,5 %');
    expect(formatPacketLoss(100), '100 %');
  });
}
