import 'package:flutter/material.dart';
import '../theme/yele_theme.dart';

/// Questionnaire de Qualité d'Expérience (QoE), affiché après le test.
class QoeDialog extends StatefulWidget {
  final void Function(int rating, String usage, String satisfaction) onCompleted;
  const QoeDialog({super.key, required this.onCompleted});

  @override
  State<QoeDialog> createState() => _QoeDialogState();
}

class _QoeDialogState extends State<QoeDialog> {
  int _stars = 0;
  String _satisfaction = '';

  static const _satisfactions = [
    {'label': '😀 Très satisfait', 'value': 'very_satisfied'},
    {'label': '🙂 Satisfait', 'value': 'satisfied'},
    {'label': '😐 Moyen', 'value': 'neutral'},
    {'label': '🙁 Insatisfait', 'value': 'unsatisfied'},
  ];

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Column(
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: YeleColors.primary.withValues(alpha: 0.12),
                      ),
                      child: const Icon(Icons.rate_review,
                          color: YeleColors.primary, size: 26),
                    ),
                    const SizedBox(height: 10),
                    Text('Évaluation de l\'expérience',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: YeleColors.surface.ink)),
                    const SizedBox(height: 4),
                    Text(
                        'Aidez-nous à évaluer la qualité ressentie du réseau.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: YeleColors.surface.muted)),
                  ],
                ),
              ),
              const Divider(height: 28),
              Text('1. Comment évaluez-vous la vitesse globale ?',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: YeleColors.surface.ink)),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) {
                  final s = i + 1;
                  return IconButton(
                    icon: Icon(
                      s <= _stars ? Icons.star_rounded : Icons.star_border_rounded,
                      size: 34,
                      color: s <= _stars ? YeleColors.testBot : YeleColors.line,
                    ),
                    onPressed: () => setState(() => _stars = s),
                  );
                }),
              ),
              const SizedBox(height: 16),
              Text('2. Votre niveau de satisfaction générale ?',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: YeleColors.surface.ink)),
              const SizedBox(height: 10),
              ..._satisfactions.map((sat) {
                final sel = _satisfaction == sat['value'];
                return GestureDetector(
                  onTap: () => setState(() => _satisfaction = sat['value']!),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: sel
                          ? YeleColors.primary.withValues(alpha: 0.08)
                          : Colors.white,
                      border: Border.all(
                          color: sel ? YeleColors.primary : YeleColors.line,
                          width: sel ? 1.5 : 1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(sat['label']!,
                            style: TextStyle(
                                fontSize: 13, color: YeleColors.surface.ink)),
                        if (sel)
                          const Icon(Icons.check_circle,
                              color: YeleColors.primary, size: 18),
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text('Ignorer',
                          style: TextStyle(color: YeleColors.surface.muted)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: YeleColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: (_stars > 0 && _satisfaction.isNotEmpty)
                          ? () {
                              widget.onCompleted(_stars, '', _satisfaction);
                              Navigator.of(context).pop();
                            }
                          : null,
                      child: const Text('Soumettre'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
