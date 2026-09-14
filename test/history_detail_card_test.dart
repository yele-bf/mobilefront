import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yele/models/speed_test_result.dart';
import 'package:yele/widgets/history_detail_card.dart';

/// Résultat 4G réaliste, calqué sur la capture « Historique » : Orange BF à
/// Ouagadougou, RSRP −77 dBm (Excellent), RSRQ −8 dB.
SpeedTestResult _result({
  int? signalRsrp,
  int? signalRsrq,
  int? signalNrRsrp,
  int? signalNrRsrq,
  int? wifiRssi,
  int? signalDbm,
  String? networkType = '4G',
  String? cellularTech = '4G',
  String? simOperator = 'Orange BF',
  double? latitude,
  double? longitude,
}) {
  return SpeedTestResult(
    downloadSpeed: 12.5,
    uploadSpeed: 3.2,
    ping: 45,
    jitter: 8,
    server: 'Render.com',
    networkType: networkType,
    operator: 'Orange Burkina Faso',
    location: 'Ouagadougou, Burkina Faso',
    cellularTech: cellularTech,
    simOperator: simOperator,
    signalRsrp: signalRsrp,
    signalRsrq: signalRsrq,
    signalNrRsrp: signalNrRsrp,
    signalNrRsrq: signalNrRsrq,
    wifiRssi: wifiRssi,
    signalDbm: signalDbm,
    latitude: latitude,
    longitude: longitude,
  );
}

Future<void> _pumpCard(WidgetTester tester, SpeedTestResult r) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: HistoryDetailCard(result: r, resolvedAddresses: const {}),
      ),
    ),
  ));
}

/// Retrouve le [Row] le plus proche englobant le texte trouvé par [finder],
/// ou null s'il n'y en a pas. Sert à vérifier que deux libellés de détail ne
/// partagent pas la même ligne (le détail rend un Row par ligne « clé : valeur »).
Row? _enclosingRow(WidgetTester tester, Finder finder) {
  final rows = find.ancestor(of: finder, matching: find.byType(Row));
  return rows.evaluate().isEmpty ? null : tester.widget<Row>(rows.first);
}

void main() {
  group('HistoryDetailCard — lignes Signal / Qualité du signal', () {
    testWidgets('un test 4G affiche RSRP et RSRQ sur deux lignes distinctes',
        (tester) async {
      await _pumpCard(tester, _result(signalRsrp: -77, signalRsrq: -8));

      // Deux libellés distincts, chacun présent une seule fois.
      expect(find.text('Signal :'), findsOneWidget);
      expect(find.text('Qualité du signal :'), findsOneWidget);

      // Les valeurs attendues, une par ligne.
      expect(find.text('RSRP -77 dBm (Excellent)'), findsOneWidget);
      expect(find.text('RSRQ -8 dB'), findsOneWidget);

      // Plus jamais l'ancien format à une seule ligne jointe par « · ».
      expect(find.text('RSRP -77 dBm (Excellent) · RSRQ -8 dB'), findsNothing);

      // Les deux libellés ne vivent pas dans le même Row.
      final signalRow = _enclosingRow(tester, find.text('Signal :'));
      final qualityRow = _enclosingRow(tester, find.text('Qualité du signal :'));
      expect(signalRow, isNotNull);
      expect(qualityRow, isNotNull);
      expect(
        identical(signalRow, qualityRow),
        isFalse,
        reason:
            'Signal et Qualité du signal doivent être rendus sur deux lignes séparées',
      );

      // Et la ligne Signal est empilée au-dessus de Qualité du signal.
      expect(
        tester.getTopLeft(find.text('Signal :')).dy,
        lessThan(tester.getTopLeft(find.text('Qualité du signal :')).dy),
      );
    });

    testWidgets('repli générique : signalDbm seul reste sur « Signal »',
        (tester) async {
      await _pumpCard(tester, _result(signalDbm: -92));

      expect(find.text('Signal :'), findsOneWidget);
      expect(find.text('-92 dBm'), findsOneWidget);
      expect(find.text('Qualité du signal :'), findsNothing);
    });

    testWidgets('Wi-Fi : RSSI sur « Signal », pas de ligne qualité',
        (tester) async {
      await _pumpCard(
        tester,
        _result(
          networkType: 'WiFi',
          cellularTech: null,
          simOperator: null,
          wifiRssi: -55,
        ),
      );

      expect(find.text('Signal :'), findsOneWidget);
      expect(find.text('RSSI -55 dBm (Excellent)'), findsOneWidget);
      expect(find.text('Qualité du signal :'), findsNothing);
    });

    testWidgets('aucune métrique mesurée : aucune ligne signal',
        (tester) async {
      await _pumpCard(tester, _result());

      expect(find.text('Signal :'), findsNothing);
      expect(find.text('Qualité du signal :'), findsNothing);
    });
  });
}
