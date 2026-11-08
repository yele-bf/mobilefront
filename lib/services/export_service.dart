import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart' show Color;
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart' show PdfColor, PdfPageFormat;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../constants/config.dart';
import '../models/speed_test_result.dart';
import 'packet_loss_service.dart';
import 'reverse_geocoding_service.dart';
import 'yele_scoring_engine.dart';
import '../theme/yele_theme.dart';

/// IMP-11 — Export d'une mesure, façon nPerf : depuis l'écran de résultat
/// ou l'historique, l'utilisateur partage la mesure choisie au format
/// CSV, Excel (xlsx), PDF (rapport brandé) ou PNG (résumé en image).
/// (Ancien libellé « IMP-13 » des commentaires : drift de nomenclature
/// V11 → V14 corrigé le 07/11/2026 — en V14, IMP-13 = identification
/// appareil.)
///
/// Le fichier est écrit dans le répertoire temporaire de l'app puis remis
/// à la feuille de partage Android (Fichiers, WhatsApp, e-mail, Drive…).
/// L'app ne demande aucune permission : ni stockage (répertoire privé +
/// share sheet), ni localisation (les coordonnées viennent de la mesure).
///
/// Revue du 07/11/2026 : les quatre formats partagent la même source de
/// vérité ([measureSections]) et portent les catégories de l'app (Position,
/// Connexion, Débit & Latence, Signal radio, Qualité perçue, Score Yélé) —
/// l'Excel ne se limite plus au bloc « Détails » et le CSV reste
/// Champ;Valeur;Unité avec une ligne de titre par catégorie.
class ExportService {
  static const _appName = 'Yélé';
  static const _appTagline = 'Mesure de la qualité des réseaux mobiles';

  // ── API publique ─────────────────────────────────────────────────────────

  Future<void> exportCsv(SpeedTestResult r) async {
    final address = await _resolveAddress(r);
    final bytes = Uint8List.fromList(utf8.encode(_csv(r, address: address)));
    await _shareFile(
      bytes,
      'Yele_mesure_${_stamp(r)}.csv',
      'text/csv',
      'Mesure Yélé (CSV)',
    );
  }

  Future<void> exportExcel(SpeedTestResult r) async {
    final address = await _resolveAddress(r);
    final excel = Excel.createExcel();
    final sheet = excel['Mesure'];

    // Bandeau Yélé (fusionné) puis en-têtes : l'utilisateur ouvre un vrai
    // classeur, lisible dans Excel comme dans LibreOffice.
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
      CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 0),
    );
    final brand = sheet.cell(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
    );
    brand.value = TextCellValue('$_appName — $_appTagline');
    brand.cellStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString(
        'FF0BB89C',
      ), // YeleColors.primary
      fontColorHex: ExcelColor.white,
    );

    const headers = ['Champ', 'Valeur', 'Unité'];
    for (var i = 0; i < headers.length; i++) {
      final c = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 1),
      );
      c.value = TextCellValue(headers[i]);
      c.cellStyle = CellStyle(
        bold: true,
        backgroundColorHex: ExcelColor.fromHexString('FFE7EBEF'),
      );
    }

    var rowIndex = 2;
    for (final section in measureSections(r, address: address)) {
      // Ligne de titre de catégorie (teinte de la marque).
      final title = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex),
      );
      title.value = TextCellValue(section.title);
      title.cellStyle = CellStyle(
        bold: true,
        backgroundColorHex: ExcelColor.fromHexString('FFE0F2F1'),
      );
      rowIndex++;
      for (final row in section.rows) {
        for (var j = 0; j < row.length && j < 3; j++) {
          sheet
              .cell(
                CellIndex.indexByColumnRow(columnIndex: j, rowIndex: rowIndex),
              )
              .value = TextCellValue(
            row[j],
          );
        }
        rowIndex++;
      }
    }
    sheet.setColumnWidth(0, 34);
    sheet.setColumnWidth(1, 44);
    sheet.setColumnWidth(2, 10);

    // Le package crée une feuille « Sheet1 » par défaut : on la retire pour
    // n'exposer que « Mesure » (excel.encode exige au moins une feuille).
    if (excel.sheets.containsKey('Sheet1') && excel.sheets.length > 1) {
      excel.delete('Sheet1');
    }

    await _shareFile(
      Uint8List.fromList(excel.encode()!),
      'Yele_mesure_${_stamp(r)}.xlsx',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'Mesure Yélé (Excel)',
    );
  }

  Future<void> exportPdf(SpeedTestResult r) async {
    final address = await _resolveAddress(r);
    final doc = await _buildPdf(r, address: address);
    await _shareFile(
      await doc.save(),
      'Yele_mesure_${_stamp(r)}.pdf',
      'application/pdf',
      'Mesure Yélé (PDF)',
    );
  }

  /// PNG = le rapport A4 rasterisé : toutes les pages produites sont
  /// recollées verticalement au cas où le contenu passe sur deux pages
  /// (revue 07/11 : les six catégories ne tiennent plus dans une seule
  /// page ; un PNG tronqué serait inacceptable).
  Future<void> exportPng(SpeedTestResult r) async {
    final address = await _resolveAddress(r);
    final doc = await _buildPdf(r, address: address);
    // PNG calibré pour l'ÉCRAN, pas pour l'impression (recherche du 08/11 :
    // l'ancien export net faisait 960×1200 px ≈ 1:1 sur l'A059) ; à 300 dpi
    // l'image (2481×3508) était réduite ×0,43 par la visionneuse → flou.
    // 150 dpi ≈ 1240×1754 px, proche du 1:1 ; le PDF reste vectoriel A4.
    final pages = await Printing.raster(await doc.save(), dpi: 150).toList();
    if (pages.isEmpty) {
      throw Exception('Rasterisation impossible sur cette plateforme');
    }
    final pngs = <Uint8List>[];
    for (final page in pages) {
      pngs.add(await _flattenPngOnWhite(await page.toPng()));
    }
    final png = pngs.length == 1 ? pngs.first : _stackPngs(pngs);
    await _shareFile(
      png,
      'Yele_mesure_${_stamp(r)}.png',
      'image/png',
      'Mesure Yélé (PNG)',
    );
  }

  /// Adresse lisible pour ces coordonnées (mêmes service et cache que
  /// l'historique) ; null si indisponible → « non disponible · GPS seul ».
  Future<String?> _resolveAddress(SpeedTestResult r) async {
    final lat = r.latitude;
    final lon = r.longitude;
    if (lat == null || lon == null) return null;
    try {
      return await ReverseGeocodingService.instance.resolveAddress(lat, lon);
    } catch (_) {
      return null;
    }
  }

  /// Octets du PDF de rapport (même builder que l'export) : utilisé par un
  /// test de vérification du rendu PNG (rasterisation hors app).
  @visibleForTesting
  Future<List<int>> buildPdfBytesForTest(SpeedTestResult r) async =>
      (await _buildPdf(r)).save();

  // ── Sections partagées (source de vérité des 4 formats) ─────────────────

  /// Une section = un titre de catégorie + des lignes Champ;Valeur;Unité.
  /// Les règles d'affichage (libellés, conditions, masquages) sont celles de
  /// la carte de détail de l'historique : ce qui est exporté est ce que
  /// l'utilisateur voit. Une catégorie complètement vide ne s'affiche pas.
  @visibleForTesting
  static List<({String title, List<List<String>> rows})> measureSections(
    SpeedTestResult r, {
    String? address,
  }) {
    final wifi = (r.networkType ?? '').toUpperCase().contains('WIFI');
    final sections = <({String title, List<List<String>> rows})>[];
    final t = r.timestamp;
    final ymd =
        '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')}/${t.year} '
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:'
        '${t.second.toString().padLeft(2, '0')}';

    // Position — Adresse (règle ISS-10 : 6 places) puis GPS/précision.
    if ((r.latitude ?? 0) != 0) {
      final lat = r.latitude!;
      final lon = r.longitude!;
      sections.add((
        title: 'Position',
        rows: [
          // L'export est précédé d'une résolution (mise en cache) :
          // l'adresse est soit connue, soit « non disponible · GPS seul ».
          [
            'Adresse',
            (address ?? '').isNotEmpty ? address! : 'non disponible · GPS seul',
            '',
          ],
          ['GPS', '${lat.toStringAsFixed(4)}, ${lon.toStringAsFixed(4)}', ''],
          ['Latitude', lat.toStringAsFixed(6), '°'],
          ['Longitude', lon.toStringAsFixed(6), '°'],
        ],
      ));
    }

    // Connexion — identité du lien réellement utilisé (règle B1 : FAI et
    // SSID Wi-Fi seulement en Wi-Fi ; Technologie seulement en SIM).
    final connexion = <List<String>>[
      ['Date du test', ymd, ''],
      ['Type de connexion', r.networkType ?? '—', ''],
      if (wifi)
        ['FAI / Opérateur', r.operator ?? '—', '']
      else
        [
          'Réseau mobile',
          (r.simOperator ?? '').isNotEmpty ? r.simOperator! : '—',
          '',
        ],
      if (wifi)
        [
          'SSID Wi-Fi',
          (r.wifiSsid ?? '').trim().isNotEmpty ? r.wifiSsid!.trim() : 'n.d.',
          '',
        ],
      if (!wifi)
        [
          'Technologie',
          (r.technology ?? '').isNotEmpty
              ? r.technology!
              : (r.cellularTech ?? 'n.d.'),
          '',
        ],
      ['Serveur', serverHumanLabel(r.server), ''],
      if ((r.deviceModel ?? '').isNotEmpty) ['Appareil', r.deviceModel!, ''],
      if ((r.osVersion ?? '').isNotEmpty) ['Version OS', r.osVersion!, ''],
    ];
    sections.add((title: 'Connexion', rows: connexion));

    // Débit & Latence — ISS-06 (min/moy/max quand connus), IMP-07 (perte),
    // IMP-01 (données consommées).
    final dl = r.downloadStats;
    final ul = r.uploadStats;
    final pi = r.pingStats;
    sections.add((
      title: 'Débit & Latence',
      rows: [
        if (dl != null)
          [
            'Download min / moy / max',
            '${dl.min.toStringAsFixed(2)} / ${dl.mean.toStringAsFixed(2)} / '
                '${dl.max.toStringAsFixed(2)} Mb/s',
            '',
          ]
        else
          ['Download', r.downloadSpeed.toStringAsFixed(2), 'Mb/s'],
        if (ul != null)
          [
            'Upload min / moy / max',
            '${ul.min.toStringAsFixed(2)} / ${ul.mean.toStringAsFixed(2)} / '
                '${ul.max.toStringAsFixed(2)} Mb/s',
            '',
          ]
        else
          ['Upload', r.uploadSpeed.toStringAsFixed(2), 'Mb/s'],
        if (pi != null)
          [
            'Latence min / moy / max',
            '${pi.min.toStringAsFixed(0)} / ${pi.mean.toStringAsFixed(0)} / '
                '${pi.max.toStringAsFixed(0)} ms',
            '',
          ]
        else
          ['Latence (ping)', r.ping.toStringAsFixed(0), 'ms'],
        ['Gigue (jitter)', r.jitter.toStringAsFixed(0), 'ms'],
        if (r.packetLoss != null)
          ['Perte de paquets', formatPacketLoss(r.packetLoss!), ''],
        if ((r.dataUsedKiB ?? -1) >= 0)
          [
            'Données consommées',
            r.dataUsedKiB! >= 1024
                ? (r.dataUsedKiB! / 1024).toStringAsFixed(1)
                : r.dataUsedKiB!.toString(),
            r.dataUsedKiB! >= 1024 ? 'Mo' : 'Ko',
          ],
      ],
    ));

    // Signal radio — mêmes métriques et paliers que l'historique
    // (RSRP/RSRQ en cellulaire, RSSI en Wi-Fi, repli générique).
    final signal = _signalRows(r);
    if (signal.isNotEmpty) sections.add((title: 'Signal radio', rows: signal));

    // Qualité perçue — streaming (agrégat + détails + paliers), navigation,
    // QoE si l'utilisateur l'a saisie.
    final perceived = <List<String>>[
      if (r.hasStreamingTest) ...[
        [
          'Streaming',
          '${r.streamingMaxResolution ?? '—'} · '
              '${(r.streamingScore ?? 0).toStringAsFixed(0)}/100',
          '',
        ],
        ['Démarrage vidéo', '${r.streamingStartupMs ?? 0}', 'ms'],
        ['Interruptions (rebuffering)', '${r.streamingRebufferCount ?? 0}', ''],
        [
          'Part du temps en tampon',
          ((r.streamingRebufferRatio ?? 0) * 100).toStringAsFixed(1),
          '%',
        ],
        for (final q in r.streamingQualities)
          [
            'Streaming ${q.label}',
            q.reached
                ? '${q.performanceRate.toStringAsFixed(0)} % · '
                      '${q.initialLoadingSec.toStringAsFixed(1)} s'
                : '—',
            '',
          ],
      ],
      if (r.hasBrowsingTest) ...[
        [
          'Navigation',
          '${((r.browsingAvgLoadMs ?? 0) / 1000).toStringAsFixed(1)} s · '
              '${(r.browsingScore ?? 0).toStringAsFixed(0)}/100',
          '',
        ],
        [
          'Taux de réussite',
          '${((r.browsingSuccessRate ?? 0) * 100).toStringAsFixed(0)} %',
          '',
        ],
        ['Pages testées', (r.browsingPagesTested ?? 0).toString(), ''],
      ],
      if (r.qoeRating != null && r.qoeRating! > 0) ...[
        ['Évaluation QoE', '${r.qoeRating}/5', ''],
        if ((r.qoeUsage ?? '').isNotEmpty) ['Usage principal', r.qoeUsage!, ''],
        if ((r.qoeSatisfaction ?? '').isNotEmpty)
          ['Commentaire', r.qoeSatisfaction!, ''],
      ],
    ];
    if (perceived.isNotEmpty) {
      sections.add((title: 'Qualité perçue', rows: perceived));
    }

    // Score Yélé — IMP-05/IMP-12 : référentiel, score ouvert (+ mention),
    // indice de lecture, composantes. Anciennes mesures sans scoring :
    // la section ne s'affiche pas (aucune rétro-attribution).
    if (r.scoringVersion != null) {
      final rows = <List<String>>[
        ['Référentiel', r.scoringVersion!, ''],
      ];
      final global = r.scoreGlobal;
      String pts(double v) => v.toStringAsFixed(0);
      if (global != null) {
        rows.add([
          'Score ouvert',
          '${pts(global)} pts · ${YeleScoringEngine.classify(global).label}',
          '',
        ]);
        final on100 = r.scoreGlobalOn100;
        if (on100 != null) {
          rows.add(['Indice (lecture)', '${on100.toStringAsFixed(0)}/100', '']);
        }
      } else {
        final sub = r.scoreMeasuredSubtotal;
        rows.add([
          'Score ouvert',
          sub == null
              ? 'non mesuré'
              : 'incomplet · ${pts(sub)} pts mesurés '
                    '(composantes absentes exclues)',
          '',
        ]);
      }
      if (r.scoreDownload != null) {
        rows.add(['Download', '${pts(r.scoreDownload!)} pts', '']);
      }
      if (r.scoreUpload != null) {
        rows.add(['Upload', '${pts(r.scoreUpload!)} pts', '']);
      }
      if (r.scorePingJitter != null) {
        rows.add(['Latence', '${pts(r.scorePingJitter!)} pts', '']);
      }
      if (r.scoreBrowsing != null) {
        rows.add(['Navigation', '${pts(r.scoreBrowsing!)} pts', '']);
      }
      if (r.scoreStreaming != null) {
        rows.add(['Streaming', '${pts(r.scoreStreaming!)} pts', '']);
      }
      sections.add((title: 'Score Yélé', rows: rows));
    }

    return sections;
  }

  /// Lignes « Signal radio » : copie conforme de la carte de détail
  /// (history_screen._signalLines) — puissance avec palier, qualité RSRQ,
  /// repli de la mesure générique si aucune métrique typée.
  static List<List<String>> _signalRows(SpeedTestResult r) {
    String qualityLabel(int dbm, {required String kind}) {
      final t = switch (kind) {
        'rsrq' => [-8, -10, -13],
        'rssi' => [-65, -75, -85],
        _ => [-80, -95, -105],
      };
      if (dbm >= t[0]) return 'Excellent';
      if (dbm >= t[1]) return 'Bon';
      if (dbm >= t[2]) return 'Moyen';
      return 'Faible';
    }

    final rows = <List<String>>[];
    if ((r.signalRsrp ?? 0) != 0) {
      rows.add([
        'Puissance du Signal',
        'RSRP ${r.signalRsrp} dBm '
            '(${qualityLabel(r.signalRsrp!, kind: 'rsrp')})',
        '',
      ]);
    }
    if ((r.signalNrRsrp ?? 0) != 0) {
      rows.add(['Puissance du Signal', 'NR RSRP ${r.signalNrRsrp} dBm', '']);
    }
    if ((r.wifiRssi ?? 0) != 0) {
      rows.add([
        'Puissance du Signal',
        'RSSI ${r.wifiRssi} dBm '
            '(${qualityLabel(r.wifiRssi!, kind: 'rssi')})',
        '',
      ]);
    }
    if ((r.signalRsrq ?? 0) != 0) {
      rows.add([
        'Qualité du Signal',
        'RSRQ ${r.signalRsrq} dB '
            '(${qualityLabel(r.signalRsrq!, kind: 'rsrq')})',
        '',
      ]);
    }
    if ((r.signalNrRsrq ?? 0) != 0) {
      rows.add(['Qualité du Signal', 'NR RSRQ ${r.signalNrRsrq} dB', '']);
    }
    if (rows.isEmpty && (r.signalDbm ?? 0) != 0) {
      rows.add(['Puissance du Signal', '${r.signalDbm} dBm', '']);
    }
    return rows;
  }

  // ── Rapport PDF (utilisé par exportPdf ET exportPng) ─────────────────────

  /// Octets des TTF embarqués (assets/fonts, cf. pubspec.yaml). La police
  /// par défaut du package pdf — Helvetica, non embarquée, encodage WinAnsi —
  /// ne couvre pas tous les caractères latins étendus (« œ », « … », tirets)
  /// et les visionneuses qui la substituent (dont le rasteriseur Android du
  /// PNG) affichaient des caractères cassés. Une vraie police TTF embarquée
  /// garantit le même rendu partout.
  Future<pw.Font?> _embeddedFont({bool bold = false}) async {
    try {
      final data = await rootBundle.load(
        bold
            ? 'assets/fonts/NotoSans-Bold.ttf'
            : 'assets/fonts/NotoSans-Regular.ttf',
      );
      return pw.Font.ttf(data.buffer.asByteData());
    } catch (_) {
      return null; // Repli sur Helvetica (rendu dégradé mais lisible).
    }
  }

  /// Styles cohérents du rapport : police embarquée partout (ou repli).
  pw.TextStyle _ts(
    pw.Font? regular,
    pw.Font? bold,
    double size,
    PdfColor color, {
    bool isBold = false,
  }) {
    final f = isBold ? (bold ?? regular) : regular;
    return pw.TextStyle(
      font: f,
      fontBold: f,
      fontSize: size,
      color: color,
      fontWeight: isBold && f != null
          ? pw.FontWeight.bold
          : pw.FontWeight.normal,
    );
  }

  Future<pw.Document> _buildPdf(SpeedTestResult r, {String? address}) async {
    final pdf = pw.Document();
    final logo = await _logo();
    final regular = await _embeddedFont();
    final bold = await _embeddedFont(bold: true) ?? regular;
    final quality = _qualityLabel(r.downloadSpeed);
    // Rapport compact : les six catégories doivent tenir sur UNE page A4
    // (re-test du 07/11 18:16 — un PNG sur deux pages est jugé flou une fois
    // mis à l'échelle du téléphone ; MultiPage reste le filet de sécurité).
    final double tileSize = 10.5;
    final double bodySize = 6.2;

    pdf.addPage(
      pw.MultiPage(
        // Fond blanc peint explicitement : sans lui, la rasterisation PNG
        // (PdfRenderer Android) produit une image à fond noir. Ce fond est
        // aussi présent dans le PDF, sans effet visible là-bas.
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(20),
          buildBackground: (context) =>
              pw.Container(color: PdfColor.fromInt(0xFFFFFFFF)),
        ),
        // Bandeau brandé en haut de CHAQUE page : le rapport passe sur
        // plusieurs pages depuis la revue du 07/11 (6 catégories) — revue
        // suivante : sans MultiPage, tout ce qui dépassait une page était
        // silencieusement coupé (Qualité perçue et Score Yélé absents).
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                if (logo != null) pw.Image(pw.MemoryImage(logo), width: 24),
                if (logo != null) pw.SizedBox(width: 6),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      _appName,
                      style: _ts(
                        regular,
                        bold,
                        15,
                        _hex(YeleColors.primary),
                        isBold: true,
                      ),
                    ),
                    pw.Text(
                      _appTagline,
                      style: _ts(regular, bold, 6, _hex(YeleColors.muted)),
                    ),
                  ],
                ),
                pw.Spacer(),
                if (context.pageNumber == 1)
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: pw.BoxDecoration(
                      color: _hex(YeleColors.panel),
                      borderRadius: const pw.BorderRadius.all(
                        pw.Radius.circular(4),
                      ),
                    ),
                    child: pw.Text(
                      _dateLong(r.timestamp),
                      style: _ts(regular, bold, 7.5, _hex(YeleColors.ink)),
                    ),
                  ),
              ],
            ),
            pw.SizedBox(height: 2),
            pw.Container(height: 2, color: _hex(YeleColors.primary)),
            pw.SizedBox(height: context.pageNumber == 1 ? 8 : 4),
          ],
        ),
        // Pied de page sur chaque page, avec pagination.
        footer: (context) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 4),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Divider(color: _hex(YeleColors.line)),
              pw.Text(
                'Généré par l\'application $_appName le ${_dateLong(DateTime.now())} — '
                'Serveur de test : ${serverHumanLabel(r.server)} — '
                'Page ${context.pageNumber} / ${context.pagesCount}',
                style: _ts(regular, bold, 5.5, _hex(YeleColors.muted)),
              ),
            ],
          ),
        ),
        build: (context) => [
          // ── Titre + badge qualité ──
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text(
                'Rapport de mesure',
                style: _ts(
                  regular,
                  bold,
                  15,
                  _hex(YeleColors.ink),
                  isBold: true,
                ),
              ),
              pw.SizedBox(width: 8),
              // Badge solide + texte blanc : contraste garanti quel que
              // soit le palier (revue 07/11 — le texte se fondait dans
              // une pastille teintée).
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: pw.BoxDecoration(
                  color: quality.color,
                  borderRadius: const pw.BorderRadius.all(
                    pw.Radius.circular(4),
                  ),
                ),
                child: pw.Text(
                  'Qualité : ${quality.label}',
                  style: _ts(
                    regular,
                    bold,
                    bodySize,
                    PdfColor.fromInt(0xFFFFFFFF),
                    isBold: true,
                  ),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 10),

          // ── Tuiles débits / latence ──
          pw.Row(
            children: [
              _tile(
                'Download',
                r.downloadSpeed.toStringAsFixed(2),
                'Mb/s',
                tileSize,
                regular,
                bold,
              ),
              pw.SizedBox(width: 10),
              _tile(
                'Upload',
                r.uploadSpeed.toStringAsFixed(2),
                'Mb/s',
                tileSize,
                regular,
                bold,
              ),
              pw.SizedBox(width: 10),
              _tile(
                'Latence',
                r.ping.toStringAsFixed(0),
                'ms',
                tileSize,
                regular,
                bold,
              ),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'Gigue : ${r.jitter.toStringAsFixed(0)} ms',
            style: _ts(regular, bold, bodySize, _hex(YeleColors.muted)),
          ),
          pw.SizedBox(height: 8),

          // ── Sections (catégories de l'app — source unique
          //    [measureSections], 07/11/2026) ──
          for (final section in measureSections(r, address: address)) ...[
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _pdfSection(
                  section.title,
                  section.rows,
                  bodySize,
                  regular,
                  bold,
                ),
                pw.SizedBox(height: 4),
              ],
            ),
          ],
        ],
      ),
    );
    return pdf;
  }

  /// Tuile « Label / Valeur / Unité » encadrée, style carte de résultat.
  pw.Widget _tile(
    String label,
    String value,
    String unit,
    double valueSize,
    pw.Font? regular,
    pw.Font? bold,
  ) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 6),
        decoration: pw.BoxDecoration(
          color: _hex(YeleColors.panel),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
          border: pw.Border.all(color: _hex(YeleColors.line)),
        ),
        child: pw.Column(
          children: [
            pw.Text(
              label,
              style: _ts(regular, bold, 6, _hex(YeleColors.muted)),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              value,
              style: _ts(
                regular,
                bold,
                valueSize,
                _hex(YeleColors.field),
                isBold: true,
              ),
            ),
            pw.SizedBox(height: 1),
            pw.Text(unit, style: _ts(regular, bold, 6, _hex(YeleColors.field))),
          ],
        ),
      ),
    );
  }

  pw.Widget _pdfSection(
    String title,
    List<List<String>> rows,
    double fontSize,
    pw.Font? regular,
    pw.Font? bold, {
    double labelWidth = 130,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: pw.BoxDecoration(
            color: _hex(YeleColors.primary),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
          ),
          child: pw.Text(
            title,
            style: _ts(
              regular,
              bold,
              fontSize,
              PdfColor.fromInt(0xFFFFFFFF),
              isBold: true,
            ),
          ),
        ),
        pw.SizedBox(height: 3),
        ...rows.map(
          (row) => pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 0.5),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.SizedBox(
                  width: labelWidth,
                  child: pw.Text(
                    '${row[0]} :',
                    style: _ts(regular, bold, fontSize, _hex(YeleColors.muted)),
                  ),
                ),
                pw.Expanded(
                  child: pw.Text(
                    row.length > 1 ? row[1] : '',
                    style: _ts(
                      regular,
                      bold,
                      fontSize,
                      _hex(YeleColors.ink),
                      isBold: true,
                    ),
                  ),
                ),
                if (row.length > 2)
                  pw.Text(
                    row[2],
                    style: _ts(regular, bold, fontSize, _hex(YeleColors.muted)),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Mêmes seuils que l'écran de résultat (score_screen.dart) : cohérence
  /// entre ce que voit l'utilisateur et ce qui est exporté.
  ({String label, PdfColor color}) _qualityLabel(double dl) {
    if (dl >= 50) return (label: 'Excellent', color: _hex(YeleColors.good));
    if (dl >= 20) return (label: 'Très bon', color: _hex(YeleColors.testBot));
    if (dl >= 10) return (label: 'Bon', color: _hex(YeleColors.warn));
    if (dl >= 4) return (label: 'Moyen', color: _hex(YeleColors.g4));
    return (label: 'Faible', color: _hex(YeleColors.danger));
  }

  String _dateLong(DateTime t) {
    const months = [
      'janvier',
      'février',
      'mars',
      'avril',
      'mai',
      'juin',
      'juillet',
      'août',
      'septembre',
      'octobre',
      'novembre',
      'décembre',
    ];
    return '${t.day} ${months[t.month - 1]} ${t.year} à '
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  String _stamp(SpeedTestResult r) {
    final t = r.timestamp;
    return '${t.year}'
        '${t.month.toString().padLeft(2, '0')}'
        '${t.day.toString().padLeft(2, '0')}'
        '_${t.hour.toString().padLeft(2, '0')}'
        '${t.minute.toString().padLeft(2, '0')}';
  }

  PdfColor _hex(Color c) => PdfColor.fromInt(c.toARGB32());

  // ── CSV ──────────────────────────────────────────────────────────────────

  /// Table de transcodage FR minimal : le CSV est livré sans accents car
  /// certains lecteurs que l'utilisateur cible (Android, tableurs, carnet)
  /// affichent mal l'UTF-8 — la revue du 07/11 a validé ce compromis
  /// (l'Excel, le PDF et le PNG conservent les accents).
  static const _asciiMap = {
    'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a', 'ã': 'a',
    'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
    'î': 'i', 'ï': 'i', 'í': 'i',
    'ô': 'o', 'ö': 'o', 'ó': 'o', 'õ': 'o',
    'ù': 'u', 'û': 'u', 'ü': 'u', 'ú': 'u',
    'ç': 'c', 'ÿ': 'y', 'ñ': 'n',
    'À': 'A', 'Â': 'A', 'Ä': 'A',
    'É': 'E', 'È': 'E', 'Ê': 'E', 'Ë': 'E',
    'Î': 'I', 'Ï': 'I',
    'Ô': 'O', 'Ö': 'O',
    'Ù': 'U', 'Û': 'U', 'Ü': 'U',
    'Ç': 'C', 'Œ': 'OE', 'œ': 'oe', 'Ñ': 'N',
    // Symboles typographiques qui posent le même problème d'affichage.
    '°': 'deg', '·': '-', '—': '-', '–': '-', '…': '...', '’': "'",
    '\u00a0': ' ',
  };

  /// Plier un texte vers l'ASCII 7 bits (CSV uniquement). Tout caractère
  /// non couvert non-ASCII est retiré plutôt que corrompu.
  @visibleForTesting
  static String asciiFold(String s) {
    final buf = StringBuffer();
    for (final ch in s.runes) {
      final c = String.fromCharCode(ch);
      if (_asciiMap.containsKey(c)) {
        buf.write(_asciiMap[c]);
      } else if (ch < 128) {
        buf.write(c);
      }
      // Sinon : caractère non géré → retiré (jamais de mojibake).
    }
    return buf.toString();
  }

  /// CSV d'une seule mesure : BOM UTF-8, séparateur « ; » (Excel FR),
  /// échappement RFC 4180, une ligne de titre « # Catégorie » par section,
  /// puis les lignes Champ;Valeur;Unité de cette catégorie. Texte plié
  /// ASCII (sans accents, cf. [asciiFold]).
  String _csv(SpeedTestResult r, {String? address}) {
    final buf = StringBuffer()
      ..writeln('${asciiFold(_appName)};${asciiFold(_appTagline)}');
    for (final section in measureSections(r, address: address)) {
      buf.writeln(_csvLine(['## ${asciiFold(section.title)}']));
      for (final row in section.rows) {
        buf.writeln(
          _csvLine([
            asciiFold(row[0]),
            asciiFold(row.length > 1 ? row[1] : ''),
            asciiFold(row.length > 2 ? row[2] : ''),
          ]),
        );
      }
    }
    return buf.toString();
  }

  String _csvLine(List<String> fields) => fields
      .map(
        (f) => (f.contains(';') || f.contains('"') || f.contains('\n'))
            ? '"${f.replaceAll('"', '""')}"'
            : f,
      )
      .join(';');

  // ── Fichiers & partage ───────────────────────────────────────────────────

  Future<Uint8List?> _logo() async {
    try {
      final data = await rootBundle.load('assets/logo/yele_logo.png');
      return data.buffer.asUint8List();
    } catch (_) {
      return null; // Le rapport reste lisible sans logo.
    }
  }

  Future<void> _shareFile(
    Uint8List bytes,
    String fileName,
    String mimeType,
    String subject,
  ) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: mimeType)],
        subject: subject,
        text: '$_appName — $subject',
      ),
    );
  }

  /// Aplatit un PNG (potentiellement transparent) sur fond blanc et recadre
  /// les marges transparentes. Retourne l'image d'origine en cas d'échec du
  /// décodage (jamais de blocage du partage pour un souci cosmétique).
  Future<Uint8List> _flattenPngOnWhite(Uint8List pngBytes) async {
    try {
      final decoded = img.decodePng(pngBytes);
      if (decoded == null) return pngBytes;
      final flattened = img.Image(
        width: decoded.width,
        height: decoded.height,
        numChannels: 3,
      );
      // Composition alpha du contenu par-dessus un fond blanc opaque :
      // tout pixel transparent reste blanc (fixe le cadrage noir).
      flattened.clear(img.ColorRgb8(255, 255, 255));
      for (var y = 0; y < decoded.height; y++) {
        for (var x = 0; x < decoded.width; x++) {
          final px = decoded.getPixel(x, y);
          final a = px.a / 255.0;
          if (a >= 1.0) {
            flattened.setPixelRgb(x, y, px.r, px.g, px.b);
          } else if (a > 0.0) {
            flattened.setPixelRgb(
              x,
              y,
              (px.r * a + 255 * (1 - a)).round(),
              (px.g * a + 255 * (1 - a)).round(),
              (px.b * a + 255 * (1 - a)).round(),
            );
          }
          // a == 0 : reste blanc (fixe le cadrage noir).
        }
      }
      return Uint8List.fromList(img.encodePng(flattened));
    } catch (_) {
      return pngBytes;
    }
  }

  /// Recolle verticalement des PNG de pages rasterisées (rapport qui
  /// dépasse une page : le résumé reste lisible d'un seul tenant).
  Uint8List _stackPngs(List<Uint8List> pngs) {
    try {
      final decoded = pngs
          .map((b) => img.decodePng(b))
          .whereType<img.Image>()
          .toList();
      if (decoded.isEmpty) return pngs.first;
      final width = decoded.map((d) => d.width).reduce((a, b) => a > b ? a : b);
      final totalHeight = decoded.fold<int>(0, (sum, d) => sum + d.height);
      final stacked = img.Image(
        width: width,
        height: totalHeight,
        numChannels: 3,
      );
      stacked.clear(img.ColorRgb8(255, 255, 255));
      var y = 0;
      for (final page in decoded) {
        // Composite optimisé (flatten au préalable → fond opaque) : la boucle
        // pixel à pixel est bien trop lente en mode debug sur deux pages A4.
        img.compositeImage(
          stacked,
          page,
          dstX: (width - page.width) ~/ 2,
          dstY: y,
        );
        y += page.height;
      }
      return Uint8List.fromList(img.encodePng(stacked));
    } catch (_) {
      // Dépassement impossible à recoller : on livre la 1ʳᵉ page.
      return pngs.first;
    }
  }
}
