import 'package:flutter_test/flutter_test.dart';
import 'package:yele/services/streaming_shared.dart';
import 'package:yele/services/streaming_test_service.dart';
import 'package:yele/services/streaming_test_service_hls.dart';

void main() {
  group('matchLevelForHeight (sélection du niveau dans le manifeste)', () {
    const ladder = [
      StreamLevel(index: 0, height: 360, bitrate: 800_000),
      StreamLevel(index: 1, height: 720, bitrate: 3_000_000),
      StreamLevel(index: 2, height: 1080, bitrate: 8_000_000),
      StreamLevel(index: 3, height: 2160, bitrate: 25_000_000),
    ];

    test('trouve la hauteur exacte', () {
      expect(matchLevelForHeight(ladder, 720)?.index, 1);
      expect(matchLevelForHeight(ladder, 2160)?.index, 3);
    });

    test('retourne le plus proche quand la hauteur exacte manque', () {
      // 1440p absent : le plus proche est 1080p (écart 360 vs 720 pour 2160p).
      expect(matchLevelForHeight(ladder, 1440)?.index, 2);
      // 480p absent : le plus proche est 360p.
      expect(matchLevelForHeight(ladder, 480)?.index, 0);
    });

    test('retourne null sur un manifeste vide', () {
      expect(matchLevelForHeight(const [], 1080), isNull);
    });

    test('hauteur 0 jamais sélectionnée si autre choix existe', () {
      const weird = [
        StreamLevel(index: 0, height: 0, bitrate: 500_000),
        StreamLevel(index: 1, height: 720, bitrate: 3_000_000),
      ];
      expect(matchLevelForHeight(weird, 1080)?.index, 1);
    });
  });

  group('compatibilité de sortie avec le backend YouTube', () {
    test('aggregateStreamingResults produit le même StreamingTestResult', () {
      final rows = [
        const StreamingQualityResult(
          label: '720p',
          reached: true,
          performanceRate: 98.5,
          initialLoadingSec: 0.8,
          bufferingSec: 0.2,
          rebufferCount: 1,
          dataUsedKiB: 2500,
        ),
        const StreamingQualityResult.unavailable('1080p'),
        const StreamingQualityResult.unavailable('2160p'),
      ];

      final r = aggregateStreamingResults(rows);
      expect(r.maxResolution, '720p');
      expect(r.startupMs, 800);
      expect(r.rebufferCount, 1);
      expect(r.score, greaterThan(0));
      expect(r.qualities.length, 3);
      // Encode/décodage historique inchangé.
      expect(
        StreamingTestResult.decodeQualities(r.encodeQualities()).length,
        3,
      );
      expect(StreamingTestResult.decodeError(r.encodeQualities()), isNull);
    });
  });

  group('Contrats de la page lecteur HLS (invariants de mesure)', () {
    // Ces invariants ont causé le bug terrain « seul le 720p est servi » :
    // sans reset d'état par palier, l'événement 'start' ne part qu'au
    // premier palier et les suivants tombent en timeout. Chaque test gèle
    // une propriété de la page, pas un détail d'implémentation.
    final page = StreamingTestServiceHls().playerHtml();

    test('resetTierState est appelé au début de chaque palier', () {
      expect(page.contains('function resetTierState()'), isTrue);
      expect('resetTierState();'.allMatches(page).length,
          greaterThanOrEqualTo(2),
          reason: 'un appel dans startHls et un dans startDash');
    });

    test("l'événement 'start' part à chaque première image, pas une seule fois",
        () {
      // Ancien bug : garde 'if (startupMs < 0)' remplie une seule fois par
      // page — les paliers 2 et 3 n'envoyaient jamais 'start'.
      expect(page.contains('if (!started) {'), isTrue);
      expect(page.contains('if (startupMs < 0) {'), isFalse);
    });

    test('chargement des segments piloté par palier (trafic attribuable)', () {
      // Sans autoStartLoad:false, hls.js précharge tout dès le manifeste : le
      // trafic d'un palier partait dans la fenêtre de mesure du précédent.
      expect(page.contains('autoStartLoad: false'), isTrue);
      expect(page.contains('engine.startLoad()'), isTrue);
      expect(page.contains('engine.stopLoad()'), isTrue);
    });

    test('verrou unique : le rattrapage LEVEL_SWITCHED est enregistré une fois',
        () {
      // On compte l'ENREGISTREMENT du listener (et non toute mention du nom
      // d'événement, présente aussi dans les commentaires de la page).
      expect('Hls.Events.LEVEL_SWITCHED'.allMatches(page).length, 1,
          reason: 'un listener par palier se battaient entre eux dès le 2e');
      expect(page.contains('wantedLevel'), isTrue);
    });

    test("le buffering d'amorçage reste hors interruptions (convention YouTube)",
        () {
      // Le stall avant la 1re image appartient au chargement initial
      // (startupMs), pas aux rebuffers.
      expect(page.contains('if (started && bufferStart === 0)'), isTrue);
    });
  });
}
