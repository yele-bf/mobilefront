import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/consent_service.dart';
// IMP-08 — Réglages de consommation : seuil mensuel d'alerte et débit
// temps réel, connectés au service de réglages persistant (Hive).
import '../services/settings_service.dart';
import '../services/throughput_service.dart';
import '../services/usage_tracker_service.dart' show formatGb;
import '../theme/yele_theme.dart';
import '../widgets/yele_scaffold.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _useGps = true;

  // IMP-08 — État courant des réglages de consommation (chargés depuis la
  // box Hive ; conservés localement au cas où la box ne serait pas
  // prête — l'écran doit s'afficher sans crash, réglages par défaut).
  double _limitGb = 0;
  bool _realtimeSpeed = false;

  @override
  void initState() {
    super.initState();
    _loadConsumptionSettings();
    // Reste synchronisé si le réglage change ailleurs (resynchro du débit
    // temps réel au retour au premier plan, par exemple).
    SettingsService.monthlyLimitGbNotifier.addListener(_onConsChanged);
    SettingsService.realtimeSpeedNotifier.addListener(_onConsChanged);
  }

  void _onConsChanged() {
    _loadConsumptionSettings();
  }

  void _loadConsumptionSettings() {
    double limit = _limitGb;
    bool realtime = _realtimeSpeed;
    try {
      limit = SettingsService().monthlyLimitGb;
      realtime = SettingsService().realtimeSpeed;
    } catch (_) {
      // Box non initialisée (démarrage dégradé) : valeurs par défaut.
    }
    if (!mounted) return;
    setState(() {
      _limitGb = limit;
      _realtimeSpeed = realtime;
    });
  }

  @override
  void dispose() {
    SettingsService.monthlyLimitGbNotifier.removeListener(_onConsChanged);
    SettingsService.realtimeSpeedNotifier.removeListener(_onConsChanged);
    super.dispose();
  }

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
            _toggle(
              'Utiliser le GPS',
              'Active/désactive la géolocalisation des tests',
              _useGps,
              (v) => setState(() => _useGps = v),
            ),
            // IMP-08 — Réglages du suivi de consommation : le seuil
            // alimente la jauge, le bandeau « seuil dépassé » et la
            // notification native de l'écran Consommation ; le débit temps
            // réel pilote le service Android (pastille de la barre d'état).
            _section('Consommation'),
            _actionItem(
              icon: Icons.data_usage,
              title: 'Limite mensuelle de données',
              sub: _limitLabel(),
              onTap: _pickLimit,
            ),
            _toggle(
              'Débit temps réel',
              "Affiche le débit instantané dans la barre d'état Android",
              _realtimeSpeed,
              (v) => _setRealtimeSpeed(v),
            ),
            _supportSection(),
            SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // ── IMP-08 — Seuil mensuel et débit temps réel ───────────────────────────

  /// Libellé de la ligne de seuil : « Aucune alerte » ou « Alerte à 5 Go ».
  String _limitLabel() =>
      _limitGb > 0 ? 'Alerte à ${formatGb(_limitGb)} Go' : 'Aucune alerte';

  /// Sélecteur du seuil mensuel (en Go ; 0 = désactivé). Presets adaptés
  /// forfaits Burkina + saisie manuelle libre avec décimales (REVUE IMP-08
  /// du 08/11 : la limite doit pouvoir se placer entre « Aucune alerte »
  /// et 1 Go, donc sous la forme 0,5 Go par exemple).
  Future<void> _pickLimit() async {
    final chosen = await showDialog<double>(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController();
        String? errorText;
        var selected = _limitGb;
        return StatefulBuilder(
          builder: (ctx, setDialog) => AlertDialog(
            title: const Text('Limite mensuelle de données'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final go in const [
                    0.0,
                    1.0,
                    2.0,
                    3.0,
                    5.0,
                    10.0,
                    20.0,
                    50.0,
                  ])
                    InkWell(
                      onTap: () {
                        selected = go;
                        setDialog(() {});
                        Navigator.of(ctx).pop(go);
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 10,
                        ),
                        child: Text(
                          go == 0 ? 'Aucune alerte' : '${formatGb(go)} Go',
                          style: TextStyle(
                            fontSize: 15,
                            color: go > 0 && go == selected
                                ? YeleColors.primary
                                : YeleColors.ink,
                            fontWeight: go == selected
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: controller,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Valeur manuelle (Go)',
                      hintText: 'Ex. 0,5',
                      errorText: errorText,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => setDialog(() => errorText = null),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Annuler'),
              ),
              TextButton(
                onPressed: () {
                  final raw = controller.text.trim().replaceAll(',', '.');
                  final v = double.tryParse(raw);
                  if (v == null || v <= 0 || v > 1000) {
                    setDialog(
                      () => errorText = 'Valeur invalide (0,01 à 1 000 Go)',
                    );
                    return;
                  }
                  Navigator.of(ctx).pop(v);
                },
                child: const Text('Valider'),
              ),
            ],
          ),
        );
      },
    );
    if (chosen == null || chosen == _limitGb) return;
    try {
      SettingsService().monthlyLimitGb = chosen;
    } catch (_) {
      if (!mounted) return;
      _snack("Impossible d'enregistrer la limite (réglages indisponibles).");
      return;
    }
    if (!mounted) return;
    setState(() => _limitGb = chosen);
  }

  /// Bascule du débit temps réel : main.dart démarre/arrête le service
  /// Android dès que le notificateur change ; on vérifie ensuite que le
  /// service natif a survécu (autorisation « Afficher par-dessus »,
  /// notification…) et on prévient l'utilisateur si ce n'est pas le cas.
  Future<void> _setRealtimeSpeed(bool want) async {
    try {
      SettingsService().realtimeSpeed = want;
    } catch (_) {
      // Box non initialisée : l'interrupteur reste sans effet persistant.
    }
    if (!mounted) return;
    setState(() => _realtimeSpeed = want);
    if (!want || !ThroughputService.instance.isSupported) return;

    await Future.delayed(const Duration(milliseconds: 600));
    final running = await ThroughputService.instance.isNativeRunning();
    if (!running && mounted) {
      _snack(
        'Débit temps réel indisponible — vérifiez les autorisations '
        "Android (notifications, « Afficher par-dessus »).",
      );
    }
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
        // IMP-14 : relire les conditions acceptées au premier lancement, ou
        // retirer son accord.
        _actionItem(
          icon: Icons.policy_outlined,
          title: "Conditions d'utilisation",
          sub: 'Données collectées, usage et vos droits',
          onTap: () => Navigator.of(context).pushNamed('/conditions'),
        ),
        _actionItem(
          icon: Icons.block_outlined,
          title: 'Retirer mon accord',
          sub: 'Les conditions vous seront présentées à nouveau',
          onTap: _withdrawConsent,
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
      if (!ok) {
        _snack('Aucune application e-mail trouvée. Écrivez à $_supportEmail');
      }
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

  Future<void> _withdrawConsent() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Retirer mon accord ?'),
        content: Text(
          "Aucun test ne sera possible tant que vous n'aurez pas accepté à "
          "nouveau les conditions d'utilisation.",
          style: TextStyle(fontSize: 14, height: 1.5, color: YeleColors.ink),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Retirer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ConsentService.instance.withdraw();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/consent', (_) => false);
  }

  void _showAbout() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('À propos de Yélé'),
        content: Text(
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
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(fontSize: 16, color: YeleColors.ink),
                  ),
                  SizedBox(height: 2),
                  Text(
                    sub,
                    style: TextStyle(fontSize: 13, color: YeleColors.muted),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 20, color: YeleColors.muted),
          ],
        ),
      ),
    );
  }

  void _snack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // ── Éléments de liste ─────────────────────────────────────────────────────

  Widget _section(String t) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 22, 18, 6),
    child: Text(
      t,
      style: TextStyle(
        color: YeleColors.primary,
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  Widget _item(String title, String sub) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: Color(0x11000000))),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: TextStyle(fontSize: 16, color: YeleColors.ink)),
        SizedBox(height: 2),
        Text(sub, style: TextStyle(fontSize: 13, color: YeleColors.muted)),
      ],
    ),
  );

  Widget _toggle(
    String title,
    String sub,
    bool value,
    ValueChanged<bool>? onChanged,
  ) {
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
                Text(
                  title,
                  style: TextStyle(fontSize: 16, color: YeleColors.ink),
                ),
                SizedBox(height: 2),
                Text(
                  sub,
                  style: TextStyle(fontSize: 13, color: YeleColors.muted),
                ),
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
