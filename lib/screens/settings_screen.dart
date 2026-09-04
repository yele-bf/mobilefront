import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../constants/config.dart';
import '../services/background_collection_service.dart';
import '../services/permission_service.dart';
import '../theme/yele_theme.dart';
import '../widgets/yele_scaffold.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  final _collect = BackgroundCollectionService();
  CollectStatus _status = CollectStatus.unavailable;
  bool _busy = false;

  final _perms = PermissionService();
  Map<YelePermission, PermissionState> _permStates = {};
  final Set<YelePermission> _busyPerms = {};
  bool _gpsOn = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshStatus();
    _refreshPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Retour des réglages système : relire l'état des permissions.
    if (state == AppLifecycleState.resumed) {
      _refreshStatus();
      _refreshPermissions();
    }
  }

  Future<void> _refreshStatus() async {
    final status = await _collect.status();
    if (!mounted) return;
    setState(() => _status = status);
  }

  Future<void> _refreshPermissions() async {
    final states = await _perms.checkAll();
    final gps = await _perms.isGpsServiceEnabled();
    if (!mounted) return;
    setState(() {
      _permStates = states;
      _gpsOn = gps;
    });
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
            ..._permissionsSection(),
            if (_collect.isSupported) ..._collectSection(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // ── Autorisations du téléphone ────────────────────────────────────────────

  /// Section groupant les autorisations Android requises par l'application :
  /// la localisation et le réseau mobile sont obligatoires, les notifications
  /// facultatives.
  List<Widget> _permissionsSection() {
    final web = kIsWeb;
    return [
      _section('Autorisations'),
      Container(
        padding: const EdgeInsets.fromLTRB(18, 2, 18, 10),
        child: Text(
          web
              ? 'Ces autorisations s\'appliquent à l\'application Android '
                  'installée sur le téléphone. Sur le web, aucune permission '
                  'système n\'est requise : la localisation utilise l\'adresse IP.'
              : 'Localisation et Réseau mobile sont obligatoires pour des '
                  'mesures exploitables (position sur la carte, opérateur, '
                  'technologie). Notifications est facultative : elle sert '
                  'uniquement à la collecte de couverture en arrière-plan.',
          style: const TextStyle(fontSize: 13, color: YeleColors.muted),
        ),
      ),
      for (final p in YelePermission.values) _permissionTile(p),
    ];
  }

  /// Ligne d'autorisation avec une bascule qui reflète l'état réel de la
  /// permission Android : ON quand elle est accordée, OFF sinon (IMP-04). On
  /// ne stocke rien en local — c'est Android qui fait foi, et l'état est relu
  /// à chaque retour au premier plan (voir [didChangeAppLifecycleState]).
  Widget _permissionTile(YelePermission p) {
    final state = _permStates[p];
    final busy = _busyPerms.contains(p);
    final web = kIsWeb;
    final required = p.required;

    // Couleur de la pastille « Obligatoire » / « Facultative ».
    final chipColor = required ? YeleColors.primaryDk : YeleColors.muted;

    // Alerte GPS : permission accordée mais service de localisation éteint →
    // les tests seront bloqués tant qu'il est désactivé (voir ISS-09).
    final gpsWarn = !web &&
        p == YelePermission.location &&
        state == PermissionState.granted &&
        !_gpsOn;

    final granted = state == PermissionState.granted;
    final deniedForever = state == PermissionState.deniedForever;
    final unavailable = state == PermissionState.unavailable;

    // Sur le web il n'y a pas de permission système ; pendant une demande en
    // cours (popup système affichée) la bascule est désactivée.
    final togglable = !web && state != null && !busy;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0x11000000))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(p.label,
                          style: const TextStyle(
                              fontSize: 16, color: YeleColors.ink)),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: chipColor.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        required ? 'Obligatoire' : 'Facultative',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: chipColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(p.description,
                    style: const TextStyle(
                        fontSize: 13, color: YeleColors.muted)),
                if (deniedForever) ...[
                  const SizedBox(height: 5),
                  Text(
                    'Refus définitif : touchez la bascule pour ouvrir les '
                    'réglages Android et autoriser.',
                    style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: YeleColors.danger,
                        height: 1.3),
                  ),
                ],
                if (unavailable) ...[
                  const SizedBox(height: 5),
                  Text(
                    web
                        ? 'Non requise sur le web (la localisation utilise '
                            'l\'adresse IP).'
                        : 'Non requise sur cette plateforme.',
                    style: const TextStyle(
                        fontSize: 12.5, color: YeleColors.muted, height: 1.3),
                  ),
                ],
                if (gpsWarn) ...[
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      const Icon(Icons.warning_amber,
                          size: 14, color: YeleColors.warn),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          'GPS du téléphone éteint : les tests resteront '
                          'bloqués tant qu\'il est désactivé.',
                          style: const TextStyle(
                              fontSize: 12.5,
                              color: YeleColors.warn,
                              height: 1.3),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (busy)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Switch(
              value: granted,
              activeThumbColor: YeleColors.primary,
              onChanged: togglable ? (v) => _onTogglePermission(p, v) : null,
            ),
        ],
      ),
    );
  }

  /// Bascule d'une autorisation :
  /// - **OFF → ON** : demande la permission à Android (popup système). Si
  ///   l'utilisateur avait refusé définitivement, Android ne réaffiche plus la
  ///   popup : on ouvre alors les réglages système de l'app.
  /// - **ON → OFF** : Android interdit à l'app de retirer elle-même une
  ///   permission accordée ; on ouvre la page « Applications → Yélé » où
  ///   l'utilisateur la désactive. À la fermeture, l'état est relu et la
  ///   bascule se met à jour (voir [didChangeAppLifecycleState]).
  Future<void> _onTogglePermission(YelePermission p, bool target) async {
    final state = _permStates[p];

    if (!target) {
      final go = await _showPermissionDialog(
        title: 'Désactiver « ${p.label} » ?',
        message: 'Yélé ne peut pas retirer elle-même une autorisation déjà '
            'accordée à Android. La page « Applications → Yélé » va '
            's\'ouvrir : désactivez-y l\'interrupteur « ${p.label} », puis '
            'revenez dans l\'application.',
      );
      if (go != true || !mounted) return;
      await _openSettings(p);
      return;
    }

    if (state == PermissionState.deniedForever) {
      final go = await _showPermissionDialog(
        title: 'Autoriser « ${p.label} » ?',
        message: 'Android a mémorisé votre refus et ne réaffichera plus la '
            'demande. La page « Applications → Yélé » va s\'ouvrir : '
            'autorisez-y « ${p.label} », puis revenez dans l\'application.',
      );
      if (go != true || !mounted) return;
      await _openSettings(p);
      return;
    }

    // Cas courant : permission refusée une fois (ou état inconnu) → popup
    // système classique.
    await _authorize(p);
  }

  /// Petit dialogue d'explication avant d'ouvrir les réglages système
  /// d'Android (l'app n'a aucun contrôle direct sur ces permissions).
  Future<bool?> _showPermissionDialog({
    required String title,
    required String message,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message, style: const TextStyle(fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ouvrir les réglages'),
          ),
        ],
      ),
    );
  }

  Future<void> _authorize(YelePermission p) async {
    if (_busyPerms.contains(p)) return;
    setState(() => _busyPerms.add(p));
    await _perms.request(p);
    // La réponse de la popup système arrive parfois en différé (canal natif).
    await Future.delayed(const Duration(milliseconds: 500));
    await _refreshPermissions();
    if (!mounted) return;
    setState(() => _busyPerms.remove(p));
    final after = _permStates[p];
    if (after == PermissionState.deniedForever) {
      _snack('Refus définitif : touchez la bascule pour ouvrir les réglages '
          'Android et autoriser.');
    } else if (after == PermissionState.denied) {
      _snack('Si la fenêtre système est affichée, accordez l\'autorisation.');
    }
  }

  Future<void> _openSettings(YelePermission p) async {
    await _perms.openAppSettings();
  }

  // ── Collecte de couverture ────────────────────────────────────────────────

  List<Widget> _collectSection() {
    return [
      _section('Collecte de couverture'),
      _toggle(
        'Contribuer en arrière-plan',
        'Relève la couverture réseau autour de vous, même application fermée',
        _status.enabled,
        _busy ? null : _onToggleCollect,
      ),
      if (_status.enabled) ...[
        _intervalPicker(),
        _statusTile(),
      ],
      if (_status.wasKilled) _batteryWarning(),
    ];
  }

  Future<void> _onToggleCollect(bool value) async {
    if (!value) {
      setState(() => _busy = true);
      await _collect.stop();
      await _refreshStatus();
      if (mounted) setState(() => _busy = false);
      return;
    }

    // Divulgation explicite avant toute activation : Google Play l'exige pour
    // toute collecte en arrière-plan, et l'utilisateur doit savoir ce qui est
    // relevé et ce que cela coûte avant d'accepter.
    final accepted = await _showConsentDialog();
    if (accepted != true) return;

    setState(() => _busy = true);
    final started = await _collect.start(intervalMinutes: _status.intervalMinutes);
    await _refreshStatus();
    if (!mounted) return;
    setState(() => _busy = false);

    if (!started) {
      // Le plus souvent : Android vient d'afficher la demande d'autorisation
      // de notification. Sans notification, le service est tué aussitôt.
      _snack('Autorisez la notification, puis réactivez la collecte.');
    }
  }

  Future<bool?> _showConsentDialog() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Contribuer à la carte de couverture'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Yélé relèvera régulièrement, même lorsque l\'application est '
                'fermée :',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 10),
              _bullet('votre position'),
              _bullet('la technologie du réseau (2G, 3G, 4G, 5G)'),
              _bullet('l\'opérateur de votre carte SIM'),
              _bullet('la puissance du signal'),
              const SizedBox(height: 12),
              const Text(
                'Aucun test de débit n\'est effectué. Chaque relève consomme '
                'environ 4 Ko, soit une dizaine de mégaoctets par mois à la '
                'cadence de 15 minutes — moins d\'un centième de ce que '
                'coûterait un test de débit automatique.',
                style: TextStyle(fontSize: 13, color: YeleColors.muted),
              ),
              const SizedBox(height: 10),
              const Text(
                'Une notification permanente reste affichée tant que la '
                'collecte est active. Vous pouvez l\'arrêter à tout moment, '
                'depuis cette notification ou depuis ces réglages.',
                style: TextStyle(fontSize: 13, color: YeleColors.muted),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Refuser'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('J\'accepte'),
          ),
        ],
      ),
    );
  }

  Widget _bullet(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('•  ', style: TextStyle(fontSize: 14)),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
          ],
        ),
      );

  Widget _intervalPicker() {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0x11000000))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Fréquence des relèves',
              style: TextStyle(fontSize: 16, color: YeleColors.ink)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: BACKGROUND_INTERVAL_CHOICES.map((minutes) {
              final selected = minutes == _status.intervalMinutes;
              return ChoiceChip(
                label: Text(minutes < 60 ? '$minutes min' : '${minutes ~/ 60} h'),
                selected: selected,
                selectedColor: YeleColors.primary.withValues(alpha: .18),
                onSelected: _busy ? null : (_) => _changeInterval(minutes),
              );
            }).toList(),
          ),
          const SizedBox(height: 6),
          Text(
            backgroundIntervalLabel(_status.intervalMinutes),
            style: const TextStyle(fontSize: 13, color: YeleColors.muted),
          ),
        ],
      ),
    );
  }

  Future<void> _changeInterval(int minutes) async {
    setState(() => _busy = true);
    // Redémarrer le service applique la nouvelle cadence : le minuteur est
    // relancé à l'intervalle demandé.
    await _collect.start(intervalMinutes: minutes);
    await _refreshStatus();
    if (mounted) setState(() => _busy = false);
  }

  Widget _statusTile() {
    final last = _status.lastCollectAt;
    final lastLabel = last == null
        ? 'Aucune relève envoyée pour l\'instant'
        : 'Dernière relève : ${_formatTime(last)}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0x11000000))),
      ),
      child: Row(
        children: [
          Icon(
            _status.running ? Icons.sensors : Icons.sensors_off,
            size: 20,
            color: _status.running ? YeleColors.primary : YeleColors.muted,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(lastLabel,
                    style: const TextStyle(fontSize: 14, color: YeleColors.ink)),
                const SizedBox(height: 2),
                Text('${_status.count} relève${_status.count > 1 ? 's' : ''} envoyée${_status.count > 1 ? 's' : ''}',
                    style: const TextStyle(
                        fontSize: 13, color: YeleColors.muted)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            color: YeleColors.muted,
            tooltip: 'Actualiser',
            onPressed: _refreshStatus,
          ),
        ],
      ),
    );
  }

  /// Avertissement affiché quand la collecte est activée mais que le service
  /// ne tourne plus : sur beaucoup de téléphones (Tecno, Infinix, Xiaomi,
  /// Oppo…), le gestionnaire de batterie tue les services d'arrière-plan sans
  /// prévenir. C'est la première cause de collecte silencieusement interrompue.
  Widget _batteryWarning() {
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 14, 18, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        border: Border.all(color: const Color(0xFFEA580C), width: 1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.battery_alert, size: 18, color: Color(0xFFEA580C)),
              SizedBox(width: 8),
              Text('Collecte interrompue par le système',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFEA580C))),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Votre téléphone a arrêté la collecte pour économiser la batterie. '
            'Pour qu\'elle continue, ouvrez Paramètres → Applications → Yélé → '
            'Batterie, et choisissez « Sans restriction ».',
            style: TextStyle(fontSize: 13, height: 1.4),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime t) {
    final now = DateTime.now();
    final diff = now.difference(t);
    if (diff.inMinutes < 1) return 'à l\'instant';
    if (diff.inMinutes < 60) return 'il y a ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'il y a ${diff.inHours} h';
    return '${t.day}/${t.month} à ${t.hour}h${t.minute.toString().padLeft(2, '0')}';
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
