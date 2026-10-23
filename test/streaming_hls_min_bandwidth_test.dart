import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yele/constants/config.dart';
import 'package:yele/services/streaming_shared.dart';
import 'package:yele/services/streaming_test_service.dart';
import 'package:yele/services/streaming_test_service_hls.dart';
import 'package:yele/widgets/streaming_table.dart';

StreamingQualityResult _row(String label, {bool reached = false}) =>
    reached
        ? StreamingQualityResult(
            label: label,
            reached: true,
            performanceRate: 96.0,
            initialLoadingSec: 0.9,
            bufferingSec: 0,
            rebufferCount: 0,
            dataUsedKiB: 5000)
        : StreamingQualityResult.unavailable(label);

Widget _host(List<StreamingQualityResult> rows,
        {String engine = 'youtube'}) =>
    MaterialApp(
      home: Scaffold(body: StreamingTable(qualities: rows, videoEngine: engine)),
    );

void main() {
  group('minRequiredKbpsFor (débit mini requis par palier)', () {
    test('fragment 4 s rapporté au timeout 20 s, marge incluse', () {
      // 1080p : BANDWIDTH 4 317 071 b/s → fragment 4 s ≈ 2,06 Mio,
      // à recevoir en ≤ 20 s → 863 kb/s × marge 1,15 ≈ 993 kb/s.
      expect(minRequiredKbpsFor(4317071), 993);
      // 720p : 2 817 071 b/s → 648 kb/s.
      expect(minRequiredKbpsFor(2817071), 648);
      // 2160p : 12 317 071 b/s → 2 833 kb/s.
      expect(minRequiredKbpsFor(12317071), 2833);
    });

    test('sensible au timeout (le 4 s × marge doit apparaître)', () {
      expect(
        minRequiredKbpsFor(4317071, timeoutSec: 10),
        greaterThan(minRequiredKbpsFor(4317071, timeoutSec: 40)),
      );
      // Timeout = durée du fragment, marge neutre : le débit mini rejoint
      // exactement la BANDWIDTH annoncée (4 317 071 b/s → 4 317 kb/s).
      expect(minRequiredKbpsFor(4317071, timeoutSec: 4, margin: 1.0), 4317);
    });

    test('les BANDWIDTH de la config couvrent les trois paliers', () {
      // Garde-fou : si le manifeste change, mettre à jour la config ET
      // rebuild_ladder_mobile_bitrates.sh (débits YouTube mobile).
      expect(STREAMING_LEVEL_BANDWIDTH_BPS.keys, ['hd720', 'hd1080', 'hd2160']);
      expect(STREAMING_LEVEL_BANDWIDTH_BPS.values.every((v) => v > 0), isTrue);
    });

    test('marge appliquée', () {
      expect(
        minRequiredKbpsFor(4317071, margin: 1.15),
        greaterThan(minRequiredKbpsFor(4317071, margin: 1.0)),
      );
    });
  });

  group('détection du moteur HLS (URL du flux configuré)', () {
    test("l'URL .m3u8 de la config active l'estimation du débit mini", () {
      // hlsEngine est un late final : évaluable sans réseau, il décide de
      // l'affichage de la ligne « Débit mini requis » et des logs associés.
      expect(StreamingTestServiceHls().hlsEngine, isTrue);
      expect(StreamingTestServiceHls().minRequiredKbps, isEmpty);
    });
  });

  group('marque moteur dans le résultat persisté', () {
    test("le moteur HLS étiquette ses résultats 'hls'", () {
      final rows = [_row('720p', reached: true)];
      final r = aggregateStreamingResults(rows, engine: 'hls');
      expect(r.engine, 'hls');
      expect(
        StreamingTestResult.decodeEngine(r.encodeQualities()),
        'hls',
      );
    });

    test("le moteur YouTube étiquette ses résultats 'youtube'", () {
      final rows = [_row('720p', reached: true)];
      final r = aggregateStreamingResults(rows, engine: 'youtube');
      expect(StreamingTestResult.decodeEngine(r.encodeQualities()),
          'youtube');
    });

    test('anciens résultats sans marque → null (affichage rétro YouTube)', () {
      final legacy = '{"rows":[{"label":"720p","reached":true,'
          '"performanceRate":90.0,"initialLoadingSec":1.0,'
          '"bufferingSec":0.0,"rebufferCount":0,"dataUsedKiB":2000,'
          '"stable":true}]}';
      expect(StreamingTestResult.decodeEngine(legacy), isNull);
      expect(StreamingTestResult.decodeError(legacy), isNull);
    });

    test('la marque moteur traverse le JSON même en cas d\u2019erreur', () {
      final r = aggregateStreamingResults(
          [_row('720p')], engine: 'hls', error: 'Flux injoignable');
      final json = r.encodeQualities();
      expect(StreamingTestResult.decodeEngine(json), 'hls');
      expect(StreamingTestResult.decodeError(json), 'Flux injoignable');
    });
  });

  group('StreamingTable — ligne « Débit mini requis »', () {
    final rows = [
      _row('720p', reached: true),
      _row('1080p'),
      _row('2160p'),
    ];

    testWidgets('absente en moteur YouTube', (tester) async {
      await tester.pumpWidget(_host(rows));
      expect(find.text('Débit mini requis'), findsNothing);
      expect(find.text('YouTube'), findsOneWidget);
    });

    testWidgets('présente en moteur HLS avec les valeurs calculées',
        (tester) async {
      await tester.pumpWidget(_host(rows, engine: 'hls'));
      expect(find.text('Débit mini requis'), findsOneWidget);
      expect(find.text('HLS'), findsOneWidget);
      // Valeurs issues de STREAMING_LEVEL_BANDWIDTH_BPS (config).
      expect(
          find.text('≥ ${(minRequiredKbpsFor(
                  STREAMING_LEVEL_BANDWIDTH_BPS['hd720']!) /
              1e3).toStringAsFixed(2)} Mb/s'),
          findsOneWidget);
      // Palier non servi : la valeur requise reste affichée (c'est le but :
      // expliquer la colonne vide), les indicateurs restent à « — ».
      expect(find.text('—'), findsWidgets);
      expect(find.textContaining('Mb/s'), findsNWidgets(3));
    });

    testWidgets('note explicative sous la ligne', (tester) async {
      await tester.pumpWidget(_host(rows, engine: 'hls'));
      expect(find.textContaining('Premier fragment (4 s)'), findsOneWidget);
    });
  });
}
