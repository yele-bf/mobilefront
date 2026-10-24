import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yele/services/streaming_test_service.dart';

void main() {
  group('StreamingQualityResult.displayLabel', () {
    test('mesure présente : libellé de la qualité servie', () {
      const r = StreamingQualityResult(
        label: '2160p',
        reached: true,
        servedLabel: '1440p',
      );
      expect(r.displayLabel, '1440p');
    });

    test('palier sans mesure : libellé de la qualité demandée', () {
      const r = StreamingQualityResult.unavailable('2160p');
      expect(r.displayLabel, '2160p');
    });

    test('qualité servie = demandée : libellé inchangé', () {
      const r = StreamingQualityResult(label: '1080p', reached: true);
      expect(r.displayLabel, '1080p');
    });
  });

  group('StreamingQualityResult.servedHeight', () {
    test('qualité servie différente de la qualité demandée', () {
      const r = StreamingQualityResult(
        label: '2160p',
        reached: true,
        servedLabel: '1440p',
      );
      expect(r.height, 2160); // demandée
      expect(r.servedHeight, 1440); // réellement servie
    });

    test('qualité servie identique : servedHeight = height', () {
      const r = StreamingQualityResult(label: '1080p', reached: true);
      expect(r.servedHeight, 1080);
    });

    test('libellé servi non numérique : repli sur la qualité demandée', () {
      // _qualityLabel('unknown') → 'inconnue' : pas de hauteur exploitable.
      const r = StreamingQualityResult(
        label: '720p',
        reached: true,
        servedLabel: 'inconnue',
      );
      expect(r.servedHeight, 720);
    });
  });

  group('StreamingQualityResult JSON', () {
    test('aller-retour avec servedLabel', () {
      const r = StreamingQualityResult(
        label: '2160p',
        reached: true,
        performanceRate: 71.93,
        initialLoadingSec: 2.273,
        bufferingSec: 1.243,
        rebufferCount: 1,
        dataUsedKiB: 17171,
        stable: false,
        servedLabel: '1440p',
      );
      final back = StreamingQualityResult.fromJson(
          jsonDecode(jsonEncode(r.toJson())) as Map<String, dynamic>);
      expect(back.label, r.label);
      expect(back.reached, r.reached);
      expect(back.performanceRate, r.performanceRate);
      expect(back.servedLabel, '1440p');
      expect(back.stable, false);
    });

    test('servedLabel omis quand la qualité servie = demandée', () {
      const r = StreamingQualityResult(label: '1080p', reached: true);
      expect(r.toJson().containsKey('servedLabel'), isFalse);
    });

    test('anciens résultats sans servedLabel : décodage inchangé', () {
      final back = StreamingQualityResult.fromJson({
        'label': '1080p',
        'reached': true,
        'performanceRate': 90.0,
        'dataUsedKiB': 4096,
      });
      expect(back.servedLabel, isEmpty);
      expect(back.servedHeight, 1080);
    });
  });

  group('StreamingTestResult.decodeQualities', () {
    test('enveloppe {rows, error} avec servedLabel', () {
      const payload = '{"rows":['
          '{"label":"720p","reached":true,"servedLabel":"480p"},'
          '{"label":"1080p","reached":false}'
          ']}';
      final rows = StreamingTestResult.decodeQualities(payload);
      expect(rows, hasLength(2));
      expect(rows[0].servedLabel, '480p');
      expect(rows[0].servedHeight, 480);
      expect(rows[1].servedLabel, isEmpty);
      expect(rows[1].reached, isFalse);
    });

    test('liste nue des premières versions toujours lisible', () {
      const payload =
          '[{"label":"720p","reached":true},{"label":"1080p","reached":true}]';
      final rows = StreamingTestResult.decodeQualities(payload);
      expect(rows, hasLength(2));
      expect(rows.every((r) => r.servedLabel.isEmpty), isTrue);
    });
  });
}
