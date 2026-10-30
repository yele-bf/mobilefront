import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:yele/main.dart';
import 'package:yele/services/consent_service.dart';

/// IMP-14 — conditions d'utilisation au premier lancement.
void main() {
  group('ConsentService (accord persistant)', () {
    late Directory tmp;
    final consent = ConsentService.instance;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('yele_consent');
      Hive.init(tmp.path);
      await consent.initialize();
    });

    tearDown(() async {
      await consent.dispose();
      await tmp.delete(recursive: true);
    });

    test('premier lancement : aucun accord', () {
      expect(consent.hasAccepted, isFalse);
      expect(consent.acceptedAt, isNull);
    });

    test('accept est conservé à la réouverture (lancements suivants)',
        () async {
      await consent.accept();
      expect(consent.hasAccepted, isTrue);
      expect(consent.acceptedAt, isNotNull);

      await consent.dispose();
      await consent.initialize();
      expect(consent.hasAccepted, isTrue);
    });

    test('withdraw redemande l\'accord', () async {
      await consent.accept();
      await consent.withdraw();
      expect(consent.hasAccepted, isFalse);
    });
  });

  testWidgets('sans accord, l\'app s\'ouvre sur les conditions d\'utilisation',
      (WidgetTester tester) async {
    await tester.pumpWidget(const YeleApp(hasAccepted: false));
    await tester.pump();

    expect(find.text('Conditions d\'utilisation'), findsOneWidget);
    expect(find.text('J\'accepte et je continue'), findsOneWidget);
    expect(find.text('Refuser et quitter'), findsOneWidget);
    expect(find.text('Test complet'), findsNothing);
  });
}
