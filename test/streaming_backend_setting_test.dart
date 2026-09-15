import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:yele/constants/config.dart';
import 'package:yele/services/streaming_backend_setting.dart';

void main() {
  group('StreamingBackendSetting (surcharge à chaud du moteur streaming)', () {
    late Directory tmp;
    final setting = StreamingBackendSetting();

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('yele_backend_setting');
      Hive.init(tmp.path);
      await setting.initialize();
    });

    tearDown(() async {
      await setting.dispose();
      await tmp.delete(recursive: true);
    });

    test('sans surcharge : moteur effectif = drapeau compilé', () {
      expect(setting.hasOverride, isFalse);
      expect(setting.overrideValue, isNull);
      expect(setting.effectiveBackend, streamingBackend);
      expect(StreamingBackendSetting.choices, contains(streamingBackend));
    });

    test('setBackend change le moteur effectif et persiste', () async {
      final other =
          StreamingBackendSetting.choices.firstWhere((c) => c != streamingBackend);

      await setting.setBackend(other);
      expect(setting.hasOverride, isTrue);
      expect(setting.effectiveBackend, other);

      // Ré-ouverture : la surcharge survit (persistance Hive).
      await setting.dispose();
      await setting.initialize();
      expect(setting.effectiveBackend, other);
    });

    test('resetToDefault revient au drapeau compilé', () async {
      await setting.setBackend('hls');
      expect(setting.effectiveBackend, 'hls');

      await setting.resetToDefault();
      expect(setting.hasOverride, isFalse);
      expect(setting.effectiveBackend, streamingBackend);
    });

    test('valeur invalide ignorée : repli silencieux sur le défaut', () async {
      await setting.setBackend('dashjs');
      expect(setting.hasOverride, isFalse);
      expect(setting.effectiveBackend, streamingBackend);
    });

    test('valeur stockée illisible : équivalente à une absence de surcharge',
        () async {
      final box = Hive.box<String>('appSettings');
      await box.put('streamingBackend', 'valeur-ancienne-version');

      expect(setting.overrideValue, isNull);
      expect(setting.effectiveBackend, streamingBackend);
    });

    test('boîte fermée : jamais d\'exception, valeur d\'usine', () async {
      await setting.setBackend('hls');
      await setting.dispose(); // ferme la boîte

      expect(setting.effectiveBackend, streamingBackend);
      expect(setting.hasOverride, isFalse);
    });
  });
}
