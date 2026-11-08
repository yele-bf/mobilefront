import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yele/models/speed_test_result.dart';
import 'package:yele/services/export_service.dart';

/// Mesure complète (valeurs réelles du 07/11/2026, Nothing Phone 3a,
/// Wi-Fi « Tecno2G », serveur Francfort) — base de la revue IMP-11.
SpeedTestResult _rich() => SpeedTestResult(
      timestamp: DateTime(2026, 11, 7, 16, 37),
      downloadSpeed: 11.70,
      uploadSpeed: 6.68,
      ping: 294,
      jitter: 28,
      server: 'yele-backend.onrender.com',
      networkType: 'WiFi',
      operator: 'Orange Burkina Faso',
      latitude: 12.370194,
      longitude: -1.478940,
      location: 'Ouagadougou, Burkina Faso',
      deviceModel: 'Nothing Phone (3a)',
      osVersion: 'Android 17',
      wifiSsid: 'Tecno2G',
      wifiRssi: -43,
      packetLoss: 5,
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
      streamingRebufferRatio: 0.0,
      streamingQualitiesJson: jsonEncode([
        {
          'label': '720p',
          'reached': true,
          'performanceRate': 88,
          'initialLoadingSec': 1.4,
        },
        {
          'label': '1080p',
          'reached': true,
          'performanceRate': 85,
          'initialLoadingSec': 1.7,
        },
        {
          'label': '1440p',
          'reached': true,
          'performanceRate': 94,
          'initialLoadingSec': 0.7,
        },
        {
          'label': '2160p',
          'reached': true,
          'performanceRate': 90,
          'initialLoadingSec': 1.2,
        },
      ]),
      browsingScore: 99,
      browsingAvgLoadMs: 1500,
      browsingSuccessRate: 1.0,
      browsingPagesTested: 6,
      scoringVersion: 'yele-open-1.0.0',
      scoreDownload: 19318,
      scoreUpload: 6641,
      scorePingJitter: 0,
      scoreBrowsing: 14899,
      scoreStreaming: 17500,
      scoreGlobal: 58358,
    );

List<String> _values(
        List<({String title, List<List<String>> rows})> sections,
        String title) =>
    sections.firstWhere((s) => s.title == title).rows.map((r) => r[1]).toList();

void main() {
  group('measureSections (revue IMP-11 du 07/11) — compéteur complet', () {
    late final sections = ExportService.measureSections(_rich());

    test('les six catégories de l\'app sont présentes et dans l\'ordre', () {
      expect(
        sections.map((s) => s.title).toList(),
        [
          'Position', 'Connexion', 'Débit & Latence', 'Signal radio',
          'Qualité perçue', 'Score Yélé',
        ],
      );
    });

    test('Position : Adresse (6 places), GPS, lat/lon', () {
      final v = _values(
        ExportService.measureSections(_rich(),
            address: 'Rue 13.58, Zogona, Ouagadougou, Kadiogo, Centre, Burkina Faso'),
        'Position',
      );
      expect(
        v,
        contains('Rue 13.58, Zogona, Ouagadougou, Kadiogo, Centre, Burkina Faso'),
      );
      expect(v, contains('12.3702, -1.4789'));
      expect(v, contains('12.370194'));
      expect(v, contains('-1.478940'));
    });

    test('Position sans adresse : « non disponible · GPS seul »', () {
      final v = _values(
        ExportService.measureSections(_rich()),
        'Position',
      );
      expect(v.first, 'non disponible · GPS seul');
    });

    test('Connexion : SSID Wi-Fi et FAI en Wi-Fi, pas de réseau mobile', () {
      final v = _values(sections, 'Connexion');
      expect(v, contains('WiFi'));
      expect(v, contains('Orange Burkina Faso'));
      expect(v, contains('Tecno2G'));
      expect(v, contains('Nothing Phone (3a)'));
      expect(v, contains('Android 17'));
      // Règle B1 : pas de ligne réseau mobile en Wi-Fi.
      expect(sections
          .firstWhere((s) => s.title == 'Connexion')
          .rows
          .map((r) => r[0]), isNot(contains('Réseau mobile')));
    });

    test('Débit & Latence : min/moy/max, perte de paquets, données', () {
      final v = _values(sections, 'Débit & Latence');
      expect(v, contains('5.82 / 11.70 / 17.61 Mb/s'));
      expect(v, contains('2.23 / 6.68 / 45.62 Mb/s'));
      expect(v, contains('267 / 294 / 467 ms'));
      expect(v, contains('5 %'));
      expect(v, contains('82.3'));
    });

    test('Signal radio : RSSI avec palier qualité', () {
      final v = _values(sections, 'Signal radio');
      expect(v, contains('RSSI -43 dBm (Excellent)'));
    });

    test('Qualité perçue : agrégat, paliers, navigation', () {
      final v = _values(sections, 'Qualité perçue');
      expect(v, contains('1080p · 90/100'));
      expect(v, contains('88 % · 1.4 s'));
      expect(v, contains('94 % · 0.7 s'));
      expect(v, contains('1.5 s · 99/100'));
      expect(v, contains('100 %'));
      expect(v, contains('6'));
    });

    test('Score Yélé : référentiel, score ouvert, indice, composantes', () {
      final section = sections.firstWhere((s) => s.title == 'Score Yélé');
      final labels = section.rows.map((r) => r[0]).toList();
      final values = section.rows.map((r) => r[1]).toList();
      expect(labels,
          containsAll(['Référentiel', 'Score ouvert', 'Indice (lecture)', 'Download', 'Upload', 'Latence', 'Navigation', 'Streaming']));
      expect(values, contains('yele-open-1.0.0'));
      expect(values.firstWhere((v) => v.contains('pts ·')), startsWith('58358 pts · '));
      expect(values, contains('78/100'));
      expect(values, contains('19318 pts'));
      expect(values, contains('14899 pts'));
    });
  });

  group('ASCII du CSV (revue 07/11 : lecteur du propriétaire, sans accents)', () {
    test('asciiFold plie les accents et symboles FR', () {
      expect(ExportService.asciiFold('Qualité perçue'), 'Qualite percue');
      expect(ExportService.asciiFold('Données consommées'), 'Donnees consommees');
      expect(ExportService.asciiFold('Référentiel'), 'Referentiel');
      expect(ExportService.asciiFold('Évaluation QoE'), 'Evaluation QoE');
      expect(ExportService.asciiFold('12.3702, -1.4789'), '12.3702, -1.4789');
      expect(ExportService.asciiFold('Latence (ping)'), 'Latence (ping)');
      // Symboles définis dans la table de pliage.
      expect(ExportService.asciiFold('Francfort, Allemagne — x'), 'Francfort, Allemagne - x');
      expect(ExportService.asciiFold('90/100 · 2.0 s'), '90/100 - 2.0 s');
      expect(ExportService.asciiFold('Latitude °'), 'Latitude deg');
      // Caractère hors table : retiré, jamais corrompu.
      expect(ExportService.asciiFold('a\u00e9b\u4e2dc'), 'aeb c'.replaceAll(' ', ''));
    });

    test('aucune ligne CSV ne contient de caractère non-ASCII', () {
      // On vérifie le pliage sur la mesure complète en passant par les
      // sections + asciiFold, qui est la base de la fabrication du CSV.
      final sections = ExportService.measureSections(_rich());
      for (final s in sections) {
        for (final field in [s.title, ...s.rows.expand((r) => r)]) {
          final folded = ExportService.asciiFold(field);
          expect(
            folded.runes.any((r) => r > 127),
            isFalse,
            reason: 'Champ non plié : "$field" → "$folded"',
          );
        }
      }
    });
  });

  group('measureSections — mesure héritée (sans scoring, sans signal)', () {
    test('pas de section Score Yélé, débits simples, adresse conservée', () {
      final legacy = SpeedTestResult(
        timestamp: DateTime(2026, 10, 1, 9, 0),
        downloadSpeed: 1.0,
        uploadSpeed: 0.5,
        ping: 500,
        jitter: 40,
        server: 'yele-backend.onrender.com',
        networkType: 'WiFi',
        latitude: 12.370194,
        longitude: -1.478940,
      );
      final sections = ExportService.measureSections(
        legacy,
        address: 'Ouagadougou, Kadiogo, Centre, Burkina Faso',
      );
      expect(sections.map((s) => s.title).toList(),
          ['Position', 'Connexion', 'Débit & Latence']);
      final debit = sections.firstWhere((s) => s.title == 'Débit & Latence');
      final labels = debit.rows.map((r) => r[0]).toList();
      expect(labels, contains('Download')); // 1.00 Mb/s simple
      expect(labels, contains('Upload'));
      expect(labels, contains('Latence (ping)')); // pas de stats ISS-06
      // Vérifie l'ordre (pas de score ni signal ni qualité perçue).
      final position =
          sections.firstWhere((s) => s.title == 'Position');
      expect(position.rows.first[1],
          'Ouagadougou, Kadiogo, Centre, Burkina Faso');
    });

    test('mesure sans coordonnées : la section Position disparaît', () {
      final legacy = SpeedTestResult(
        timestamp: DateTime(2026, 10, 1, 9, 0),
        downloadSpeed: 1.0,
        uploadSpeed: 0.5,
        ping: 500,
        jitter: 40,
        server: 'yele-backend.onrender.com',
      );
      final titles = ExportService.measureSections(legacy)
          .map((s) => s.title)
          .toList();
      expect(titles, isNot(contains('Position')));
    });
  });
}
