import 'package:flutter_test/flutter_test.dart';
import 'package:yele/constants/arcep_seuils.dart';
import 'package:yele/services/arcep_scoring.dart';

/// Valeurs situées de part et d'autre du seuil ARCEP de chargement (30 s) et
/// du seuil de connexion (20 s) : IMP-06.
void main() {
  tearDown(() => ArcepScoring.seuils = ArcepSeuils.valides);

  group('Seuil ARCEP de chargement (30 s)', () {
    test('29,999 s est dans le seuil, 30,000 s ne l\'est plus', () {
      expect(ArcepScoring.pageDansSeuil(29999), isTrue);
      expect(ArcepScoring.pageDansSeuil(30000), isFalse);
      expect(ArcepScoring.pageDansSeuil(30001), isFalse);
    });

    test('une page juste sous le seuil compte comme réussie', () {
      final score = ArcepScoring.scoreNavigation(
        pagesTestees: 1,
        pagesDansSeuil: 1,
        pageLoadMoyenMs: 29999,
      );
      // 100 × 1 − 20 × (29 999 / 30 000) ≈ 80,0
      expect(score, closeTo(80.0, 0.1));
    });

    test('une page juste au-dessus ne rapporte aucun point', () {
      final score = ArcepScoring.scoreNavigation(
        pagesTestees: 1,
        pagesDansSeuil: 0,
        pageLoadMoyenMs: 30001,
      );
      expect(score, 0);
    });

    test('une page lente fait basculer la moitié du score', () {
      // 2 pages : une à 29,9 s (réussie), une à 30,1 s (échec).
      final score = ArcepScoring.scoreNavigation(
        pagesTestees: 2,
        pagesDansSeuil: 1,
        pageLoadMoyenMs: 30000,
      );
      expect(score, closeTo(30.0, 0.1)); // 50 − 20
    });

    test('des pages rapides approchent 100 sans l\'atteindre', () {
      final score = ArcepScoring.scoreNavigation(
        pagesTestees: 10,
        pagesDansSeuil: 10,
        pageLoadMoyenMs: 3000,
      );
      expect(score, closeTo(98.0, 0.1)); // 100 − 20 × 0,1
    });

    test('aucune page testée donne 0, pas une division par zéro', () {
      expect(
        ArcepScoring.scoreNavigation(
          pagesTestees: 0,
          pagesDansSeuil: 0,
          pageLoadMoyenMs: 0,
        ),
        0,
      );
    });
  });

  group('Seuil ARCEP de connexion (20 s)', () {
    test('19,999 s est dans le seuil, 20,000 s ne l\'est plus', () {
      expect(ArcepScoring.connexionDansSeuil(19999), isTrue);
      expect(ArcepScoring.connexionDansSeuil(20000), isFalse);
      expect(ArcepScoring.connexionDansSeuil(20001), isFalse);
    });
  });

  group('Référentiel surchargé par l\'API', () {
    test('le score suit le seuil reçu, pas la valeur par défaut', () {
      ArcepScoring.seuils = ArcepSeuils.fromApiJson({
        'navigation': {'pageLoadSeuilS': 10},
      });

      // 12 s : échec avec le seuil de l'API (10 s), réussite avec le défaut (30 s).
      expect(ArcepScoring.pageDansSeuil(12000), isFalse);
      final score = ArcepScoring.scoreNavigation(
        pagesTestees: 1,
        pagesDansSeuil: 0,
        pageLoadMoyenMs: 12000,
      );
      expect(score, 0);
    });
  });
}
