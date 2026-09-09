import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:image/image.dart' as img;
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

  /// Bytes du rapport (réservé aux tests de rendu).
  Future<Uint8List> buildPdfBytesForTest(SpeedTestResult r) async =>
      (await _buildPdf(r, a4: false)).save();

  /// Résumé en image : on réutilise le rapport vectoriel (PDF) rasterisé en
  /// PNG par `printing` — un seul rendu à maintenir pour les deux formats.
  /// La rasterisation passe par la plateforme : indisponible sur le web.
  ///
  /// Deux corrections de rendu :
  /// 1. le rasteriseur Android (PdfRenderer) produit une image à canal alpha :
  ///    tout pixel non peint est transparent et s'affiche NOIR dans la plupart
  ///    des visionneuses (cadrage noir signalé). On recompose le PNG sur fond
  ///    blanc avec le package `image` ;
  /// 2. on recadre l'image sur le contenu utile pour supprimer les marges
  ///    transparentes résiduelles autour de la page.
  Future<void> exportPng(SpeedTestResult r) async {
    final doc = await _buildPdf(r, a4: false);
    final pages = await Printing.raster(await doc.save(), dpi: 144).toList();
    if (pages.isEmpty) {
      throw Exception('Rasterisation impossible sur cette plateforme');
    }
    final rawPng = await pages.first.toPng();
    final png = await _flattenPngOnWhite(rawPng);
    await _shareFile(
      png,
      'Yele_mesure_${_stamp(r)}.png',
      'image/png',
      'Mesure Yélé (PNG)',
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
          width: decoded.width, height: decoded.height, numChannels: 3);
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

  // ── Rapport PDF (utilisé par exportPdf ET exportPng) ─────────────────────

  /// Octets des TTF embarqués (assets/fonts, cf. pubspec.yaml). La police
  /// par défaut du package pdf — Helvetica, non embarquée, encodage WinAnsi —
  /// ne couvre pas tous les caractères latins étendus (« œ », « … », tirets)
  /// et les visionneuses qui la substituent (dont le rasteriseur Android du
  /// PNG) affichaient des caractères cassés. Une vraie police TTF embarquée
  /// garantit le même rendu partout.
  Future<pw.Font?> _embeddedFont({bool bold = false}) async {
    try {
      final data = await rootBundle.load(bold
          ? 'assets/fonts/NotoSans-Bold.ttf'
          : 'assets/fonts/NotoSans-Regular.ttf');
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
      fontWeight: isBold && f != null ? pw.FontWeight.bold : pw.FontWeight.normal,
    );
  }

  Future<pw.Document> _buildPdf(SpeedTestResult r, {required bool a4}) async {
    final pdf = pw.Document();
    final logo = await _logo();
    final regular = await _embeddedFont();
    final bold = await _embeddedFont(bold: true) ?? regular;
    final quality = _qualityLabel(r.downloadSpeed);
    final pageFormat =
        a4 ? PdfPageFormat.a4 : const PdfPageFormat(480, 600);
    final double titleSize = a4 ? 18 : 15;
    final double tileValue = a4 ? 17 : 14;
    final double bodySize = a4 ? 9.5 : 8;

    pdf.addPage(
      pw.Page(
        // Fond blanc peint explicitement : sans lui, la rasterisation PNG
        // (PdfRenderer Android) produit une image à fond noir. Ce fond est
        // aussi présent dans le PDF A4, sans effet visible là-bas.
        pageTheme: pw.PageTheme(
          pageFormat: pageFormat,
          margin: pw.EdgeInsets.all(a4 ? 40 : 18),
          buildBackground: (context) =>
              pw.Container(color: PdfColor.fromInt(0xFFFFFFFF)),
        ),
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
                        style: _ts(regular, bold, a4 ? 22 : 16,
                            _hex(YeleColors.primary),
                            isBold: true)),
                    pw.Text(_appTagline,
                        style: _ts(
                            regular, bold, a4 ? 8.5 : 6.5, _hex(YeleColors.muted))),
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
                        style: _ts(regular, bold, 9, _hex(YeleColors.ink))),
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
                    style: _ts(regular, bold, titleSize, _hex(YeleColors.ink),
                        isBold: true)),
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
                      style: _ts(regular, bold, bodySize, quality.color,
                          isBold: true)),
                ),
              ],
            ),
            pw.SizedBox(height: a4 ? 14 : 8),

            // ── Tuiles débits / latence ──
            pw.Row(
              children: [
                _tile('Download', r.downloadSpeed.toStringAsFixed(2), 'Mb/s',
                    tileValue, regular, bold),
                pw.SizedBox(width: a4 ? 10 : 6),
                _tile('Upload', r.uploadSpeed.toStringAsFixed(2), 'Mb/s',
                    tileValue, regular, bold),
                pw.SizedBox(width: a4 ? 10 : 6),
                _tile('Latence', r.ping.toStringAsFixed(0), 'ms', tileValue,
                    regular, bold),
              ],
            ),
            pw.SizedBox(height: 4),
            pw.Text('Gigue : ${r.jitter.toStringAsFixed(0)} ms',
                style: _ts(
                    regular, bold, bodySize, _hex(YeleColors.muted))),
            pw.SizedBox(height: a4 ? 14 : 8),

            // ── Sections ──
            _pdfSection('Détails de la mesure', _rows(r), bodySize, regular,
                bold, labelWidth: a4 ? 150 : 130),
            if (r.hasStreamingTest) ...[
              pw.SizedBox(height: a4 ? 12 : 8),
              _pdfSection('Test de streaming vidéo', _streamingRows(r),
                  bodySize, regular, bold,
                  labelWidth: a4 ? 150 : 130),
            ],
            if (r.hasBrowsingTest) ...[
              pw.SizedBox(height: a4 ? 12 : 8),
              _pdfSection('Test de navigation web', _browsingRows(r), bodySize,
                  regular, bold, labelWidth: a4 ? 150 : 130),
            ],
            if (a4) ...[
              pw.Spacer(),
              pw.Divider(color: _hex(YeleColors.line)),
              pw.Text(
                'Généré par l\'application $_appName le ${_dateLong(DateTime.now())} — Serveur de test : ${r.server}.',
                style: _ts(regular, bold, 7.5, _hex(YeleColors.muted)),
              ),
            ],
          ],
        ),
      ),
    );
    return pdf;
  }

  /// Tuile « Label / Valeur / Unité » encadrée, style carte de résultat.
  pw.Widget _tile(String label, String value, String unit, double valueSize,
      pw.Font? regular, pw.Font? bold) {
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
                style: _ts(regular, bold, 8, _hex(YeleColors.muted))),
            pw.SizedBox(height: 3),
            pw.Text(value,
                style: _ts(regular, bold, valueSize, _hex(YeleColors.field),
                    isBold: true)),
            pw.Text(unit,
                style: _ts(regular, bold, 8, _hex(YeleColors.field))),
          ],
        ),
      ),
    );
  }

  pw.Widget _pdfSection(String title, List<List<String>> rows, double fontSize,
      pw.Font? regular, pw.Font? bold,
      {double labelWidth = 150}) {
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
              style: _ts(regular, bold, fontSize,
                  PdfColor.fromInt(0xFFFFFFFF),
                  isBold: true)),
        ),
        pw.SizedBox(height: 4),
        ...rows.map((row) => pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.SizedBox(
                    width: labelWidth,
                    child: pw.Text('${row[0]} :',
                        style: _ts(
                            regular, bold, fontSize, _hex(YeleColors.muted))),
                  ),
                  pw.Expanded(
                    child: pw.Text(
                      row.length > 1 ? row[1] : '',
                      style: _ts(regular, bold, fontSize,
                          _hex(YeleColors.ink),
                          isBold: true),
                    ),
                  ),
                  if (row.length > 2 && row[2].isNotEmpty)
                    pw.SizedBox(
                      width: 30,
                      child: pw.Text(row[2],
                          style: _ts(
                              regular, bold, fontSize, _hex(YeleColors.muted))),
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
      // IMP-01 : données consommées par le test (masqué si non mesuré).
      if ((r.dataUsedKiB ?? -1) >= 0)
        [
          'Données consommées',
          r.dataUsedKiB! >= 1024
              ? (r.dataUsedKiB! / 1024).toStringAsFixed(1)
              : r.dataUsedKiB!.toString(),
          r.dataUsedKiB! >= 1024 ? 'Mo' : 'Ko',
        ],
      if (r.qoeRating != null && r.qoeRating! > 0)
        ['Évaluation QoE', '${r.qoeRating}/5', ''],
      if ((r.qoeUsage ?? '').isNotEmpty) ['Usage principal', r.qoeUsage!, ''],
      if ((r.qoeSatisfaction ?? '').isNotEmpty)
        ['Commentaire', r.qoeSatisfaction!, ''],
      if ((r.deviceModel ?? '').isNotEmpty) ['Appareil', r.deviceModel!, ''],
      if ((r.osVersion ?? '').isNotEmpty) ['Version OS', r.osVersion!, ''],
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
