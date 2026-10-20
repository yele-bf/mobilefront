import 'package:flutter_test/flutter_test.dart';
import 'package:yele/models/speed_test_result.dart';

void main() {
  test('preserves the active data SIM slot in measurement JSON', () {
    final result = SpeedTestResult.fromJson({
      'downloadSpeed': 10,
      'uploadSpeed': 2,
      'ping': 40,
      'jitter': 3,
      'server': 'Render.com',
      'simOperator': 'Orange Burkina Faso',
      'cellularTech': '4G',
      'dataSimSlot': 1,
    });

    expect(result.simSlot, 1);
    expect(result.toJson()['simSlot'], 1);
  });

  test('keeps older measurements without SIM slot information valid', () {
    final result = SpeedTestResult.fromJson({
      'downloadSpeed': 10,
      'uploadSpeed': 2,
      'ping': 40,
      'jitter': 3,
      'server': 'Render.com',
    });

    expect(result.simSlot, isNull);
  });
}
