import 'package:flutter/material.dart';

import '../services/streaming_test_service.dart';
import '../theme/yele_theme.dart';

/// Tableau des mesures de streaming, une colonne par qualité vidéo.
///
/// Quatre lignes : taux de performance, chargement initial, temps de mise en
/// tampon, données consommées. Une qualité que YouTube n'a pas servie affiche
/// « — » sur toute sa colonne.
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

    final hasServedNote =
        qualities.any((q) => q.reached && q.servedLabel.isNotEmpty);

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
          _row('Données consommées', _data, last: !hasServedNote),
          if (hasServedNote) _servedLegend(),
          if (qualities.any((q) => q.reached && !q.stable))
            _unstableNote(separated: hasServedNote),
        ],
      ),
    );
  }

  /// Légende de l'indication « servi : X » affichée dans l'en-tête : sans
  /// elle, « 2160p / servi : 1440p » ressemble à une erreur d'affichage
  /// plutôt qu'à l'information qu'une demande 4K n'a tenu qu'en 1440p.
  Widget _servedLegend() {
    return Container(
      width: double.infinity,
      color: YeleColors.panel2,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: const Text(
        '« servi » : qualité réellement délivrée par YouTube pour la qualité '
        'demandée — il ajuste lui-même selon le réseau et la taille du lecteur.',
        style: TextStyle(fontSize: 11, color: YeleColors.muted),
      ),
    );
  }

  /// YouTube peut basculer de qualité en cours de lecture. Le signaler évite
  /// de présenter comme une mesure d'une qualité des chiffres qui en
  /// mélangent deux. [separated] trace un filet quand la légende « servi »
  /// précède, pour que les deux notes ne fondent pas en un seul bloc.
  Widget _unstableNote({required bool separated}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: YeleColors.panel2,
        border: separated
            ? const Border(top: BorderSide(color: YeleColors.line))
            : null,
      ),
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
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    q.reached && !q.stable ? '${q.label} *' : q.label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: YeleColors.field),
                  ),
                  // Qualité réellement servie quand elle diffère de la
                  // qualité demandée (colonne) : « servi : 1440p » sous
                  // « 2160p » dit d'un coup d'œil ce que le réseau a tenu.
                  if (q.reached && q.servedLabel.isNotEmpty)
                    Text(
                      'servi : ${q.servedLabel}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 10.5, color: YeleColors.muted),
                    ),
                ],
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
