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

    test('le lecteur est audible (démutage armé, déclenché à canplay)', () {
      // Bug terrain 17/09 : la balise vidéo naissait 'muted' et personne ne
      // la démutait — les vidéos se lisaient sans aucun son. La WebView
      // autorise pourtant la lecture avec son sans geste utilisateur.
      // Moteur neuf par palier depuis le correctif « démarrage à froid » : le
      // play() immédiat serait rejeté (aucune donnée) et déclencherait le
      // repli muet — le démutage est donc ARMÉ au démarrage du palier et
      // déclenché à canplay (premier fragment décodable).
      expect(page.contains('<video id="video" muted'), isFalse,
          reason: 'la balise ne doit pas naître muette');
      expect(page.contains('function unmute()'), isTrue,
          reason: 'la fonction de démutage doit exister');
      expect('unmuteArmed = true;'.allMatches(page).length,
          greaterThanOrEqualTo(2),
          reason: 'armé dans startHls ET startDash (chaque palier)');
      expect(page.contains("addEventListener('canplay', onCanPlay)"), isTrue,
          reason: 'le démutage part à canplay, pas avant que des données existent');
      expect(page.contains('if (unmuteArmed)'), isTrue,
          reason: 'onCanPlay ne démute que si le palier a armé le démutage');
      // Filet de sécurité : si le système refuse le son, on retombe en muet
      // au lieu de bloquer la mesure.
      expect(page.contains('video.muted = false;'), isTrue);
    });

    test('le moteur est recréé à froid à CHAQUE palier (convention YouTube)',
        () {
      // Le backend YouTube détruit son lecteur par palier (buildLevel) pour
      // éviter que l'estimation de bande passante ne contamine les paliers
      // suivants. Le moteur HLS unique faisait démarrer 1080p/2160p avec les
      // buffers et l'estimation du palier précédent : startupMs mesurait une
      // reprise, pas un démarrage à froid — périmètre A/B inégal.
      expect(page.contains('function destroyEngine()'), isTrue);
      expect('destroyEngine();'.allMatches(page).length, greaterThanOrEqualTo(2),
          reason: 'appelé dans startHls ET startDash (chaque palier)');
      expect(page.contains('engine.destroy()'), isTrue,
          reason: 'hls.js : destroy relâche buffers MSE et listeners');
      expect(page.contains('engine.reset()'), isTrue,
          reason: 'dash.js : reset, équivalent documenté du destroy');
      // Deux instances hls.js au total : le moteur de découverte (échelle
      // remontée à Dart avant le 1er palier) + le moteur neuf de chaque
      // palier. Un seul = moteur réutilisé (ancien comportement).
      expect('new Hls({'.allMatches(page).length, 2);
      expect('startLevel: -1'.allMatches(page).length, 2,
          reason: 'moteur de découverte et moteur de palier démarrent sans '
              'niveau imposé : c\'est le verrou qui décide');
    });

    test('le verrou est appliqué AVANT startLoad sur le moteur neuf', () {
      // Sans verrou avant startLoad, le premier fragment du moteur neuf
      // partirait au niveau par défaut : le trafic du palier serait mêlé et
      // le palier servi ne serait plus garanti (régression du verrouillage).
      final lockAt = page.indexOf('engine.currentLevel = wantedLevel;');
      final loadAt = page.indexOf('engine.startLoad();');
      expect(lockAt, greaterThan(0));
      expect(loadAt, greaterThan(lockAt),
          reason: 'MANIFEST_PARSED applique le verrou avant startLoad');
      expect('autoStartLoad: false'.allMatches(page).length, 2,
          reason: 'découverte ET palier : aucun octet sans startLoad explicite '
              '(attribution du trafic par palier)');
      expect(page.contains('report();'), isTrue,
          reason: 'le moteur neuf remonte son échelle : Dart reste synchronisé');
    });

    test("l'état audio est remonté une fois par palier (diagnostic terrain)", () {
      // Sans ce signal, un muet imposé par la WebView malgré le unmute est
      // indiscernable en terrain d'un défaut de piste audio.
      expect(page.contains('function reportAudio()'), isTrue);
      expect(page.contains('audioReported = false;'), isTrue,
          reason: 'compteur remis par resetTierState : 1 signalement par palier');
      // Signalé à la 1re image (chemin nominal) ET au repli muet du unmute
      // (play() rejeté) : les deux trajectoires doivent aboutir au log.
      expect('reportAudio();'.allMatches(page).length, greaterThanOrEqualTo(2));
    });
  });
}
