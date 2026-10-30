import 'package:flutter/material.dart';

import '../constants/conditions_utilisation.dart';
import '../theme/yele_theme.dart';

/// IMP-14 — Conditions d'utilisation et politique de confidentialité
/// complètes. Ouvert depuis l'écran du premier lancement et depuis les
/// réglages, d'où un simple bouton retour plutôt que le tiroir de navigation
/// (avant l'accord, aucun autre écran ne doit être accessible).
class ConditionsScreen extends StatelessWidget {
  const ConditionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: YeleColors.panel,
      appBar: AppBar(
        backgroundColor: YeleColors.header,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Conditions d\'utilisation',
            style: TextStyle(fontSize: 17)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Text('Dernière mise à jour : $CONDITIONS_DATE',
              style: TextStyle(fontSize: 13, color: YeleColors.muted)),
          for (final section in CONDITIONS_UTILISATION) ..._section(section),
        ],
      ),
    );
  }

  List<Widget> _section(ConditionsSection section) => [
        const SizedBox(height: 22),
        Text(section.title,
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: YeleColors.ink)),
        const SizedBox(height: 8),
        for (final p in section.paragraphs)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(p, style: conditionsBodyStyle(YeleColors.ink)),
          ),
        for (final b in section.bullets) ConditionsBullet(b),
      ];
}

TextStyle conditionsBodyStyle(Color color) =>
    TextStyle(fontSize: 14, height: 1.45, color: color);

/// Ligne à puce, partagée avec l'écran du premier lancement.
class ConditionsBullet extends StatelessWidget {
  final String text;

  /// Couleur du texte ; par défaut celle du texte principal du thème courant.
  final Color? color;

  const ConditionsBullet(this.text, {super.key, this.color});

  @override
  Widget build(BuildContext context) {
    final style = conditionsBodyStyle(color ?? YeleColors.ink);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('•  ', style: style),
          Expanded(child: Text(text, style: style)),
        ],
      ),
    );
  }
}
