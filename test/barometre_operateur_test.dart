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

  group('BarometerResult.fromJson v2', () {
    test('réponse complète : médianes, rangs, sous-groupes, tendance', () {
      final b = BarometerResult.fromJson({
        'downloadPercentile': 40,
        'uploadPercentile': 50,
        'pingPercentile': 60,
        'sampleSize': 56,
        'medianDownload': 27.5,
        'medianUpload': 5.5,
        'medianPing': 35,
        'downloadRank': 5,
        'uploadRank': 12,
        'pingRank': 8,
        'streamingPercentile': 50,
        'browsingPercentile': 75,
        'operator': 'Orange',
        'operatorSampleSize': 40,
        'operatorAvgDownload': 19,
        'operatorTech': '4G',
        'operatorTechSampleSize': 12,
        'operatorTechDownloadPercentile': 50,
        'operatorTechUploadPercentile': 60,
        'operatorTechPingPercentile': 70,
        'zoneSampleSize': 11,
        'zoneDownloadPercentile': 36.36,
        'zoneUploadPercentile': 45,
        'zonePingPercentile': 55,
        'recentDownloads': [20, 18, 16, 14, 12],
        'networkType': 'wifi',
      });
      expect(b.medianDownload, 27.5);
      expect(b.medianPing, 35);
      expect(b.downloadRank, 5);
      expect(b.pingRank, 8);
      expect(b.streamingPercentile, 50);
      expect(b.operatorTech, '4G');
      expect(b.hasOperatorTechComparison, isTrue);
      expect(b.hasZoneComparison, isTrue);
      expect(b.hasTrend, isTrue);
      expect(b.recentDownloads.first, 20);
      expect(b.networkType, 'wifi');
    });

    test('réponse ancienne (v1) : nouveaux champs à zéro, blocs masqués', () {
      final b = BarometerResult.fromJson({
        'downloadPercentile': 40,
        'sampleSize': 56,
      });
      expect(b.medianDownload, 0);
      expect(b.downloadRank, 0);
      expect(b.operatorTech, isNull);
      expect(b.hasOperatorTechComparison, isFalse);
      expect(b.hasZoneComparison, isFalse);
      expect(b.hasTrend, isFalse);
      expect(b.recentDownloads, isEmpty);
    });

    test('sous-groupes trop petits : blocs masqués', () {
      final b = BarometerResult.fromJson({
        'sampleSize': 56,
        'operatorTech': '4G',
        'operatorTechSampleSize': BarometerResult.minSubgroupSample - 1,
        'zoneSampleSize': BarometerResult.minSubgroupSample - 1,
        'recentDownloads': [18],
      });
      expect(b.hasOperatorTechComparison, isFalse);
      expect(b.hasZoneComparison, isFalse);
      expect(b.hasTrend, isFalse); // un seul test : pas de tendance
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
