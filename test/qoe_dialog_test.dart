import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yele/models/qoe_answers.dart';
import 'package:yele/widgets/qoe_dialog.dart';

/// Support du test : capture les réponses transmises par « Enregistrer ».
class _Holder {
  QoeAnswers? value;
}

Future<_Holder> _ouvrir(
  WidgetTester tester, {
  required String testType,
  bool isMobile = true,
  QoeAnswers? initial,
}) async {
  final holder = _Holder();
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (ctx) => Center(
          child: ElevatedButton(
            onPressed: () => showDialog(
              context: ctx,
              barrierDismissible: false,
              builder: (_) => QoeDialog(
                testType: testType,
                isMobile: isMobile,
                initial: initial,
                onCompleted: (answers) => holder.value = answers,
              ),
            ),
            child: const Text('ouvrir'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('ouvrir'));
  await tester.pumpAndSettle();
  return holder;
}

Future<void> _tap(WidgetTester tester, String label) async {
  final finder = find.text(label);
  await tester.ensureVisible(finder.first);
  await tester.pumpAndSettle();
  await tester.tap(finder.first);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('speedtest : vitesse, satisfaction, liste mobile, commentaire',
      (tester) async {
    await _ouvrir(tester, testType: 'speedtest', isMobile: true);

    expect(
        find.text(
            'Comment évaluez-vous la vitesse de votre connexion Internet ?'),
        findsOneWidget);
    expect(
        find.text(
            'Globalement, comment évaluez-vous la qualité du réseau de votre opérateur ?'),
        findsOneWidget);
    expect(
        find.text(
            'Quelle est l\'amélioration la plus urgente ? (plusieurs réponses)'),
        findsOneWidget);
    expect(find.text('Un commentaire ?'), findsOneWidget);
    // Liste mobile, pas fixe.
    expect(
        find.text('Éviter les coupures du réseau pendant la pluie ou le vent'),
        findsOneWidget);
    expect(find.text('Étendre la fibre dans plus de quartiers et de villes'),
        findsNothing);
    // Questions des autres usages absentes.
    expect(find.text('Avez-vous des difficultés à charger des pages web ?'),
        findsNothing);
    expect(find.text('Comment jugez-vous la qualité des vidéos en ligne ?'),
        findsNothing);
  });

  testWidgets('navigation : pages web, liste fixe en Wi-Fi', (tester) async {
    await _ouvrir(tester, testType: 'navigation', isMobile: false);

    expect(find.text('Avez-vous des difficultés à charger des pages web ?'),
        findsOneWidget);
    expect(find.text('Fréquemment'), findsOneWidget);
    expect(
        find.text(
            'Globalement, comment évaluez-vous la qualité du réseau de votre opérateur ?'),
        findsOneWidget);
    expect(find.text('Étendre la fibre dans plus de quartiers et de villes'),
        findsOneWidget);
    expect(
        find.text('Éviter les coupures du réseau pendant la pluie ou le vent'),
        findsNothing);
    expect(
        find.text(
            'Comment évaluez-vous la vitesse de votre connexion Internet ?'),
        findsNothing);
  });

  testWidgets('streaming : qualité vidéo + coupures, pas de pages web',
      (tester) async {
    await _ouvrir(tester, testType: 'streaming', isMobile: true);

    expect(find.text('Comment jugez-vous la qualité des vidéos en ligne ?'),
        findsOneWidget);
    expect(
        find.text(
            'Rencontrez-vous des coupures ou des blocages pendant les vidéos ?'),
        findsOneWidget);
    expect(find.text('Avez-vous des difficultés à charger des pages web ?'),
        findsNothing);
  });

  testWidgets('test complet : toutes les questions du formulaire',
      (tester) async {
    await _ouvrir(tester, testType: 'complet', isMobile: true);

    expect(
        find.text(
            'Comment évaluez-vous la vitesse de votre connexion Internet ?'),
        findsOneWidget);
    expect(find.text('Avez-vous des difficultés à charger des pages web ?'),
        findsOneWidget);
    expect(find.text('Comment jugez-vous la qualité des vidéos en ligne ?'),
        findsOneWidget);
    expect(
        find.text(
            'Rencontrez-vous des coupures ou des blocages pendant les vidéos ?'),
        findsOneWidget);
    expect(
        find.text(
            'Globalement, comment évaluez-vous la qualité du réseau de votre opérateur ?'),
        findsOneWidget);
    expect(find.text('Un commentaire ?'), findsOneWidget);
  });

  testWidgets('« Aucune réponse en particulier » est exclusive', (tester) async {
    final holder = await _ouvrir(tester, testType: 'speedtest');

    await _tap(tester, 'Aucune réponse en particulier');
    await _tap(tester, 'Baisser le prix des forfaits Internet');
    await _tap(tester, 'Enregistrer');

    expect(holder.value, isNotNull);
    expect(holder.value!.ameliorations, {'baisser_prix'});
  });

  testWidgets('enregistrement : profil, étoiles et satisfaction repris',
      (tester) async {
    final holder = await _ouvrir(tester, testType: 'complet');

    await _tap(tester, '20 à 40 ans');
    await _tap(tester, 'Féminin');
    await _tap(tester, 'Plus de 5 ans');
    // 4 étoiles : les 5 boutons sont dans l'ordre.
    final etoiles = find.byIcon(Icons.star_border_rounded);
    await tester.ensureVisible(etoiles.first);
    await tester.pumpAndSettle();
    await tester.tap(etoiles.at(3));
    await tester.pumpAndSettle();
    // « Bonne » existe aussi pour la qualité vidéo : la satisfaction globale
    // est la dernière occurrence.
    final bonne = find.text('Bonne').last;
    await tester.ensureVisible(bonne);
    await tester.pumpAndSettle();
    await tester.tap(bonne);
    await tester.pumpAndSettle();
    await _tap(tester, 'Enregistrer');

    final a = holder.value!;
    expect(a.testType, 'complet');
    expect(a.reseau, 'mobile');
    expect(a.trancheAge, '20_40');
    expect(a.genre, 'feminin');
    expect(a.dureeUtilisation, 'plus_5_ans');
    expect(a.vitesseInternet, 4);
    expect(a.evaluationGlobaleReseau, 'Bonne');
    expect(a.rating, 4);
    expect(a.satisfaction, 'satisfied');
    // Les clés suivent le XLSForm.
    final json = a.toJson();
    expect(json['tranche_age'], '20_40');
    expect(json['vitesse_internet'], 4);
    expect(json['evaluation_globale_reseau'], 'Bonne');
  });

  testWidgets('profil pré-rempli depuis le questionnaire précédent',
      (tester) async {
    final initial = QoeAnswers(
      testType: 'speedtest',
      reseau: 'mobile',
      trancheAge: 'plus_40',
      genre: 'masculin',
      dureeUtilisation: 'moins_6_mois',
    );
    final holder =
        await _ouvrir(tester, testType: 'speedtest', initial: initial);

    expect(find.textContaining('pré-rempli'), findsOneWidget);
    await _tap(tester, 'Enregistrer');

    expect(holder.value!.trancheAge, 'plus_40');
    expect(holder.value!.genre, 'masculin');
    expect(holder.value!.dureeUtilisation, 'moins_6_mois');
  });

  testWidgets('« Passer » ne transmet aucune réponse', (tester) async {
    final holder = await _ouvrir(tester, testType: 'streaming');

    await _tap(tester, 'Passer');

    expect(holder.value, isNull);
    expect(find.byType(QoeDialog), findsNothing);
  });
}
