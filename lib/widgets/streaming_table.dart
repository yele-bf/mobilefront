import 'package:flutter/material.dart';

import '../constants/config.dart';
import '../services/streaming_test_service.dart';
import '../theme/yele_theme.dart';

/// Tableau des mesures de streaming, une colonne par palier testé.
///
/// Lignes : taux de performance, chargement initial, temps de mise en tampon,
/// données consommées — plus, en moteur HLS uniquement, le débit minimal
/// requis pour qu'un palier puisse démarrer (voir [_minBandwidth]).
///
/// En moteur YouTube, l'en-tête de chaque colonne affiche la qualité que
/// YouTube a RÉELLEMENT servie (souvent différente de la qualité demandée) ;
/// en moteur HLS la qualité est verrouillée : l'en-tête reste la qualité
/// demandée. Un palier sans mesure garde sa colonne, avec « — » sur toute la
/// hauteur.
class StreamingTable extends StatelessWidget {
  final List<StreamingQualityResult> qualities;

  /// Qualité en cours de mesure, surlignée pendant le test. null hors test.
  final String? activeLabel;

  /// 'youtube' (défaut, rétro-compatible) ou 'hls' : change l'en-tête et
  /// l'ajout de la ligne « Débit mini requis ».
  final String videoEngine;

  const StreamingTable({
    super.key,
    required this.qualities,
    this.activeLabel,
    this.videoEngine = 'youtube',
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

  /// Nombre d'interruptions après démarrage (dépôt YouTube : case vide
  /// plutôt que 0 quand il n'y en a pas eu).
  String _rebuffers(StreamingQualityResult q) {
    if (!q.reached || q.rebufferCount <= 0) return _dash;
    return '${q.rebufferCount}';
  }

  /// Débit minimal requis par le palier, en Mb/s lisibles (« ≥ 2,36 Mb/s »).
  /// [minKbps] = label → kb/s, calculé dans [build] à partir de la config :
  /// taille du premier fragment (BANDWIDTH du manifeste × 4 s) rapportée au
  /// timeout de démarrage. Un réseau qui ne tient pas ce débit dès la première
  /// seconde ne peut pas amorcer le palier — d'où la colonne vide à côté.
  String _minBandwidth(StreamingQualityResult q, Map<String, int> minKbps) {
    final kbps = minKbps[q.label] ?? 0;
    if (kbps <= 0) return _dash;
    return '≥ ${(kbps / 1e3).toStringAsFixed(2)} Mb/s';
  }

  @override
  Widget build(BuildContext context) {
    if (qualities.isEmpty) return const SizedBox.shrink();

    final isHls = videoEngine == 'hls';

    // Débit mini requis par palier (label → kb/s), en moteur HLS uniquement :
    // le fragment initial (BANDWIDTH du manifeste × 4 s) doit être reçu entier
    // avant la première image, dans le timeout — sinon le palier reste vide.
    final minKbps = <String, int>{
      if (isHls)
        for (final e in STREAMING_QUALITY_LEVELS.entries)
          e.value: minRequiredKbpsFor(STREAMING_LEVEL_BANDWIDTH_BPS[e.key] ?? 0),
    };

    // En YouTube seulement : l'en-tête affiche la qualité servie, qui peut
    // différer de la qualité demandée (1440p pour un palier 2160p) — sans
    // cette légende, le libellé ressemblerait à un bug d'affichage.
    final servedLegend = Text(
      'Colonnes : qualité réellement servie par YouTube pour chaque palier '
      'testé — il ajuste lui-même selon le réseau et la taille du lecteur.',
      style: TextStyle(fontSize: 11, color: YeleColors.muted),
    );
    final alwaysShowLegend =
        !isHls && qualities.any((q) => q.reached); // au moins un palier mesuré

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
          _headerRow(isHls),
          _row('Taux de performance', _performance, bold: true),
          _row('Chargement initial', _loading),
          _row('Temps de mise en tampon', _buffering),
          _row('Données consommées', _data),
          if (isHls)
            _row('Débit mini requis', (q) => _minBandwidth(q, minKbps),
                hint: 'Premier fragment (4 s) rapporté au délai max de '
                    'démarrage : un réseau qui ne tient pas ce débit laisse '
                    'le palier vide.'),
          _row('Interruptions', _rebuffers, last: !isHls),
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
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: YeleColors.line)),
      ),
      color: YeleColors.panel2,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Text(
        '* qualité modifiée par YouTube pendant la mesure : valeurs indicatives',
        style: TextStyle(fontSize: 11, color: YeleColors.muted),
      ),
    );
  }

  /// En-tête : nom du moteur à gauche (YouTube, ou HLS — la qualité y est
  /// verrouillée), une colonne par qualité.
  Widget _headerRow(bool isHls) {
    return Row(
      children: [
        Expanded(
          flex: 34,
          child: Container(
            color: YeleColors.testMid,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            child: Text(
              isHls ? 'HLS' : 'YouTube',
              style: const TextStyle(
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
                // En YouTube : la qualité réellement servie pour ce palier
                // (ex. 1440p affiché sous le palier 2160p), et la qualité
                // demandée tant qu'aucune mesure n'existe. Les doublons
                // restent : une colonne par palier testé.
                // En HLS la qualité est verrouillée : toujours la demandée.
                q.reached && !q.stable && !isHls
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
    String? hint,
  }) {
    return Container(
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(bottom: BorderSide(color: YeleColors.line)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 34,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 12.5, color: YeleColors.field)),
                  if (hint != null)
                    Text(hint,
                        style: TextStyle(
                            fontSize: 10, color: YeleColors.muted)),
                ],
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
