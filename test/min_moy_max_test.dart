import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:yele/models/speed_test_result.dart';

/// ISS-06 — min / moy / max des débits et de la latence.
void main() {
  SpeedTestResult result({double? dlMin, double? dlMax}) => SpeedTestResult(
        downloadSpeed: 18.4,
        uploadSpeed: 6.1,
        ping: 52,
        jitter: 7,
        server: 'test',
        downloadMin: dlMin,
        downloadMax: dlMax,
        uploadMin: 2.3,
        uploadMax: 9.8,
        pingMin: 38,
        pingMax: 97,
      );

  test('les trois valeurs : moyenne = valeur principale du test', () {
    final r = result(dlMin: 3.2, dlMax: 41);
    expect(r.downloadStats, (min: 3.2, mean: 18.4, max: 41.0));
    expect(r.uploadStats, (min: 2.3, mean: 6.1, max: 9.8));
    expect(r.pingStats, (min: 38.0, mean: 52.0, max: 97.0));
  });

  test('min ou max absent : métrique non affichable', () {
    expect(result(dlMin: 3.2).downloadStats, isNull);
    expect(result().downloadStats, isNull);
    final ancien = SpeedTestResult(
        downloadSpeed: 10, uploadSpeed: 2, ping: 40, jitter: 5, server: 's');
    expect(ancien.downloadStats, isNull);
    expect(ancien.uploadStats, isNull);
    expect(ancien.pingStats, isNull);
  });

  test('min et max survivent au stockage Hive (index 53 à 58)', () async {
    final tmp = await Directory.systemTemp.createTemp('yele_minmax');
    Hive.init(tmp.path);
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(SpeedTestResultAdapter());
    }
    final box = await Hive.openBox<SpeedTestResult>('minmax');
    await box.put('r', result(dlMin: 3.2, dlMax: 41));
    await box.close();

    final relu = (await Hive.openBox<SpeedTestResult>('minmax')).get('r')!;
    expect(relu.downloadMin, 3.2);
    expect(relu.downloadMax, 41);
    expect(relu.uploadMin, 2.3);
    expect(relu.uploadMax, 9.8);
    expect(relu.pingMin, 38);
    expect(relu.pingMax, 97);

    await Hive.close();
    await tmp.delete(recursive: true);
  });
}
