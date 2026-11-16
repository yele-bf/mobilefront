import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/conditions_utilisation.dart';
import '../services/consent_service.dart';
import '../services/permission_service.dart';
import '../theme/yele_theme.dart';
import 'conditions_screen.dart';

/// IMP-14 — Écran du premier lancement : les conditions d'utilisation doivent
/// être acceptées avant tout test, donc avant tout envoi au serveur. Il
/// réapparaît si les conditions changent (ConsentService.termsVersion) ou si
/// l'utilisateur retire son accord depuis les réglages.
///
/// Demande du 15/11/2026 : après un « Retirer mon accord », le prochain
/// accord redemande AUSSI les autorisations (localisation, réseau mobile,
/// notifications) — séquence de [PermissionService], comme un premier
/// lancement. Android interdit à une app de révoquer elle-même une
/// permission déjà accordée : celle-ci est re-vérifiée, celles refusées
/// redéclenchent la boîte système, celles refusées « définitivement »
/// ouvrent les réglages Android.
class ConsentScreen extends StatelessWidget {
  /// Écran ouvert après l'accord (le test par défaut des réglages).
  final String nextRoute;

  const ConsentScreen({super.key, this.nextRoute = '/full'});

  Future<void> _accept(BuildContext context) async {
    await ConsentService.instance.accept();
    // Re-confirmation des autorisations si l'utilisateur avait retiré son
    // accord (drapeau posé par ConsentService.withdraw) : on redemande les
    // trois permissions AVANT d'entrer dans l'application.
    if (ConsentService.instance.shouldReconfirmPermissions) {
      if (!context.mounted) return;
      await _reconfirmPermissions(context);
      await ConsentService.instance.clearReconfirm();
    }
    if (!context.mounted) return;
    Navigator.of(context).pushReplacementNamed(nextRoute);
  }

  /// Redemande chaque permission l'une après l'autre. Une permission déjà
  /// accordée est re-vérifiée sans boîte système (contrainte Android) ;
  /// un refus « définitif » ouvre les réglages Android au choix de
  /// l'utilisateur — l'app n'est jamais bloquée : « Plus tard » continue.
  Future<void> _reconfirmPermissions(BuildContext context) async {
    final perms = PermissionService();
    for (final p in YelePermission.values) {
      final state = await perms.request(p);
      if (state != PermissionState.deniedForever) continue;
      if (!context.mounted) return;
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('« ${p.label} » est bloquée'),
          content: Text(
            "Vous l'avez refusée définitivement. Pour la réactiver, "
            "ouvrez les réglages Android de Yélé.\n\nVous pourrez aussi "
            "le faire plus tard dans Réglages → Autorisations.",
            style: const TextStyle(fontSize: 14, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Plus tard'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Ouvrir les réglages'),
            ),
          ],
        ),
      );
      if (go == true) await perms.openAppSettings();
    }
    // « Utiliser le GPS » : le service de localisation du téléphone, l'app
    // ne peut pas l'activer elle-même — on propose les réglages Android.
    if (!await perms.isGpsServiceEnabled()) {
      if (!context.mounted) return;
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Le GPS du téléphone est désactivé'),
          content: const Text(
            'La géolocalisation est nécessaire pour placer vos mesures sur '
            'la carte. Activez-la dans les réglages Android.',
            style: TextStyle(fontSize: 14, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Plus tard'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Ouvrir les réglages'),
            ),
          ],
        ),
      );
      if (go == true) await perms.openAppSettings();
    }
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
