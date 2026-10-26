import 'package:flutter_test/flutter_test.dart';
import 'package:yele/services/streaming_shared.dart';
import 'package:yele/services/streaming_test_service.dart';

void main() {
  group('Performance globale : moyenne des taux des qualités servies', () {
    test('moyenne simple sur les 3 paliers servis', () {
      final rows = [
        const StreamingQualityResult(
            label: '720p', reached: true, performanceRate: 98.0),
        const StreamingQualityResult(
            label: '1080p', reached: true, performanceRate: 95.0),
        const StreamingQualityResult(
            label: '2160p', reached: true, performanceRate: 90.0),
      ];
      final r = aggregateStreamingResults(rows);
      // (98 + 95 + 90) / 3 = 94,333… arrondi à 1 décimale au stockage.
      expect(r.score, 94.3);
    });

    test('les paliers non servis ne tirent pas la moyenne vers 0', () {
      // Réseau qui ne tient pas le 4K : la performance reste celle des
      // paliers réellement mesurés (règle nPerf), le « — » ne compte pas.
      final rows = [
        const StreamingQualityResult(
            label: '720p', reached: true, performanceRate: 98.0),
        const StreamingQualityResult.unavailable('1080p'),
        const StreamingQualityResult.unavailable('2160p'),
      ];
      final r = aggregateStreamingResults(rows);
      expect(r.score, 98.0);
    });

    test('aucune qualité servie : performance globale 0', () {
      final r = aggregateStreamingResults([
        const StreamingQualityResult.unavailable('720p'),
        const StreamingQualityResult.unavailable('1080p'),
        const StreamingQualityResult.unavailable('2160p'),
      ]);
      expect(r.score, 0.0);
    });

    test('une mesure dont la qualité a changé (YouTube) compte comme servie', () {
      // reached=true + stable=false : la mesure est indicative mais réelle,
      // elle participe à la moyenne comme les autres.
      final rows = [
        const StreamingQualityResult(
          label: '2160p',
          reached: true,
          stable: false,
          servedLabel: '1440p',
          performanceRate: 80.0,
        ),
      ];
      final r = aggregateStreamingResults(rows);
      expect(r.score, 80.0);
    });

    test('les autres indicateurs restent mesurés comme avant', () {
      final rows = [
        const StreamingQualityResult(
          label: '720p',
          reached: true,
          performanceRate: 98.0,
          initialLoadingSec: 0.8,
          bufferingSec: 0.2,
          rebufferCount: 1,
          dataUsedKiB: 2500,
        ),
        const StreamingQualityResult.unavailable('1080p'),
      ];
      final r = aggregateStreamingResults(rows);
      // 98 × 0,85 : la définition Yélé exige 0 interruption, chacune coûte
      // 15 % de la note (IMP-06).
      expect(r.score, 83.3);
      expect(r.startupMs, 800); // inchangé
      expect(r.rebufferCount, 1); // inchangé
      expect(r.maxResolution, '720p'); // inchangé
      expect(r.rebufferRatio, greaterThan(0)); // inchangé
    });
  });
}
