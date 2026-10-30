import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/conditions_utilisation.dart';
import '../services/consent_service.dart';
import '../theme/yele_theme.dart';
import 'conditions_screen.dart';

/// IMP-14 — Écran du premier lancement : les conditions d'utilisation doivent
/// être acceptées avant tout test, donc avant tout envoi au serveur. Il
/// réapparaît si les conditions changent (ConsentService.termsVersion) ou si
/// l'utilisateur retire son accord depuis les réglages.
class ConsentScreen extends StatelessWidget {
  /// Écran ouvert après l'accord (le test par défaut des réglages).
  final String nextRoute;

  const ConsentScreen({super.key, this.nextRoute = '/full'});

  Future<void> _accept(BuildContext context) async {
    await ConsentService.instance.accept();
    if (!context.mounted) return;
    Navigator.of(context).pushReplacementNamed(nextRoute);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: YeleColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
                children: [
                  const Text.rich(
                    TextSpan(
                      style: TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w700,
                          color: Colors.white),
                      children: [
                        TextSpan(text: 'Yé'),
                        TextSpan(
                            text: 'lé',
                            style: TextStyle(color: YeleColors.primary)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text('Mesure de la qualité des réseaux mobiles',
                      style: TextStyle(fontSize: 14, color: _soft)),
                  const SizedBox(height: 28),
                  const Text('Conditions d\'utilisation',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                  const SizedBox(height: 12),
                  const Text(
                    'Vos mesures alimentent la carte publique de couverture '
                    'du Burkina Faso. Pour cela, chaque test que vous lancez '
                    'envoie au serveur Yélé :',
                    style: _text,
                  ),
                  const SizedBox(height: 12),
                  for (final item in CONSENT_SUMMARY)
                    ConditionsBullet(item, color: _bullet),
                  const SizedBox(height: 12),
                  const Text(
                    'Yélé ne collecte ni votre nom, ni votre numéro, ni vos '
                    'contacts, et ne contient aucune publicité. Un test '
                    'consomme des données de votre forfait mobile.',
                    style: _text,
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          foregroundColor: YeleColors.accent),
                      onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const ConditionsScreen())),
                      child: const Text(
                          'Lire les conditions d\'utilisation complètes'),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: YeleColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                    onPressed: () => _accept(context),
                    child: const Text('J\'accepte et je continue',
                        style: TextStyle(fontSize: 16)),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: _soft),
                    // Refuser ferme l'app : sans envoi au serveur, aucune
                    // fonction de Yélé n'a de sens.
                    onPressed: () => SystemNavigator.pop(),
                    child: const Text('Refuser et quitter'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const _soft = Color(0xFF9FB0C6);
const _bullet = Color(0xFFE7ECF4);
const _text = TextStyle(fontSize: 15, height: 1.45, color: Color(0xFFCFD6E0));
