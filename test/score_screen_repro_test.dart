// Tests de régression — écran de résultat, les 4 variantes (17/11).
//
// Contexte : anomalie du 17/11 — le Row des tuiles débit utilisait
// `CrossAxisAlignment.stretch` dans une SingleChildScrollView : contraintes de
// hauteur infinies, frame corrompue en release (contenu sous les tuiles jamais
// peint, tuiles sans fond). Aucun test ne construisait ScoreScreen avant :
// ce fichier garantit désormais que chaque variante (speedtest seul,
// streaming seul, navigation seule, test complet) construit toutes ses
// sections, avec les décimales françaises.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:yele/models/speed_test_result.dart';
import 'package:yele/screens/score_screen.dart';

SpeedTestResult _speedSeul() => SpeedTestResult(
      downloadSpeed: 6.08,
      uploadSpeed: 7.60,
      ping: 334,
      jitter: 127,
      server: 'Ouagadougou — Yélé',
      networkType: 'MOBILE',
      technology: '4G',
      deviceModel: 'Nothing Phone (3a)',
      osVersion: 'Android 15',
      dataUsedKiB: 22221,
      packetLoss: 0.0,
      scoringVersion: 'yele-open-1.0.0',
      scoreDownload: 14873,
      scoreUpload: 7008,
      scorePingJitter: 0,
    );

SpeedTestResult _streamingSeul() => SpeedTestResult(
      downloadSpeed: 0,
      uploadSpeed: 0,
      ping: 0,
      jitter: 0,
      server: 'Ouagadougou — Yélé',
      networkType: 'MOBILE',
      deviceModel: 'Nothing Phone (3a)',
      osVersion: 'Android 15',
      dataUsedKiB: 45123,
      streamingScore: 92,
      streamingMaxResolution: '1080p',
      streamingStartupMs: 1400,
      streamingRebufferCount: 0,
      streamingQualitiesJson: jsonEncode([
        {
          'label': '480p',
          'reached': true,
          'performanceRate': 95,
          'initialLoadingSec': 1.1,
          'rebufferCount': 0,
        },
        {
          'label': '720p',
          'reached': true,
          'performanceRate': 90,
          'initialLoadingSec': 1.4,
          'rebufferCount': 0,
        },
        {
          'label': '1080p',
          'reached': true,
          'performanceRate': 88,
          'initialLoadingSec': 1.7,
          'rebufferCount': 0,
        },
      ]),
      scoringVersion: 'yele-open-1.0.0',
      scoreStreaming: 14950,
    );

SpeedTestResult _navigationSeule() => SpeedTestResult(
      downloadSpeed: 0,
      uploadSpeed: 0,
      ping: 0,
      jitter: 0,
      server: 'Ouagadougou — Yélé',
      networkType: 'MOBILE',
      deviceModel: 'Nothing Phone (3a)',
      osVersion: 'Android 15',
      dataUsedKiB: 3010,
      browsingScore: 84,
      browsingAvgLoadMs: 2400,
      browsingSuccessRate: 0.83,
      browsingPagesTested: 6,
      // Détail par site (validation du 18/11) : 5 réussies, 1 échec.
      browsingPagesJson: jsonEncode([
        {'label': 'Google', 'loadMs': 800, 'success': true},
        {'label': 'Wikipédia', 'loadMs': 1100, 'success': true},
        {'label': 'Facebook', 'loadMs': 2400, 'success': true},
        {'label': 'Lefaso.net', 'loadMs': 3200, 'success': true},
        {'label': 'YouTube', 'loadMs': 1500, 'success': true},
        {'label': 'Bing', 'loadMs': 30000, 'success': false},
      ]),
      scoringVersion: 'yele-open-1.0.0',
      scoreBrowsing: 13500,
    );

SpeedTestResult _complet() => SpeedTestResult(
      downloadSpeed: 11.70,
      uploadSpeed: 6.68,
      ping: 294,
      jitter: 28,
      server: 'Ouagadougou — Yélé',
      networkType: 'MOBILE',
      technology: '4G',
      deviceModel: 'Nothing Phone (3a)',
      osVersion: 'Android 15',
      dataUsedKiB: 84287,
      downloadMin: 5.82,
      downloadMax: 17.61,
      uploadMin: 2.23,
      uploadMax: 45.62,
      pingMin: 267,
      pingMax: 467,
      streamingScore: 90,
      streamingMaxResolution: '1080p',
      streamingStartupMs: 1388,
      streamingRebufferCount: 0,
      streamingQualitiesJson: jsonEncode([
        {
          'label': '1080p',
          'reached': true,
          'performanceRate': 85,
          'initialLoadingSec': 1.7,
          'rebufferCount': 0,
        },
      ]),
      browsingScore: 88,
      browsingAvgLoadMs: 2100,
      browsingSuccessRate: 1.0,
      browsingPagesTested: 6,
      browsingPagesJson: jsonEncode([
        {'label': 'Google', 'loadMs': 900, 'success': true},
        {'label': 'Wikipédia', 'loadMs': 1200, 'success': true},
        {'label': 'Facebook', 'loadMs': 2100, 'success': true},
        {'label': 'Lefaso.net', 'loadMs': 3400, 'success': true},
        {'label': 'YouTube', 'loadMs': 1600, 'success': true},
        {'label': 'Bing', 'loadMs': 2200, 'success': true},
      ]),
      packetLoss: 5,
      scoringVersion: 'yele-open-1.0.0',
      scoreDownload: 14000,
      scoreUpload: 8000,
      scorePingJitter: 9000,
      scoreStreaming: 17000,
      scoreBrowsing: 16000,
      scoreGlobal: 64000,
    );

Future<void> _pomper(WidgetTester tester, SpeedTestResult r) async {
  await tester.pumpWidget(MaterialApp(home: ScoreScreen(result: r)));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  // L'écran interroge l'identité d'appareil (Hive) dès son ouverture : on
  // initialise Hive sur un dossier temporaire pour éviter l'HiveError du
  // harnais de test.
  setUpAll(() async {
    final tmp = await Directory.systemTemp.createTemp('yele_score_repro');
    Hive.init(tmp.path);
  });

  testWidgets('speedtest seul : toutes les sections se construisent',
      (tester) async {
    await _pomper(tester, _speedSeul());

    expect(find.textContaining('Données consommées'), findsOneWidget);
    // Décimales françaises : virgule, jamais le point anglais.
    expect(find.text('6,08'), findsOneWidget);
    expect(find.text('7,60'), findsOneWidget);
    expect(find.textContaining('Mo'), findsOneWidget);
    expect(find.textContaining('21.7'), findsNothing,
        reason: 'point décimal anglais interdit');
    // Héros : sous-total des composantes fournies (14 873 + 7 008 + 0).
    expect(find.text('21 881'), findsOneWidget);
    expect(find.textContaining('pts YELE'), findsOneWidget);
    expect(find.text('14 873 / 17 500'), findsOneWidget);
    expect(find.text('0 / 15 000'), findsOneWidget);
    expect(find.textContaining('DOWNLOAD'), findsOneWidget);
    expect(find.textContaining('UPLOAD'), findsOneWidget);
    expect(find.textContaining('LATENCE'), findsOneWidget);
    // Sections suivantes : comparaison, infos, actions.
    expect(find.textContaining('COMPARAISON'), findsWidgets);
    expect(find.textContaining('Serveur de test'), findsOneWidget);
    expect(find.text('Évaluer la qualité de ma connexion'), findsOneWidget);
    expect(find.text('Exporter la mesure'), findsOneWidget);
    expect(find.text('Recommencer'), findsOneWidget);
    expect(find.text('Historique'), findsOneWidget);
  });

  testWidgets('streaming seul : carte streaming + rappel test complet',
      (tester) async {
    await _pomper(tester, _streamingSeul());

    expect(find.textContaining('Streaming vidéo'), findsWidgets);
    expect(find.textContaining('480p'), findsOneWidget);
    expect(find.textContaining('720p'), findsOneWidget);
    expect(find.textContaining('1080p'), findsNWidgets(2),
        reason: 'tableau + résolution max de la synthèse');
    expect(find.textContaining('pts YELE'), findsOneWidget);
    expect(find.textContaining('Score partiel'), findsOneWidget);
    expect(find.textContaining('COMPARAISON'), findsWidgets);
    expect(find.textContaining('test complet'), findsOneWidget,
        reason: 'rappel discret en usage seul');
    expect(find.textContaining('Serveur de test'), findsOneWidget);
    expect(find.text('Recommencer'), findsOneWidget);
    expect(find.text('Historique'), findsOneWidget);
  });

  testWidgets('navigation seule : carte navigation + rappel test complet',
      (tester) async {
    await _pomper(tester, _navigationSeule());

    expect(find.textContaining('Navigation web'), findsWidgets);
    expect(find.textContaining('Chargement moyen'), findsOneWidget);
    // Tableau des 6 sites (croquis ⑥) : une ligne par page, résultat ✓/✗,
    // décimales françaises. Les libellés peuvent être surlignés
    // (« Google ★ », « Lefaso.net · lent ») → textContaining.
    expect(find.textContaining('Google'), findsWidgets);
    expect(find.textContaining('Wikipédia'), findsOneWidget);
    expect(find.textContaining('Facebook'), findsOneWidget);
    expect(find.textContaining('Lefaso.net'), findsWidgets,
        reason: 'ligne du tableau + mention « plus lent »');
    expect(find.textContaining('YouTube'), findsOneWidget);
    expect(find.textContaining('Bing'), findsOneWidget);
    expect(find.text('0,8 s'), findsOneWidget,
        reason: 'Google, page la plus rapide (800 ms)');
    expect(find.text('Chargée ✓'), findsNWidgets(5));
    expect(find.text('Échec ✗'), findsOneWidget,
        reason: 'Bing en timeout (30 s)');
    expect(find.textContaining('plus rapide'), findsOneWidget);
    expect(find.textContaining('plus lent'), findsOneWidget);
    expect(find.textContaining('2.4'), findsNothing,
        reason: 'point décimal anglais interdit');
    expect(find.textContaining('pts YELE'), findsOneWidget);
    expect(find.textContaining('Score partiel'), findsOneWidget);
    expect(find.textContaining('COMPARAISON'), findsWidgets);
    expect(find.textContaining('test complet'), findsOneWidget,
        reason: 'rappel discret en usage seul');
    expect(find.textContaining('Serveur de test'), findsOneWidget);
    expect(find.text('Recommencer'), findsOneWidget);
    expect(find.text('Historique'), findsOneWidget);
  });

  testWidgets('test complet : tuiles, min/moy/max, deux usages, verdict',
      (tester) async {
    await _pomper(tester, _complet());

    expect(find.textContaining('pts YELE'), findsOneWidget);
    expect(find.text('64 000'), findsOneWidget,
        reason: 'score global affiché dans le cercle');
    expect(find.textContaining('Très faible'), findsNothing);
    expect(find.textContaining('Moyen'), findsWidgets,
        reason: '64 000 pts → « Moyen » (seuils 30 000/70 000)');
    expect(find.textContaining('DOWNLOAD'), findsOneWidget);
    expect(find.textContaining('MIN / MOY / MAX'), findsOneWidget);
    expect(find.textContaining('Streaming vidéo'), findsWidgets);
    expect(find.textContaining('Navigation web'), findsWidgets);
    expect(find.textContaining('COMPARAISON'), findsWidgets);
    expect(find.textContaining('refaites un test complet'), findsNothing,
        reason: 'rappel réservé à l\'usage seul');
    expect(
        find.text('Évaluer la qualité de mon test complet'), findsOneWidget);
    expect(find.text('Recommencer'), findsOneWidget);
    expect(find.text('Historique'), findsOneWidget);
  });

  test('roundtrip Hive : le détail par site (index 62) survit à l\'écriture',
      () async {
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(SpeedTestResultAdapter());
    }
    final box = await Hive.openBox<SpeedTestResult>('repro_field62');
    await box.put('nav', _navigationSeule());
    final lu = box.get('nav')!;
    expect(lu.browsingPagesJson, isNotNull);
    final pages = lu.browsingPages;
    expect(pages, hasLength(6));
    expect(pages.first.label, 'Google');
    expect(pages.first.loadMs, 800);
    expect(pages.first.success, isTrue);
    expect(pages.last.label, 'Bing');
    expect(pages.last.success, isFalse);
    // Ancien enregistrement sans détail : liste vide, pas de crash.
    final ancien = box.get('ancien');
    expect(ancien, isNull);
    expect(SpeedTestResult(downloadSpeed: 1, uploadSpeed: 1, ping: 1,
            jitter: 1, server: 'x')
        .browsingPages, isEmpty);
    await box.close();
  });

  test('roundtrip Hive : les réponses QoE (index 63) survivent', () async {
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(SpeedTestResultAdapter());
    }
    final box = await Hive.openBox<SpeedTestResult>('repro_field63');
    final r = _complet()
      ..qoeAnswersJson =
          jsonEncode({'test_type': 'complet', 'tranche_age': '20_40'})
      ..qoeRating = 4
      ..qoeUsage = 'complet'
      ..qoeSatisfaction = 'satisfied';
    await box.put('qoe', r);

    final lu = box.get('qoe')!;
    expect(lu.qoeAnswersJson, contains('"tranche_age":"20_40"'));
    expect(lu.qoeRating, 4);
    expect(lu.qoeUsage, 'complet');
    expect(lu.qoeSatisfaction, 'satisfied');
    await box.close();
  });
}
