import 'package:flutter_test/flutter_test.dart';
import 'package:yele/models/speed_test_result.dart';
import 'package:yele/services/dashboard_api_service.dart';

/// IMP-09 — baromètre : comparaison parmi les clients du même opérateur.
void main() {
  group('BarometerResult.fromJson', () {
    test('réponse complète avec comparaison par opérateur', () {
      final b = BarometerResult.fromJson({
        'downloadPercentile': 40,
        'uploadPercentile': 55.5,
        'pingPercentile': 62,
        'sampleSize': 748,
        'nationalAvgDownload': 32.5,
        'operator': 'Orange',
        'operatorSampleSize': 206,
        'operatorDownloadPercentile': 66.67,
        'operatorUploadPercentile': 70,
        'operatorPingPercentile': 48,
        'operatorAvgDownload': 17.5,
      });
      expect(b.downloadPercentile, 40);
      expect(b.nationalAvgDownload, 32.5);
      expect(b.operator, 'Orange');
      expect(b.operatorSampleSize, 206);
      expect(b.operatorDownloadPercentile, 66.67);
      expect(b.operatorAvgDownload, 17.5);
      expect(b.hasOperatorComparison, isTrue);
    });

    test('ancienne réponse du serveur : pas de comparaison par opérateur', () {
      final b = BarometerResult.fromJson({
        'downloadPercentile': 40,
        'uploadPercentile': 50,
        'pingPercentile': 60,
        'sampleSize': 100,
      });
      expect(b.operator, isNull);
      expect(b.hasOperatorComparison, isFalse);
    });

    test('trop peu de mesures de l\'opérateur : bloc masqué', () {
      final b = BarometerResult.fromJson({
        'sampleSize': 100,
        'operator': 'Telecel',
        'operatorSampleSize': BarometerResult.minOperatorSample - 1,
      });
      expect(b.hasOperatorComparison, isFalse);
    });
  });

  group('barometerOperatorOf', () {
    SpeedTestResult r({String? net, String? sim, String? isp}) =>
        SpeedTestResult(
          downloadSpeed: 10,
          uploadSpeed: 2,
          ping: 40,
          jitter: 5,
          server: 's',
          networkType: net,
          simOperator: sim,
          operator: isp,
        );

    test('données mobiles : opérateur de la SIM', () {
      expect(barometerOperatorOf(r(net: '4G', sim: 'Orange BF', isp: 'ONATEL')),
          'Orange BF');
    });

    test('Wi-Fi : fournisseur d\'accès, même si une SIM est présente', () {
      expect(barometerOperatorOf(r(net: 'WiFi', sim: 'Orange BF', isp: 'Canalbox')),
          'Canalbox');
    });

    test('rien de connu : pas d\'opérateur', () {
      expect(barometerOperatorOf(r(net: '4G')), isNull);
    });
  });
}
