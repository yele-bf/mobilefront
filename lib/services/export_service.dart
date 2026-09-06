import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter/material.dart' show Color;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart' show PdfColor, PdfPageFormat;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../models/speed_test_result.dart';
import '../theme/yele_theme.dart';

/// IMP-13 — Export d'une mesure, façon nPerf : depuis l'écran de résultat
/// ou l'historique, l'utilisateur partage la mesure choisie au format
/// CSV, Excel (xlsx), PDF (rapport brandé) ou PNG (résumé en image).
///
/// Le fichier est écrit dans le répertoire temporaire de l'app puis remis
/// à la feuille de partage Android (Fichiers, WhatsApp, e-mail, Drive…).
/// L'app ne demande aucune permission : ni stockage (répertoire privé +
/// share sheet), ni localisation (les coordonnées viennent de la mesure).
class ExportService {
  static const _appName = 'Yélé';
  static const _appTagline = 'Mesure de la qualité des réseaux mobiles';

  // ── API publique ─────────────────────────────────────────────────────────

  Future<void> exportCsv(SpeedTestResult r) async {
    final bytes = Uint8List.fromList(utf8.encode(_csv(r)));
    await _shareFile(
      bytes,
      'Yele_mesure_${_stamp(r)}.csv',
      'text/csv',
      'Mesure Yélé (CSV)',
    );
  }

  Future<void> exportExcel(SpeedTestResult r) async {
    final excel = Excel.createExcel();
    final sheet = excel['Mesure'];

    // Bandeau Yélé (fusionné) puis en-têtes : l'utilisateur ouvre un vrai
    // classeur, lisible dans Excel comme dans LibreOffice.
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
      CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 0),
    );
    final brand = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0));
    brand.value = TextCellValue('$_appName — $_appTagline');
    brand.cellStyle = CellStyle(
      bold: true,
      backgroundColorHex:
          ExcelColor.fromHexString('FF0BB89C'), // YeleColors.primary
      fontColorHex: ExcelColor.white,
    );

    const headers = ['Champ', 'Valeur', 'Unité'];
    for (var i = 0; i < headers.length; i++) {
      final c = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 1));
      c.value = TextCellValue(headers[i]);
      c.cellStyle = CellStyle(
        bold: true,
        backgroundColorHex: ExcelColor.fromHexString('FFE7EBEF'),
      );
    }

    final rows = _rows(r);
    for (var i = 0; i < rows.length; i++) {
      for (var j = 0; j < rows[i].length; j++) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: j, rowIndex: i + 2))
            .value = TextCellValue(rows[i][j]);
      }
    }
    sheet.setColumnWidth(0, 34);
    sheet.setColumnWidth(1, 42);
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
    final doc = await _buildPdf(r, a4: true);
    await _shareFile(
      await doc.save(),
      'Yele_mesure_${_stamp(r)}.pdf',
      'application/pdf',
      'Mesure Yélé (PDF)',
    );
  }

  /// Résumé en image : on réutilise le rapport vectoriel (PDF) rasterisé en
  /// PNG par `printing` — un seul rendu à maintenir pour les deux formats.
  /// La rasterisation passe par la plateforme : indisponible sur le web.
  Future<void> exportPng(SpeedTestResult r) async {
    final doc = await _buildPdf(r, a4: false);
    final pages = await Printing.raster(await doc.save(), dpi: 144).toList();
    if (pages.isEmpty) {
      throw Exception('Rasterisation impossible sur cette plateforme');
    }
    final png = await pages.first.toPng();
    await _shareFile(
      png,
      'Yele_mesure_${_stamp(r)}.png',
      'image/png',
      'Mesure Yélé (PNG)',
    );
  }

  // ── Rapport PDF (utilisé par exportPdf ET exportPng) ─────────────────────

  Future<pw.Document> _buildPdf(SpeedTestResult r, {required bool a4}) async {
    final pdf = pw.Document();
    final logo = await _logo();
    final quality = _qualityLabel(r.downloadSpeed);
    final pageFormat =
        a4 ? PdfPageFormat.a4 : const PdfPageFormat(420, 520);
    final double titleSize = a4 ? 18 : 15;
    final double tileValue = a4 ? 17 : 14;
    final double bodySize = a4 ? 9.5 : 8;

    pdf.addPage(
      pw.Page(
        pageFormat: pageFormat,
        margin: pw.EdgeInsets.all(a4 ? 40 : 18),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // ── En-tête brandé ──
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                if (logo != null) pw.Image(pw.MemoryImage(logo), width: a4 ? 40 : 26),
                if (logo != null) pw.SizedBox(width: 10),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(_appName,
                        style: pw.TextStyle(
                            fontSize: a4 ? 22 : 16,
                            fontWeight: pw.FontWeight.bold,
                            color: _hex(YeleColors.primary))),
                    pw.Text(_appTagline,
                        style: pw.TextStyle(
                            fontSize: a4 ? 8.5 : 6.5,
                            color: _hex(YeleColors.muted))),
                  ],
                ),
                pw.Spacer(),
                if (a4)
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: pw.BoxDecoration(
                      color: _hex(YeleColors.panel),
                      borderRadius:
                          const pw.BorderRadius.all(pw.Radius.circular(6)),
                    ),
                    child: pw.Text(_dateLong(r.timestamp),
                        style: pw.TextStyle(
                            fontSize: 9, color: _hex(YeleColors.ink))),
                  ),
              ],
            ),
            pw.SizedBox(height: 6),
            pw.Container(height: a4 ? 3 : 2, color: _hex(YeleColors.primary)),
            pw.SizedBox(height: a4 ? 16 : 10),

            // ── Titre + badge qualité ──
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Text('Rapport de mesure',
                    style: pw.TextStyle(
                        fontSize: titleSize,
                        fontWeight: pw.FontWeight.bold,
                        color: _hex(YeleColors.ink))),
                pw.SizedBox(width: 10),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: pw.BoxDecoration(
                    // 15 % d'opacité : PdfColor n'a pas de withValues,
                    // on compose à la main sur les 8 bits alpha.
                    color: _alpha(quality.color, 0.15),
                    borderRadius:
                        const pw.BorderRadius.all(pw.Radius.circular(4)),
                  ),
                  child: pw.Text('Qualité : ${quality.label}',
                      style: pw.TextStyle(
                          fontSize: bodySize,
                          fontWeight: pw.FontWeight.bold,
                          color: quality.color)),
                ),
              ],
            ),
            pw.SizedBox(height: a4 ? 14 : 8),

            // ── Tuiles débits / latence ──
            pw.Row(
              children: [
                _tile('Download', r.downloadSpeed.toStringAsFixed(2), 'Mb/s',
                    tileValue),
                pw.SizedBox(width: a4 ? 10 : 6),
                _tile('Upload', r.uploadSpeed.toStringAsFixed(2), 'Mb/s',
                    tileValue),
                pw.SizedBox(width: a4 ? 10 : 6),
                _tile('Latence', r.ping.toStringAsFixed(0), 'ms', tileValue),
              ],
            ),
            pw.SizedBox(height: 4),
            pw.Text('Gigue : ${r.jitter.toStringAsFixed(0)} ms',
                style: pw.TextStyle(
                    fontSize: bodySize, color: _hex(YeleColors.muted))),
            pw.SizedBox(height: a4 ? 14 : 8),

            // ── Sections ──
            _pdfSection('Détails de la mesure', _rows(r), bodySize),
            if (r.hasStreamingTest) ...[
              pw.SizedBox(height: a4 ? 12 : 8),
              _pdfSection('Test de streaming vidéo', _streamingRows(r), bodySize),
            ],
            if (r.hasBrowsingTest) ...[
              pw.SizedBox(height: a4 ? 12 : 8),
              _pdfSection('Test de navigation web', _browsingRows(r), bodySize),
            ],
            if (a4) ...[
              pw.Spacer(),
              pw.Divider(color: _hex(YeleColors.line)),
              pw.Text(
                'Généré par l\'application $_appName le ${_dateLong(DateTime.now())} — Serveur de test : ${r.server}.',
                style: pw.TextStyle(
                    fontSize: 7.5, color: _hex(YeleColors.muted)),
              ),
            ],
          ],
        ),
      ),
    );
    return pdf;
  }

  /// Tuile « Label / Valeur / Unité » encadrée, style carte de résultat.
  pw.Widget _tile(String label, String value, String unit, double valueSize) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: pw.BoxDecoration(
          color: _hex(YeleColors.panel),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
          border: pw.Border.all(color: _hex(YeleColors.line)),
        ),
        child: pw.Column(
          children: [
            pw.Text(label,
                style: pw.TextStyle(
                    fontSize: 8, color: _hex(YeleColors.muted))),
            pw.SizedBox(height: 3),
            pw.Text(value,
                style: pw.TextStyle(
                    fontSize: valueSize,
                    fontWeight: pw.FontWeight.bold,
                    color: _hex(YeleColors.field))),
            pw.Text(unit,
                style: pw.TextStyle(
                    fontSize: 8, color: _hex(YeleColors.field))),
          ],
        ),
      ),
    );
  }

  pw.Widget _pdfSection(String title, List<List<String>> rows, double fontSize) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          padding:
              const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: pw.BoxDecoration(
            color: _hex(YeleColors.primary),
            borderRadius:
                const pw.BorderRadius.all(pw.Radius.circular(4)),
          ),
          child: pw.Text(title,
              style: pw.TextStyle(
                  fontSize: fontSize,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColor.fromInt(0xFFFFFFFF))),
        ),
        pw.SizedBox(height: 4),
        ...rows.map((row) => pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.SizedBox(
                    width: 150,
                    child: pw.Text('${row[0]} :',
                        style: pw.TextStyle(
                            fontSize: fontSize,
                            color: _hex(YeleColors.muted))),
                  ),
                  pw.Expanded(
                    child: pw.Text(
                      row.length > 1 ? row[1] : '',
                      style: pw.TextStyle(
                          fontSize: fontSize,
                          fontWeight: pw.FontWeight.bold,
                          color: _hex(YeleColors.ink)),
                    ),
                  ),
                  if (row.length > 2 && row[2].isNotEmpty)
                    pw.SizedBox(
                      width: 30,
                      child: pw.Text(row[2],
                          style: pw.TextStyle(
                              fontSize: fontSize,
                              color: _hex(YeleColors.muted))),
                    ),
                ],
              ),
            )),
      ],
    );
  }

  // ── Données de la mesure ─────────────────────────────────────────────────

  /// Lignes « Champ / Valeur / Unité » communes aux quatre formats
  /// (une seule source de vérité : CSV, Excel, PDF et PNG restent cohérents).
  List<List<String>> _rows(SpeedTestResult r) {
    final t = r.timestamp;
    final ymd =
        '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')}/${t.year} '
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';

    return [
      ['Date du test', ymd, ''],
      ['Type de connexion', r.networkType ?? '—', ''],
      ['Réseau mobile', _mobileLabel(r), ''],
      ['FAI / Opérateur', r.operator ?? '—', ''],
      ['Serveur', r.server, ''],
      ['Localisation', r.location ?? '—', ''],
      if ((r.latitude ?? 0) != 0) ...[
        ['Latitude', r.latitude!.toStringAsFixed(6), '°'],
        ['Longitude', r.longitude!.toStringAsFixed(6), '°'],
      ],
      ['Download', r.downloadSpeed.toStringAsFixed(2), 'Mb/s'],
      ['Upload', r.uploadSpeed.toStringAsFixed(2), 'Mb/s'],
      ['Latence (ping)', r.ping.toStringAsFixed(0), 'ms'],
      ['Gigue (jitter)', r.jitter.toStringAsFixed(0), 'ms'],
      if (r.qoeRating != null && r.qoeRating! > 0)
        ['Évaluation QoE', '${r.qoeRating}/5', ''],
      if ((r.qoeUsage ?? '').isNotEmpty) ['Usage principal', r.qoeUsage!, ''],
      if ((r.qoeSatisfaction ?? '').isNotEmpty)
        ['Commentaire', r.qoeSatisfaction!, ''],
      ['Appareil', r.deviceModel ?? '—', ''],
      ['Version OS', r.osVersion ?? '—', ''],
    ];
  }

  List<List<String>> _streamingRows(SpeedTestResult r) {
    final rows = <List<String>>[
      ['Score streaming', (r.streamingScore ?? 0).toStringAsFixed(0), '/100'],
      ['Résolution max soutenue', r.streamingMaxResolution ?? '—', ''],
      ['Démarrage vidéo', '${r.streamingStartupMs ?? 0}', 'ms'],
      ['Interruptions (rebuffering)', '${r.streamingRebufferCount ?? 0}', ''],
      [
        'Part du temps en tampon',
        ((r.streamingRebufferRatio ?? 0) * 100).toStringAsFixed(1),
        '%'
      ],
    ];
    // Détail par qualité testée (720p/1080p/2160p), aligné sur le tableau
    // de l'écran de résultat : taux de performance et chargement initial.
    for (final q in r.streamingQualities) {
      rows.add([
        'Streaming ${q.label}',
        q.reached
            ? '${q.performanceRate.toStringAsFixed(0)} % · ${q.initialLoadingSec.toStringAsFixed(1)} s'
            : '—',
        ''
      ]);
    }
    return rows;
  }

  List<List<String>> _browsingRows(SpeedTestResult r) {
    return [
      ['Score navigation', (r.browsingScore ?? 0).toStringAsFixed(0), '/100'],
      [
        'Temps de chargement moyen',
        ((r.browsingAvgLoadMs ?? 0) / 1000).toStringAsFixed(1),
        's'
      ],
      [
        'Taux de réussite',
        '${((r.browsingSuccessRate ?? 0) * 100).toStringAsFixed(0)} %',
        ''
      ],
      ['Pages testées', (r.browsingPagesTested ?? 0).toString(), ''],
    ];
  }

  String _mobileLabel(SpeedTestResult r) {
    final parts = [r.cellularTech, r.simOperator]
        .where((e) => (e ?? '').isNotEmpty)
        .join(' · ');
    return parts.isEmpty ? '—' : parts;
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
      'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
      'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre',
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

  /// Même teinte avec une opacité donnée (0–1), car PdfColor n'expose pas
  /// de méthode `withValues` comme Flutter.
  PdfColor _alpha(PdfColor c, double opacity) => PdfColor(
        c.red,
        c.green,
        c.blue,
        c.alpha * opacity,
      );

  // ── CSV ──────────────────────────────────────────────────────────────────

  /// CSV d'une seule mesure (en-tête + 1 bloc clé/valeur), séparateur « ; »
  /// (Excel FR), échappement RFC 4180 et BOM UTF-8 pour les accents.
  String _csv(SpeedTestResult r) {
    final rows = [
      const ['Champ', 'Valeur', 'Unité'],
      ..._rows(r),
      if (r.hasStreamingTest) ..._streamingRows(r),
      if (r.hasBrowsingTest) ..._browsingRows(r),
    ];
    final buf = StringBuffer()
      ..writeln('\uFEFF${_appName.replaceAll(';', ',')};${_appTagline.replaceAll(';', ',')}');
    for (final row in rows) {
      buf.writeln(_csvLine(row));
    }
    return buf.toString();
  }

  String _csvLine(List<String> fields) => fields
      .map((f) => (f.contains(';') || f.contains('"') || f.contains('\n'))
          ? '"${f.replaceAll('"', '""')}"'
          : f)
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
}
