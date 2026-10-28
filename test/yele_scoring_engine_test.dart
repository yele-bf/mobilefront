import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:yele/services/yele_scoring_engine.dart';

void main() {
  final engine = YeleScoringEngine();

  group('Score Download', () {
    test('débit nul → 0 point (mesure valide)', () {
      final c = engine.scoreDownload(0);
      expect(c.status, MeasurementStatus.completed);
      expect(c.score, 0);
    });

    test('débit inférieur à 0,1 Mbps → 0 point', () {
      final c = engine.scoreDownload(0.05);
      expect(c.status, MeasurementStatus.completed);
      expect(c.score, 0);
    });

    test('débit égal à 0,1 Mbps → score logarithmique minimal', () {
      final c = engine.scoreDownload(0.1);
      expect(c.status, MeasurementStatus.completed);
      expect(c.score!, closeTo(17500 * _log10(1.1), 0.0001));
      expect(c.score!, greaterThan(0));
      expect(c.score!, lessThan(1000));
    });

    test('débit positif ordinaire (10 Mbps) → valeur attendue', () {
      final c = engine.scoreDownload(10);
      expect(c.status, MeasurementStatus.completed);
      expect(c.score!, closeTo(17500 * _log10(11), 0.0001)); // ≈ 18239
      expect(c.score!, greaterThan(17500)); // au-delà de l'allocation de réf
    });

    test('débit élevé (1000 Mbps) → non plafonné', () {
      final c = engine.scoreDownload(1000);
      expect(c.status, MeasurementStatus.completed);
      expect(c.score!, closeTo(17500 * _log10(1001), 0.0001)); // ≈ 52528
      expect(c.score!, greaterThan(50000)); // dépasse largement 17 500
    });

    test('valeur négative → invalide, pas de score', () {
      final c = engine.scoreDownload(-5);
      expect(c.status, MeasurementStatus.invalid);
      expect(c.score, isNull);
    });

    test('NaN → invalide', () {
      final c = engine.scoreDownload(double.nan);
      expect(c.status, MeasurementStatus.invalid);
      expect(c.score, isNull);
    });

    test('infini → invalide', () {
      final c = engine.scoreDownload(double.infinity);
      expect(c.status, MeasurementStatus.invalid);
    });

    test('null → indisponible (test non effectué ≠ zéro)', () {
      final c = engine.scoreDownload(null);
      expect(c.status, MeasurementStatus.unavailable);
      expect(c.score, isNull);
    });
  });

  group('Score Upload', () {
    test('débit nul → 0 point', () {
      final c = engine.scoreUpload(0);
      expect(c.status, MeasurementStatus.completed);
      expect(c.score, 0);
    });

    test('débit inférieur à 0,1 → 0 point', () {
      expect(engine.scoreUpload(0.09).score, 0);
    });

    test('débit égal à 0,1 → score minimal non nul', () {
      final c = engine.scoreUpload(0.1);
      expect(c.score!, closeTo(7500 * _log10(1.1), 0.0001));
    });

    test('débit positif ordinaire (5 Mbps)', () {
      final c = engine.scoreUpload(5);
      expect(c.score!, closeTo(7500 * _log10(6), 0.0001)); // ≈ 5843
    });

    test('débit élevé (500 Mbps) → non plafonné', () {
      final c = engine.scoreUpload(500);
      expect(c.score!, closeTo(7500 * _log10(501), 0.0001)); // ≈ 20223
      expect(c.score!, greaterThan(7500));
    });

    test('valeur négative → invalide', () {
      expect(engine.scoreUpload(-1).status, MeasurementStatus.invalid);
    });

    test('NaN et infini → invalides', () {
      expect(engine.scoreUpload(double.nan).status, MeasurementStatus.invalid);
      expect(
          engine.scoreUpload(double.negativeInfinity).status,
          MeasurementStatus.invalid);
    });
  });

  group('Score Ping et jitter', () {
    test('latence et jitter nuls → score maximal 15000', () {
      final c = engine.scorePingJitter(0, 0);
      expect(c.status, MeasurementStatus.completed);
      expect(c.score, 15000);
      expect(c.intermediate, 0);
    });

    test('latence effective intermédiaire → formule quadratique', () {
      // Ping 50, jitter 25 → L = 50 + 50 = 100 → 15000 × (1 - 100/250)²
      final c = engine.scorePingJitter(50, 25);
      expect(c.intermediate, 100);
      expect(c.score!, closeTo(15000 * 0.6 * 0.6, 0.0001)); // 5400
    });

    test('latence effective égale à 250 ms → 0 point', () {
      // Ping 200, jitter 25 → L = 250
      final c = engine.scorePingJitter(200, 25);
      expect(c.status, MeasurementStatus.completed);
      expect(c.score, 0);
    });

    test('latence effective supérieure à 250 ms → 0 point', () {
      final c = engine.scorePingJitter(400, 50);
      expect(c.status, MeasurementStatus.completed);
      expect(c.score, 0);
    });

    test('jitter non nul pesé double', () {
      // Ping 0, jitter 10 → L = 20
      final c = engine.scorePingJitter(0, 10);
      expect(c.intermediate, 20);
      expect(c.score!, closeTo(15000 * (1 - 20 / 250) * (1 - 20 / 250), 0.0001));
    });

    test('valeur négative → invalide', () {
      expect(engine.scorePingJitter(-10, 0).status, MeasurementStatus.invalid);
      expect(engine.scorePingJitter(10, -5).status, MeasurementStatus.invalid);
    });

    test('NaN → invalide', () {
      expect(
          engine.scorePingJitter(double.nan, 0).status,
          MeasurementStatus.invalid);
    });

    test('mesure absente → indisponible', () {
      expect(engine.scorePingJitter(null, 0).status,
          MeasurementStatus.unavailable);
    });
  });

  group('Score Navigation', () {
    test('cinq chargements rapides (1 s) → QoE 90, score maximal proche', () {
      final c = engine.scoreBrowsing([1, 1, 1, 1, 1]);
      expect(c.status, MeasurementStatus.completed);
      expect(c.score!, closeTo(17500 * 0.9, 0.0001)); // 15750
    });

    test('cinq chargements de 10 secondes → QoE 0, score 0', () {
      final c = engine.scoreBrowsing([10, 10, 10, 10, 10]);
      expect(c.status, MeasurementStatus.completed);
      expect(c.score, 0);
    });

    test('temps dépassant 10 secondes → QoE bornée à 0 (pas de négatif)', () {
      final c = engine.scoreBrowsing([15, 15, 15, 15, 15]);
      expect(c.status, MeasurementStatus.completed);
      expect(c.score, 0);
    });

    test('mix rapide/lent → moyenne des QoE', () {
      // QoE : 100, 90, 80, 70, 0 → moyenne 68
      final c = engine.scoreBrowsing([0, 1, 2, 3, 12]);
      expect(c.score!, closeTo(17500 * 0.68, 0.0001));
    });

    test('timeout (null) → statut partiel, absence ≠ zéro', () {
      final c = engine.scoreBrowsing([1, 1, 1, 1, null], expectedPages: 5);
      expect(c.status, MeasurementStatus.partial);
      expect(c.score!, closeTo(17500 * 0.9, 0.0001)); // moyenne sur 4 valides
      expect(c.message, isNotNull);
    });

    test('erreur technique (null) sur toutes les pages → failed', () {
      final c = engine.scoreBrowsing([null, null, null, null, null],
          expectedPages: 5);
      expect(c.status, MeasurementStatus.failed);
      expect(c.score, isNull);
    });

    test('moins de cinq résultats → partiel avec message', () {
      final c = engine.scoreBrowsing([1, 2], expectedPages: 5);
      expect(c.status, MeasurementStatus.partial);
      expect(c.score!, closeTo(17500 * 0.85, 0.0001));
    });

    test('mesure invalide (négative) → ignorée et signalée', () {
      final c = engine.scoreBrowsing([1, 1, 1, 1, -3], expectedPages: 5);
      expect(c.status, MeasurementStatus.partial);
      expect(c.message, contains('invalide'));
    });

    test('liste vide → indisponible', () {
      final c = engine.scoreBrowsing([]);
      expect(c.status, MeasurementStatus.unavailable);
      expect(c.score, isNull);
    });

    test('six pages (liste réelle du projet) → complètes', () {
      final c = engine.scoreBrowsing([1, 2, 3, 1, 2, 3], expectedPages: 6);
      expect(c.status, MeasurementStatus.completed);
    });
  });

  group('Score Streaming', () {
    test('session sans buffering ni interruption → score maximal', () {
      final c = engine.scoreStreaming(
          totalDurationSec: 30, bufferingSec: 0, stallCount: 0);
      expect(c.status, MeasurementStatus.completed);
      expect(c.score, 17500);
    });

    test('buffering partiel (10 %) → QoE 90', () {
      final c = engine.scoreStreaming(
          totalDurationSec: 30, bufferingSec: 3, stallCount: 0);
      expect(c.score!, closeTo(17500 * 0.9, 0.0001));
    });

    test('une interruption → pénalité de 15 points de QoE', () {
      final c = engine.scoreStreaming(
          totalDurationSec: 30, bufferingSec: 3, stallCount: 1);
      expect(c.score!, closeTo(17500 * 0.75, 0.0001));
    });

    test('plusieurs interruptions → QoE bornée à 0', () {
      final c = engine.scoreStreaming(
          totalDurationSec: 30, bufferingSec: 6, stallCount: 6);
      expect(c.status, MeasurementStatus.completed);
      expect(c.score, 0);
    });

    test('pénalités partielles : QoE 80 - 5×15 = 5 → score 875', () {
      final c = engine.scoreStreaming(
          totalDurationSec: 30, bufferingSec: 6, stallCount: 5);
      expect(c.status, MeasurementStatus.completed);
      expect(c.score!, closeTo(875, 0.0001));
    });

    test('durée totale nulle → failed', () {
      final c = engine.scoreStreaming(
          totalDurationSec: 0, bufferingSec: 0, stallCount: 0);
      expect(c.status, MeasurementStatus.failed);
      expect(c.score, isNull);
    });

    test('buffering supérieur à la durée totale → invalide', () {
      final c = engine.scoreStreaming(
          totalDurationSec: 10, bufferingSec: 12, stallCount: 0);
      expect(c.status, MeasurementStatus.invalid);
      expect(c.score, isNull);
    });

    test('nombre d\'interruptions négatif → invalide', () {
      final c = engine.scoreStreaming(
          totalDurationSec: 30, bufferingSec: 3, stallCount: -1);
      expect(c.status, MeasurementStatus.invalid);
    });

    test('mesures absentes → indisponible (jamais un score artificiel)', () {
      final c = engine.scoreStreaming();
      expect(c.status, MeasurementStatus.unavailable);
      expect(c.score, isNull);
    });

    test('NaN → invalide', () {
      final c = engine.scoreStreaming(
          totalDurationSec: double.nan, bufferingSec: 0, stallCount: 0);
      expect(c.status, MeasurementStatus.invalid);
    });
  });

  group('Résultat global et compatibilité', () {
    test('calcul global complet → somme des cinq composantes', () {
      final r = engine.scoreAll(
        downloadMbps: 10,
        uploadMbps: 5,
        pingMs: 20,
        jitterMs: 5,
        browsingLoadTimesSec: [1, 1, 1, 1, 1],
        streamingTotalSec: 30,
        streamingBufferingSec: 0,
        streamingStallCount: 0,
      );
      expect(r.isComplete, isTrue);
      expect(r.globalScore!, closeTo(68926.5, 1)); // somme vérifiée à la main
      // Égal à la somme des composantes.
      final sum = r.download.score! +
          r.upload.score! +
          r.pingJitter.score! +
          r.browsing.score! +
          r.streaming.score!;
      expect(r.globalScore!, closeTo(sum, 0.0001));
    });

    test('score global non plafonné (débits très élevés)', () {
      final r = engine.scoreAll(
        downloadMbps: 1000,
        uploadMbps: 500,
        pingMs: 1,
        jitterMs: 0,
        browsingLoadTimesSec: [0.2, 0.2, 0.2, 0.2, 0.2],
        streamingTotalSec: 30,
        streamingBufferingSec: 0,
        streamingStallCount: 0,
      );
      expect(r.globalScore!, greaterThan(100000));
      // Aucune composante plafonnée à son allocation.
      expect(r.download.score!, greaterThan(YeleScoringEngine.maxDownload));
      expect(r.upload.score!, greaterThan(YeleScoringEngine.maxUpload));
    });

    test('composante indisponible → global null, statut unavailable', () {
      final r = engine.scoreAll(
        downloadMbps: 10,
        uploadMbps: 5,
        pingMs: 20,
        jitterMs: 5,
        browsingLoadTimesSec: [], // pas de test de navigation
      );
      expect(r.isComplete, isFalse);
      expect(r.globalScore, isNull);
      expect(r.globalStatus, MeasurementStatus.unavailable);
      expect(r.classification, '');
    });

    test('test échoué → statut failed, global null', () {
      final r = engine.scoreAll(
        downloadMbps: 10,
        uploadMbps: 5,
        pingMs: 20,
        jitterMs: 5,
        browsingLoadTimesSec: [1, 1, 1, 1, 1],
        streamingTotalSec: 0, // session nulle = échec
        streamingBufferingSec: 0,
        streamingStallCount: 0,
      );
      expect(r.globalStatus, MeasurementStatus.failed);
      expect(r.globalScore, isNull);
    });

    test('résultat partiel (timeout navigation) → global null', () {
      final r = engine.scoreAll(
        downloadMbps: 10,
        uploadMbps: 5,
        pingMs: 20,
        jitterMs: 5,
        browsingLoadTimesSec: [1, 1, 1, 1, null],
        streamingTotalSec: 30,
        streamingBufferingSec: 0,
        streamingStallCount: 0,
      );
      expect(r.globalStatus, MeasurementStatus.partial);
      expect(r.globalScore, isNull);
    });

    test('ancien enregistrement sans aucun champ de scoring → indisponible',
        () {
      // Simule un résultat Hive d'avant l'intégration : champs null.
      final r = engine.scoreAll();
      expect(r.globalStatus, MeasurementStatus.unavailable);
      expect(r.globalScore, isNull);
      expect(r.download.status, MeasurementStatus.unavailable);
      expect(r.streaming.status, MeasurementStatus.unavailable);
    });

    test('version du modèle exposée', () {
      expect(YeleScoringEngine.version, 'yele-open-1.0.0');
      final r = engine.scoreAll(downloadMbps: 10);
      expect(r.version, 'yele-open-1.0.0');
    });

    test('classification centralisée', () {
      expect(YeleScoringEngine.classify(0).label, 'Très faible');
      expect(YeleScoringEngine.classify(30000).label, 'Très faible');
      expect(YeleScoringEngine.classify(30001).label, 'Moyen');
      expect(YeleScoringEngine.classify(70000).label, 'Moyen');
      expect(YeleScoringEngine.classify(110000).label, 'Bon');
      expect(YeleScoringEngine.classify(160000).label, 'Très bon');
      expect(YeleScoringEngine.classify(200000).label, 'Excellent / élite');
    });

    test('arrondi uniquement à la présentation', () {
      final c = engine.scoreDownload(3);
      expect(c.score, isNot(c.score!.round().toDouble()));
      expect(c.rounded, c.score!.round());
    });
  });
}

double _log10(num x) => math.log(x) / math.ln10;
