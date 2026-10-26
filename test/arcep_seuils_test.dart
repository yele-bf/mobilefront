import 'package:flutter_test/flutter_test.dart';
import 'package:yele/constants/arcep_seuils.dart';

void main() {
  group('Référentiel ARCEP v3', () {
    test('les valeurs validées sont celles de config/seuils.json', () {
      final s = ArcepSeuils.valides;
      expect(s.version, '3');
      expect(s.navigation.pageLoadS, 30);
      expect(s.navigation.pageLoadPct, 95);
      expect(s.navigation.connectionS, 20);
      expect(s.navigation.transferPct, 95);
      expect(s.streaming.preloadS, 5);
      expect(s.streaming.qualityPct, 95);
      expect(s.streaming.rebufferRatioMax, 0.10);
      expect(s.streaming.resolutionMinHeight, 480);
      expect(s.streaming.interruptionsMax, 0);
    });

    test('la réponse API remplace les seuils quand elle les fournit', () {
      final s = ArcepSeuils.fromApiJson({
        'navigation': {'pageLoadSeuilS': 25, 'connectionSeuil': 15},
        'streaming': {
          'preloadSeuilS': 4,
          'rebufferRatioMax': 0.05,
          'resolutionMin': '720p',
          'interruptionsMax': 2,
          'qualityPctReference': 90,
        },
      });
      expect(s.navigation.pageLoadS, 25);
      expect(s.navigation.connectionS, 15);
      expect(s.streaming.preloadS, 4);
      expect(s.streaming.rebufferRatioMax, 0.05);
      expect(s.streaming.resolutionMinHeight, 720);
      expect(s.streaming.interruptionsMax, 2);
      expect(s.streaming.qualityPct, 90);
    });

    test('un champ absent garde la valeur validée, jamais zéro', () {
      final s = ArcepSeuils.fromApiJson({
        'navigation': <String, dynamic>{},
        'streaming': {'preloadSeuilS': 6},
      });
      expect(s.navigation.pageLoadS, 30); // repli validé
      expect(s.navigation.connectionS, 20);
      expect(s.streaming.preloadS, 6); // surcharge lue
      expect(s.streaming.rebufferRatioMax, 0.10);
      expect(s.streaming.resolutionMinHeight, 480);
    });

    test('une réponse vide ne casse pas le référentiel', () {
      final s = ArcepSeuils.fromApiJson(const <String, dynamic>{});
      expect(s.navigation.pageLoadS, ArcepSeuils.valides.navigation.pageLoadS);
      expect(s.streaming.preloadS, ArcepSeuils.valides.streaming.preloadS);
      expect(s.version, ArcepSeuils.valides.version);
    });
  });
}
