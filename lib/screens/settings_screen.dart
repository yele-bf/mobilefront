import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/yele_theme.dart';
import '../widgets/yele_scaffold.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _useGps = true;

  @override
  Widget build(BuildContext context) {
    return YeleScaffold(
      title: 'Réglages',
      route: '/settings',
      body: Container(
        color: YeleColors.panel,
        child: ListView(
          children: [
            _section('Général'),
            _item('Langue', 'Auto'),
            _item('Test par défaut au démarrage', 'Test complet'),
            _item('Unité de débit', 'Mb/s'),
            _item('Style de fond', 'Vert'),
            _toggle('Utiliser le GPS',
                'Active/désactive la géolocalisation des tests', _useGps,
                (v) => setState(() => _useGps = v)),
            _supportSection(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // ── Assistance (FAQ + Contactez-nous) ────────────────────────────────────

  static const _supportEmail = 'support@yele.bf';
  // Numéro fictif (à remplacer par la vraie ligne support avant publication)
  static const _supportPhone = '+226 25 00 00 00';
  static const _supportPhoneRaw = '+22625000000';

  Widget _supportSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section('Assistance'),
        _actionItem(
          icon: Icons.help_outline,
          title: 'FAQ',
          sub: 'Questions fréquentes sur les mesures et l\'application',
          onTap: _openFaq,
        ),
        _actionItem(
          icon: Icons.mail_outline,
          title: 'Contactez-nous',
          sub: 'Signaler un problème ou poser une question ($_supportEmail)',
          onTap: _contactSupport,
        ),
        _actionItem(
          icon: Icons.phone_outlined,
          title: 'Appelez-nous',
          sub: 'Assistance téléphonique ($_supportPhone)',
          onTap: _callSupport,
        ),
        _actionItem(
          icon: Icons.info_outline,
          title: 'À propos de Yélé',
          sub: 'Version de l\'application et mentions légales',
          onTap: _showAbout,
        ),
      ],
    );
  }

  void _openFaq() {
    // FAQ native : les questions s'affichent directement dans l'application
    // (accordéons), sans ouvrir de navigateur ni dépendre d'une URL externe.
    Navigator.of(context).pushNamed('/faq');
  }

  Future<void> _contactSupport() async {
    final uri = Uri(
      scheme: 'mailto',
      path: _supportEmail,
      query: 'subject=Support application Yélé',
    );
    try {
      final ok = await launchUrl(uri).catchError((_) => false);
      if (!ok) _snack('Aucune application e-mail trouvée. Écrivez à $_supportEmail');
    } catch (_) {
      _snack('Aucune application e-mail trouvée. Écrivez à $_supportEmail');
    }
  }

  Future<void> _callSupport() async {
    final uri = Uri(scheme: 'tel', path: _supportPhoneRaw);
    try {
      final ok = await launchUrl(uri).catchError((_) => false);
      if (!ok) _snack('Appel impossible. Appelez le $_supportPhone');
    } catch (_) {
      _snack('Appel impossible. Appelez le $_supportPhone');
    }
  }

  void _showAbout() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('À propos de Yélé'),
        content: const Text(
          'Version 1.0.0\n\n'
          'Mesure de la qualité des réseaux mobiles au Burkina Faso',
          style: TextStyle(fontSize: 14, height: 1.5, color: YeleColors.ink),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  Widget _actionItem({
    required IconData icon,
    required String title,
    required String sub,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0x11000000))),
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: YeleColors.primary),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style:
                          const TextStyle(fontSize: 16, color: YeleColors.ink)),
                  const SizedBox(height: 2),
                  Text(sub,
                      style: const TextStyle(
                          fontSize: 13, color: YeleColors.muted)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 20, color: YeleColors.muted),
          ],
        ),
      ),
    );
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // ── Éléments de liste ─────────────────────────────────────────────────────

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 22, 18, 6),
        child: Text(t,
            style: const TextStyle(
                color: YeleColors.primary,
                fontSize: 15,
                fontWeight: FontWeight.w700)),
      );

  Widget _item(String title, String sub) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0x11000000))),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(fontSize: 16, color: YeleColors.ink)),
            const SizedBox(height: 2),
            Text(sub,
                style: const TextStyle(fontSize: 13, color: YeleColors.muted)),
          ],
        ),
      );

  Widget _toggle(
      String title, String sub, bool value, ValueChanged<bool>? onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0x11000000))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontSize: 16, color: YeleColors.ink)),
                const SizedBox(height: 2),
                Text(sub,
                    style:
                        const TextStyle(fontSize: 13, color: YeleColors.muted)),
              ],
            ),
          ),
          Switch(
            value: value,
            activeThumbColor: YeleColors.primary,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
