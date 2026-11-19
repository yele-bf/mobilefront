import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yele/models/qoe_answers.dart';

void main() {
  test('les clés JSON reprennent les noms du XLSForm', () {
    final a = QoeAnswers(
      testType: 'complet',
      reseau: 'mobile',
      trancheAge: '20_40',
      genre: 'feminin',
      dureeUtilisation: '1_5_ans',
      vitesseInternet: 4,
      difficultePagesWeb: 'rarement',
      qualiteStreaming: 'Bonne',
      buffering: 'jamais',
      evaluationGlobaleReseau: 'Bonne',
      ameliorationsAutre: 'Couverture',
      commentaire: '  Test  ',
    )
      ..ameliorations.addAll({'baisser_prix', 'autre'});

    expect(a.toJson(), {
      'test_type': 'complet',
      'reseau': 'mobile',
      'tranche_age': '20_40',
      'genre': 'feminin',
      'duree_utilisation': '1_5_ans',
      'vitesse_internet': 4,
      'difficulte_pages_web': 'rarement',
      'qualite_streaming': 'Bonne',
      'buffering': 'jamais',
      'evaluation_globale_reseau': 'Bonne',
      'ameliorations_mobile': ['baisser_prix', 'autre'],
      'amelioration_autre': 'Couverture',
      'commentaire': 'Test',
    });
  });

  test('liste fixe : la clé est ameliorations_fixe', () {
    final a = QoeAnswers(testType: 'speedtest', reseau: 'fixe')
      ..ameliorations.add('etendre_fibre');
    expect(a.toJson().containsKey('ameliorations_fixe'), isTrue);
    expect(a.toJson().containsKey('ameliorations_mobile'), isFalse);
  });

  test('note et satisfaction : étoiles prioritaires, sinon conversion', () {
    final a = QoeAnswers(
        testType: 'speedtest',
        reseau: 'mobile',
        evaluationGlobaleReseau: 'Mauvaise');
    expect(a.rating, 2);
    expect(a.satisfaction, 'unsatisfied');
    a.vitesseInternet = 5;
    expect(a.rating, 5);
  });

  test('décodage tolérant du JSON Hive', () {
    final raw = jsonEncode({
      'test_type': 'streaming',
      'reseau': 'fixe',
      'qualite_streaming': 'Moyenne',
      'ameliorations_fixe': ['reparer_pannes_rapidement'],
    });
    final a = QoeAnswers.tryDecode(raw)!;
    expect(a.testType, 'streaming');
    expect(a.reseau, 'fixe');
    expect(a.qualiteStreaming, 'Moyenne');
    expect(a.ameliorations, {'reparer_pannes_rapidement'});
    expect(QoeAnswers.tryDecode(null), isNull);
    expect(QoeAnswers.tryDecode('pas du json'), isNull);
  });

  test('un questionnaire vide est détecté', () {
    final a = QoeAnswers(testType: 'speedtest', reseau: 'mobile');
    expect(a.isEmpty, isTrue);
    a.commentaire = '   ';
    expect(a.isEmpty, isTrue);
    a.commentaire = 'ok';
    expect(a.isEmpty, isFalse);
  });
}
