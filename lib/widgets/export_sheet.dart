import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../models/speed_test_result.dart';
import '../services/export_service.dart';
import '../theme/yele_theme.dart';

/// IMP-13 — Feuille de choix du format d'export d'une mesure, façon nPerf.
/// Appelée depuis l'écran de résultat (fin de test) et l'historique.
///
/// Sur le web, l'export PNG est masqué : la rasterisation PDF → PNG passe
/// par la plateforme (printing) et n'y est pas disponible ; les trois autres
/// formats restent téléchargeables via le navigateur.
Future<void> showExportSheet(BuildContext context, SpeedTestResult result) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => _ExportSheet(result: result),
  );
}

class _ExportSheet extends StatefulWidget {
  final SpeedTestResult result;

  const _ExportSheet({required this.result});

  @override
  State<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<_ExportSheet> {
  final _export = ExportService();
  String? _busy; // Format en cours d'export (désactive les autres options).

  Future<void> _run(String label, Future<void> Function() action) async {
    setState(() => _busy = label);
    try {
      await action();
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$label exporté — choisissez où l\'enregistrer')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Échec de l\'export $label : $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 18, 0, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Exporter la mesure',
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: YeleColors.ink)),
                  SizedBox(height: 4),
                  Text(
                      'Le fichier est préparé puis partagé via Android '
                      '(Fichiers, e-mail, WhatsApp…)',
                      style: TextStyle(fontSize: 12, color: YeleColors.muted)),
                ],
              ),
            ),
            const SizedBox(height: 10),
            if (!kIsWeb)
              _option(
                icon: Icons.image_outlined,
                color: YeleColors.g4,
                title: 'PNG — image du résultat',
                subtitle: 'Résumé visuel, idéal pour partager',
                label: 'PNG',
                onTap: () => _run('PNG', () => _export.exportPng(widget.result)),
              ),
            _option(
              icon: Icons.picture_as_pdf_outlined,
              color: YeleColors.danger,
              title: 'PDF — rapport complet',
              subtitle: 'Rapport brandé Yélé, une page',
              label: 'PDF',
              onTap: () => _run('PDF', () => _export.exportPdf(widget.result)),
            ),
            _option(
              icon: Icons.table_chart_outlined,
              color: YeleColors.good,
              title: 'Excel — classeur (.xlsx)',
              subtitle: 'Toutes les valeurs, prêtes à analyser',
              label: 'Excel',
              onTap: () =>
                  _run('Excel', () => _export.exportExcel(widget.result)),
            ),
            _option(
              icon: Icons.description_outlined,
              color: YeleColors.field,
              title: 'CSV — données brutes',
              subtitle: 'Champ ; Valeur ; Unité (ouvrable dans Excel)',
              label: 'CSV',
              onTap: () => _run('CSV', () => _export.exportCsv(widget.result)),
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  Widget _option({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required String label,
    required VoidCallback onTap,
  }) {
    final busy = _busy == label;
    final disabled = _busy != null && !busy;
    return Opacity(
      opacity: disabled ? 0.45 : 1,
      child: ListTile(
        leading: CircleAvatar(
          radius: 20,
          backgroundColor: color.withValues(alpha: 0.12),
          child: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(icon, color: color, size: 22),
        ),
        title: Text(title,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: YeleColors.ink)),
        subtitle: Text(subtitle,
            style: const TextStyle(fontSize: 12, color: YeleColors.muted)),
        onTap: disabled ? null : onTap,
      ),
    );
  }
}
