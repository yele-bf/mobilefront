import 'package:flutter/material.dart';

import '../services/streaming_test_service.dart';
import '../theme/yele_theme.dart';

/// Tableau des mesures de streaming, une colonne par palier testé.
///
/// Quatre lignes : taux de performance, chargement initial, temps de mise en
/// tampon, données consommées. L'en-tête de chaque colonne affiche la qualité
/// que YouTube a RÉELLEMENT servie (souvent différente de la qualité demandée) ;
/// un palier sans mesure garde sa colonne, avec « — » sur toute la hauteur.
class StreamingTable extends StatelessWidget {
  final List<StreamingQualityResult> qualities;

  /// Qualité en cours de mesure, surlignée pendant le test. null hors test.
  final String? activeLabel;

  const StreamingTable({
    super.key,
    required this.qualities,
    this.activeLabel,
  });

  static const _dash = '—';

  String _performance(StreamingQualityResult q) =>
      q.reached ? '${q.performanceRate.toStringAsFixed(2)} %' : _dash;

  String _loading(StreamingQualityResult q) =>
      q.reached ? '${q.initialLoadingSec.toStringAsFixed(3)} s' : _dash;

  String _buffering(StreamingQualityResult q) {
    if (!q.reached) return _dash;
    // Pas d'interruption : nPerf laisse la case vide plutôt que d'écrire 0.
    if (q.bufferingSec <= 0) return _dash;
    return '${q.bufferingSec.toStringAsFixed(3)} s';
  }

  String _data(StreamingQualityResult q) {
    if (!q.reached || q.dataUsedKiB < 0) return _dash;
    return '${q.dataUsedKiB} kiB';
  }

  @override
  Widget build(BuildContext context) {
    if (qualities.isEmpty) return const SizedBox.shrink();

    // L'en-tête affiche la qualité servie : sans cette légende, un libellé
    // différent de la qualité demandée (1440p pour un palier 2160p)
    // ressemblerait à un bug d'affichage.
    const servedLegend = Text(
      'Colonnes : qualité réellement servie par YouTube pour chaque palier '
      'testé — il ajuste lui-même selon le réseau et la taille du lecteur.',
      style: TextStyle(fontSize: 11, color: YeleColors.muted),
    );
    final alwaysShowLegend =
        qualities.any((q) => q.reached); // au moins un palier mesuré

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      decoration: BoxDecoration(
        color: YeleColors.panel,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10)],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _headerRow(),
          _row('Taux de performance', _performance, bold: true),
          _row('Chargement initial', _loading),
          _row('Temps de mise en tampon', _buffering),
          _row('Données consommées', _data, last: true),
          if (alwaysShowLegend)
            Container(
              width: double.infinity,
              color: YeleColors.panel2,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: servedLegend,
            ),
          if (qualities.any((q) => q.reached && !q.stable)) _unstableNote(),
        ],
      ),
    );
  }

  /// YouTube peut basculer de qualité en cours de lecture. Le signaler évite
  /// de présenter comme une mesure d'une qualité des chiffres qui en
  /// mélangent deux.
  Widget _unstableNote() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: YeleColors.line)),
      ),
      color: YeleColors.panel2,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: const Text(
        '* qualité modifiée par YouTube pendant la mesure : valeurs indicatives',
        style: TextStyle(fontSize: 11, color: YeleColors.muted),
      ),
    );
  }

  /// En-tête : libellé de la source à gauche, une colonne par qualité.
  Widget _headerRow() {
    return Row(
      children: [
        Expanded(
          flex: 34,
          child: Container(
            color: YeleColors.testMid,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            child: const Text(
              'YouTube',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1F3A00)),
            ),
          ),
        ),
        for (final q in qualities)
          Expanded(
            flex: 22,
            child: Container(
              color: q.label == activeLabel
                  ? YeleColors.primary.withValues(alpha: 0.18)
                  : YeleColors.panel2,
              padding: const EdgeInsets.symmetric(vertical: 14),
              alignment: Alignment.center,
              child: Text(
                // En-tête dynamique : la qualité que YouTube a servie pour
                // ce palier (ex. 1440p affiché sous le palier 2160p), et la
                // qualité demandée tant qu'aucune mesure n'existe. Les
                // doublons restent : une colonne par palier testé.
                q.reached && !q.stable
                    ? '${q.displayLabel} *'
                    : q.displayLabel,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: YeleColors.field),
              ),
            ),
          ),
      ],
    );
  }

  Widget _row(
    String label,
    String Function(StreamingQualityResult) value, {
    bool bold = false,
    bool last = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: YeleColors.line)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 34,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              child: Text(
                label,
                style: const TextStyle(fontSize: 12.5, color: YeleColors.field),
              ),
            ),
          ),
          for (final q in qualities)
            Expanded(
              flex: 22,
              child: Container(
                color: q.label == activeLabel
                    ? YeleColors.primary.withValues(alpha: 0.08)
                    : null,
                padding: const EdgeInsets.symmetric(vertical: 11),
                alignment: Alignment.center,
                child: Text(
                  value(q),
                  style: TextStyle(
                    fontSize: 12.5,
                    color: YeleColors.ink,
                    fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
