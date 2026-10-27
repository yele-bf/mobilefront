import 'package:flutter_test/flutter_test.dart';
import 'package:yele/constants/arcep_seuils.dart';
import 'package:yele/services/arcep_scoring.dart';

/// Valeurs situées de part et d'autre de chaque seuil du streaming :
/// démarrage 5 s, rebuffering 10 %, résolution 480p, interruptions 0 — IMP-06.
void main() {
  tearDown(() => ArcepScoring.seuils = ArcepSeuils.valides);

  double score({
    double fluidite = 100,
    double startupMs = 0,
    double rebufferRatio = 0,
    int interruptions = 0,
    int hauteurServie = 1080,
  }) =>
      ArcepScoring.scoreStreaming(
        fluidite: fluidite,
        startupMs: startupMs,
        rebufferRatio: rebufferRatio,
        interruptions: interruptions,
        hauteurServie: hauteurServie,
      );

  group('Démarrage vidéo (seuil 5 s)', () {
    test('4,999 s est dans le seuil, 5,000 s reste à la limite, 5,001 s non', () {
      expect(ArcepScoring.preloadDansSeuil(4999), isTrue);
      expect(ArcepScoring.preloadDansSeuil(5000), isFalse);
      expect(ArcepScoring.preloadDansSeuil(5001), isFalse);
    });

    test('aucune pénalité jusqu\'au seuil inclus', () {
      expect(score(startupMs: 5000), closeTo(100, 0.01));
    });

    test('juste au-delà du seuil, la note baisse', () {
      expect(score(startupMs: 5001), lessThan(100));
      expect(score(startupMs: 5001), greaterThan(99));
    });

    test('au double du seuil (10 s), la moitié de la note est perdue', () {
      expect(score(startupMs: 10000), closeTo(50, 0.01));
    });
  });

  group('Rebuffering (seuil 10 %)', () {
    test('9,9 % est dans le seuil, 10,1 % ne l\'est plus', () {
      expect(score(rebufferRatio: 0.099), closeTo(100, 0.01));
      expect(score(rebufferRatio: 0.101), lessThan(100));
    });

    test('au double du seuil (20 %), la moitié de la note est perdue', () {
      expect(score(rebufferRatio: 0.20), closeTo(50, 0.1));
    });
  });

  group('Interruptions (définition Yélé : aucune)', () {
    test('0 interruption ne coûte rien, 1 coûte 15 %', () {
      expect(score(interruptions: 0), closeTo(100, 0.01));
      expect(score(interruptions: 1), closeTo(85, 0.01));
    });
  });

  group('Résolution servie (minimum 480p)', () {
    test('479p perd la moitié de la note, 480p ne perd rien', () {
      expect(score(hauteurServie: 479), closeTo(50, 0.01));
      expect(score(hauteurServie: 480), closeTo(100, 0.01));
    });

    test('sessionBonneQualite suit les mêmes bornes', () {
      expect(
        ArcepScoring.sessionBonneQualite(
            rebufferRatio: 0.10, hauteurServie: 480, interruptions: 0),
        isTrue,
      );
      expect(
        ArcepScoring.sessionBonneQualite(
            rebufferRatio: 0.1001, hauteurServie: 480, interruptions: 0),
        isFalse,
      );
      expect(
        ArcepScoring.sessionBonneQualite(
            rebufferRatio: 0.05, hauteurServie: 479, interruptions: 0),
        isFalse,
      );
      expect(
        ArcepScoring.sessionBonneQualite(
            rebufferRatio: 0.05, hauteurServie: 720, interruptions: 1),
        isFalse,
      );
    });
  });

  group('Combinaisons', () {
    test('tous les seuils respectés : la note reste la fluidité mesurée', () {
      expect(
        score(
          fluidite: 94.3,
          startupMs: 5000,
          rebufferRatio: 0.10,
          interruptions: 0,
          hauteurServie: 480,
        ),
        closeTo(94.3, 0.01),
      );
    });

    test('aucun palier servi : 0, quels que soient les autres indicateurs', () {
      expect(score(fluidite: 0, startupMs: 1000), 0);
    });

    test('les pénalités se cumulent sans sortir de 0-100', () {
      final s = score(
        fluidite: 100,
        startupMs: 10000,
        rebufferRatio: 0.20,
        interruptions: 1,
        hauteurServie: 479,
      );
      // 100 × 0,5 × 0,5 × 0,85 × 0,5 = 10,625
      expect(s, closeTo(10.6, 0.1));
      expect(s, inInclusiveRange(0, 100));
    });
  });

  group('Référentiel surchargé par l\'API', () {
    test('le seuil de démarrage reçu remplace celui par défaut', () {
      ArcepScoring.seuils = ArcepSeuils.fromApiJson({
        'streaming': {'preloadSeuilS': 2},
      });
      // 3 s : au-delà du seuil API (2 s) mais dans le seuil par défaut (5 s).
      expect(ArcepScoring.preloadDansSeuil(3000), isFalse);
      expect(score(startupMs: 3000), lessThan(100));
    });
  });
}
