import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import '../lib/models/speed_test_result.dart';
import '../lib/services/export_service.dart';

void main() {
  test('génère le PDF du rapport pour vérification PNG', () async {
    final r = SpeedTestResult(
      downloadSpeed: 90.54,
      uploadSpeed: 81.14,
      ping: 29,
      jitter: 24,
      server: 'Yélé serveur - Ouagadougou',
    )
      ..timestamp = DateTime(2026, 9, 9, 23, 52, 8)
      ..networkType = 'WiFi'
      ..operator = 'private IPv4 access"'
      ..cellularTech = '4G'
      ..simOperator = 'Moov Africa BF'
      ..server = 'Yélé serveur - Ouagadougou'
      ..latitude = 12.381562
      ..longitude = -1.485557
      ..qoeRating = 3
      ..qoeSatisfaction = 'satisfied'
      ..deviceModel = 'Nothing Phone (3a)'
      ..osVersion = 'Android 16';

    final svc = ExportService();
    // Réutilise le builder privé via l'export PDF : le PDF produit est le
    // même que celui rasterisé en PNG par l'app.
    final docBytes = await svc.buildPdfBytesForTest(r);
    File('build/yele_mesure_test.png.pdf').writeAsBytesSync(docBytes);
    expect(docBytes.isNotEmpty, isTrue);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
