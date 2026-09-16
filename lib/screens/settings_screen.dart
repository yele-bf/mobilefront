import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/config.dart';
import '../services/background_collection_service.dart';
import '../services/permission_service.dart';
import '../services/settings_service.dart';
import '../services/throughput_service.dart';
import '../theme/yele_theme.dart';
import '../widgets/app_localizations.dart';
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

  /// ISS-12 — Réglages généraux fonctionnels et persistants (Hive).
  final _settings = SettingsService();
  AppLanguage _language = AppLanguage.system;
  DefaultTest _defaultTest = DefaultTest.full;
  SpeedUnit _speedUnit = SpeedUnit.auto;
  AppStyle _appStyle = AppStyle.green;

  /// IMP-01 — Suivi de consommation : seuil mensuel + débit temps réel.
  double _monthlyLimitGb = 0;
  bool _realtimeSpeed = false;

  /// Grand compteur en surimpression (taille de l'horloge) — voir
  /// [_toggleBigDisplay].
  bool _bigDisplay = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSettings();
    _refreshStatus();
    _refreshPermissions();
    // ISS-12 : la langue peut être changée depuis cet écran même — on
    // rafraîchit les libellés dès que le notificateur la change.
    SettingsService.languageNotifier.addListener(_onLanguageChanged);
  }

  void _onLanguageChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _readOverlayState() async {
    try {
      const channel = MethodChannel('com.yele/telephony');
      final on = await channel.invokeMethod<bool>('getThroughputOverlay') ?? false;
      if (!mounted) return;
      setState(() => _bigDisplay = on);
    } catch (_) {}
  }

  void _loadSettings() {
    setState(() {
      _language = _settings.language;
      _defaultTest = _settings.defaultTest;
      _speedUnit = _settings.speedUnit;
      _appStyle = _settings.appStyle;
      if (_usageSupported) {
        _monthlyLimitGb = _settings.monthlyLimitGb;
        _realtimeSpeed = _settings.realtimeSpeed;
        // État initial de l'overlay : lu dans les préférences natives.
        _readOverlayState();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SettingsService.languageNotifier.removeListener(_onLanguageChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Retour des réglages système : relire l'état des permissions.
    if (state == AppLifecycleState.resumed) {
      _refreshStatus();
      _refreshPermissions();
      _loadSettings();
      // IMP-01 : si l'utilisateur a arrêté le débit temps réel depuis la
      // notification, on resynchronise le réglage.
      ThroughputService.instance.syncFromNative();
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
    // ISS-12 — libellés localisés de l'écran Réglages (fr/en).
    final title = AppLocale.t('Réglages', 'Settings');
    return YeleScaffold(
      title: title,
      route: '/settings',
      body: Container(
        color: YeleColors.surface.panel,
        child: ListView(
          children: [
            _section(AppLocale.t('Général', 'General')),
            _choiceItem(
              AppLocale.t('Langue', 'Language'),
              _languageLabel(_language),
              _pickLanguage,
            ),
            _choiceItem(
              AppLocale.t('Test par défaut au démarrage',
                  'Default test at startup'),
              _defaultTestLabel(_defaultTest),
              _pickDefaultTest,
            ),
            _choiceItem(
              AppLocale.t('Unité de débit', 'Speed unit'),
              _speedUnitLabel(_speedUnit),
              _pickSpeedUnit,
            ),
            _choiceItem(
              AppLocale.t('Style de fond', 'Background style'),
              _appStyleLabel(_appStyle),
              _pickAppStyle,
            ),
            ..._permissionsSection(),
            if (_usageSupported) ..._usageSection(),
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
      _section(AppLocale.t('Autorisations', 'Permissions')),
      Container(
        padding: const EdgeInsets.fromLTRB(18, 2, 18, 10),
        child: Text(
          web
              ? AppLocale.t(
                  'Ces autorisations s\'appliquent à l\'application Android '
                  'installée sur le téléphone. Sur le web, aucune permission '
                  'système n\'est requise : la localisation utilise '
                  'l\'adresse IP.',
                  'These permissions apply to the Android app installed on '
                  'your phone. On the web, no system permission is required: '
                  'location uses your IP address.')
              : AppLocale.t(
                  'Localisation et Réseau mobile sont obligatoires pour des '
                  'mesures exploitables (position sur la carte, opérateur, '
                  'technologie). Notifications est facultative : elle sert '
                  'uniquement à la collecte de couverture en arrière-plan.',
                  'Location and Mobile network are required for meaningful '
                  'measurements (map position, operator, technology). '
                  'Notifications is optional: it is only used by background '
                  'coverage collection.'),
          style: TextStyle(fontSize: 13, color: YeleColors.surface.muted),
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
                          style: TextStyle(
                              fontSize: 16, color: YeleColors.surface.ink)),
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
                        required
                            ? AppLocale.t('Obligatoire', 'Required')
                            : AppLocale.t('Facultative', 'Optional'),
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
                    style: TextStyle(
                        fontSize: 13, color: YeleColors.surface.muted)),
                if (deniedForever) ...[
                  const SizedBox(height: 5),
                  Text(
                    AppLocale.t(
                      'Refus définitif : touchez la bascule pour ouvrir les '
                      'réglages Android et autoriser.',
                      'Permanently denied: tap the switch to open the Android '
                      'settings and allow it.',
                    ),
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
                        ? AppLocale.t(
                            'Non requise sur le web (la localisation utilise '
                            'l\'adresse IP).',
                            'Not required on the web (location uses the IP '
                            'address).')
                        : AppLocale.t(
                            'Non requise sur cette plateforme.',
                            'Not required on this platform.'),
                    style: TextStyle(
                        fontSize: 12.5,
                        color: YeleColors.surface.muted,
                        height: 1.3),
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
                          AppLocale.t(
                            'GPS du téléphone éteint : les tests resteront '
                            'bloqués tant qu\'il est désactivé.',
                            'Phone GPS is off: tests will stay blocked while '
                            'it is disabled.',
                          ),
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
        title: AppLocale.t(
            'Désactiver « ${p.label} » ?', 'Turn off "${p.label}"?'),
        message: AppLocale.t(
          'Yélé ne peut pas retirer elle-même une autorisation déjà accordée '
          'à Android. La page « Applications → Yélé » va s\'ouvrir : '
          'désactivez-y l\'interrupteur « ${p.label} », puis revenez dans '
          'l\'application.',
          'Yélé cannot revoke a permission already granted to Android. The '
          '"Apps → Yélé" page will open: turn off "${p.label}" there, then '
          'return to the app.',
        ),
      );
      if (go != true || !mounted) return;
      await _openSettings(p);
      return;
    }

    if (state == PermissionState.deniedForever) {
      final go = await _showPermissionDialog(
        title: AppLocale.t('Autoriser « ${p.label} » ?', 'Allow "${p.label}"?'),
        message: AppLocale.t(
          'Android a mémorisé votre refus et ne réaffichera plus la demande. '
          'La page « Applications → Yélé » va s\'ouvrir : autorisez-y '
          '« ${p.label} », puis revenez dans l\'application.',
          'Android remembered your denial and will not show the prompt again. '
          'The "Apps → Yélé" page will open: allow "${p.label}" there, then '
          'return to the app.',
        ),
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
            child: Text(AppLocale.t('Annuler', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(AppLocale.t('Ouvrir les réglages', 'Open settings')),
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
      _snack(AppLocale.t(
          'Refus définitif : touchez la bascule pour ouvrir les réglages '
          'Android et autoriser.',
          'Permanently denied: tap the switch to open the Android settings '
          'and allow it.'));
    } else if (after == PermissionState.denied) {
      _snack(AppLocale.t(
          'Si la fenêtre système est affichée, accordez l\'autorisation.',
          'If the system dialog is shown, grant the permission.'));
    }
  }

  Future<void> _openSettings(YelePermission p) async {
    await _perms.openAppSettings();
  }

  // ── Suivi de consommation ─────────────────────────────────────────────

  bool get _usageSupported =>
      !kIsWeb && !Platform.isIOS;

  List<Widget> _usageSection() {
    return [
      _section(AppLocale.t('Suivi de consommation', 'Data usage tracking')),
      // Seuil mensuel en Go (0 = alerte désactivée) — l'alerte locale est
      // levée par UsageTrackerService au franchissement.
      _choiceItem(
        AppLocale.t('Seuil mensuel', 'Monthly limit'),
        _monthlyLimitGb <= 0
            ? AppLocale.t('Aucune alerte', 'No alert')
            : '${AppLocale.t('Alerte à', 'Alert at')} '
                '${_formatGb(_monthlyLimitGb)} ${AppLocale.t('Go', 'GB')}',
        _pickMonthlyLimit,
      ),
      // Débit temps réel : désactivé par défaut — seul élément qui consomme
      // des ressources en continu (notification de premier plan + mesure/s).
      _toggle(
        AppLocale.t('Débit en temps réel', 'Real-time speed'),
        AppLocale.t(
            'Affiche le débit dans la barre d\'état, même application fermée '
            '(consomme un peu plus de batterie)',
            'Shows the speed in the status bar, even with the app closed '
            '(uses a bit more battery)'),
        _realtimeSpeed,
        _toggleRealtimeSpeed,
      ),
      if (_realtimeSpeed) ...[
        _choiceItem(
          AppLocale.t('Affichage en grand (compteur lisible)',
              'Large display (readable counter)'),
          _bigDisplay
              ? AppLocale.t('Activé — compteur à la taille de l\'horloge',
                  'On — counter the size of the clock')
              : AppLocale.t(
                  'Désactivé — compteur minuscule (limite Android)',
                  'Off — tiny counter (Android limit)'),
          _toggleBigDisplay,
        ),
      ],
    ];
  }

  /// Grand compteur en surimpression : la taille des icônes de notification
  /// est limitée par Android (~17 dp) — illisible. La surimpression dessine
  /// le débit à la taille de l'horloge. Nécessite la permission spéciale
  /// « Afficher par-dessus les autres applications ».
  Future<void> _toggleBigDisplay() async {
    const channel = MethodChannel('com.yele/telephony');
    if (!_bigDisplay) {
      try {
        final ok = await channel.invokeMethod<bool>('canDrawOverlays') ?? false;
        if (!ok) {
          await channel.invokeMethod('requestOverlayPermission');
          if (!mounted) return;
          _snack(AppLocale.t(
              'Autorisez « Afficher par-dessus les autres applications », '
              'puis revenez : le compteur s\'affichera en grand.',
              'Allow "Display over other apps", then come back: the '
              'counter will show up large.'));
        }
        const channel2 = MethodChannel('com.yele/telephony');
        await channel2.invokeMethod('setThroughputOverlay', {'enabled': true});
        if (!mounted) return;
        setState(() => _bigDisplay = true);
      } catch (_) {}
    } else {
      try {
        const channel3 = MethodChannel('com.yele/telephony');
        await channel3.invokeMethod('setThroughputOverlay', {'enabled': false});
      } catch (_) {}
      if (!mounted) return;
      setState(() => _bigDisplay = false);
    }
  }

  /// Formatage d'un seuil en Go : sans décimale si entier, sinon une décimale.
  String _formatGb(double gb) =>
      gb % 1 == 0 ? gb.toStringAsFixed(0) : gb.toStringAsFixed(1);

  /// Choix du seuil mensuel : valeurs prédéfinies ou saisie manuelle au
  /// clavier (retour utilisateur : les paliers fixes ne suffisent pas).
  Future<void> _pickMonthlyLimit() async {
    // Ordre voulu (retour utilisateur) : Aucune alerte, Saisir manuellement,
    // puis les paliers croissants. Le palier 100 Go a été retiré.
    const choices = <double>[1, 2, 5, 10, 20, 50];
    final gbUnit = AppLocale.t('Go', 'GB');
    Icon? checkIcon(bool selected) => selected
        ? const Icon(Icons.check, color: YeleColors.primary, size: 22)
        : null;
    final picked = await showModalBottomSheet<double>(
      context: context,
      builder: (ctx) => SafeArea(
        // Défilement obligatoire : sans lui, sur un petit écran la ligne
        // « Saisir manuellement… » était coupée et invisible (retour terrain).
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
              child: Text(
                  AppLocale.t('Seuil mensuel de données mobiles',
                      'Monthly mobile data limit'),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            // 1. Aucune alerte (valeur 0).
            ListTile(
              title: Text(AppLocale.t('Aucune alerte', 'No alert')),
              trailing: checkIcon(_monthlyLimitGb <= 0),
              onTap: () => Navigator.pop(ctx, 0.0),
            ),
            // 2. Saisie manuelle libre (0,1–9999 Go).
            ListTile(
              leading: const Icon(Icons.edit, size: 20),
              title: Text(_isPresetLimit(_monthlyLimitGb)
                  ? AppLocale.t('Saisir manuellement…', 'Enter manually…')
                  : '${AppLocale.t('Personnalisé', 'Custom')} : ${_formatGb(_monthlyLimitGb)} $gbUnit'),
              trailing: checkIcon(!_isPresetLimit(_monthlyLimitGb)),
              onTap: () async {
                Navigator.pop(ctx); // ferme la feuille de choix
                final manual = await _promptManualLimit();
                if (manual == null || manual == _monthlyLimitGb) return;
                if (!mounted) return;
                setState(() => _monthlyLimitGb = manual);
                _settings.monthlyLimitGb = manual;
              },
            ),
            // 3+. Paliers prédéfinis croissants.
            for (final gb in choices)
              ListTile(
                title: Text('${_formatGb(gb)} $gbUnit'),
                trailing: checkIcon(gb == _monthlyLimitGb),
                onTap: () => Navigator.pop(ctx, gb),
              ),
            const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (picked == null || picked == _monthlyLimitGb) return;
    setState(() => _monthlyLimitGb = picked);
    _settings.monthlyLimitGb = picked;
  }

  /// Saisie clavier libre du seuil mensuel (Go), avec validation : valeur
  /// décimale acceptée (virgule ou point), bornée à 0,1–9999 Go.
  Future<double?> _promptManualLimit() {
    final controller = TextEditingController(
      text: _monthlyLimitGb > 0 ? _formatGb(_monthlyLimitGb) : '',
    );
    final errorText = AppLocale.t(
        'Entrez un seuil entre 0,1 et 9999 Go.',
        'Enter a limit between 0.1 and 9999 GB.');
    return showDialog<double>(
      context: context,
      builder: (ctx) {
        String? error;
        void submit() {
          final parsed = _parseGb(controller.text);
          if (parsed == null) {
            // Rester dans le dialogue et signaler l'erreur plutôt que de
            // fermer silencieusement.
            error = errorText;
            (ctx as Element).markNeedsBuild();
          } else {
            Navigator.pop(ctx, parsed);
          }
        }

        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title:
                Text(AppLocale.t('Seuil mensuel (Go)', 'Monthly limit (GB)')),
            content: TextField(
              controller: controller,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                // Chiffres + un séparateur décimal + 2 décimales max.
                FilteringTextInputFormatter.allow(RegExp(r'^\d*[.,]?\d{0,2}')),
              ],
              decoration: InputDecoration(
                hintText: AppLocale.t('Ex. : 3,5', 'E.g. 3.5'),
                suffixText: AppLocale.t('Go', 'GB'),
                errorText: error,
              ),
              onSubmitted: (_) => submit(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(AppLocale.t('Annuler', 'Cancel')),
              ),
              FilledButton(
                onPressed: () {
                  final parsed = _parseGb(controller.text);
                  if (parsed == null) {
                    setDialogState(() => error = errorText);
                  } else {
                    Navigator.pop(ctx, parsed);
                  }
                },
                child: Text(AppLocale.t('Valider', 'OK')),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Analyse d'une valeur de seuil saisie au clavier : virgule ou point,
  /// bornée à 0,1–9999 Go. null si invalide.
  double? _parseGb(String raw) {
    final v = double.tryParse(raw.trim().replaceAll(',', '.'));
    if (v == null || v <= 0) return null;
    return v.clamp(0.1, 9999.0).toDouble();
  }

  /// Le seuil courant est-il un palier prédéfini (sinon : valeur
  /// personnalisée saisie manuellement) ?
  bool _isPresetLimit(double gb) =>
      gb <= 0 || const <double>[1, 2, 5, 10, 20, 50].contains(gb);

  Future<void> _toggleRealtimeSpeed(bool value) async {
    setState(() => _realtimeSpeed = value);
    _settings.realtimeSpeed = value;
    final ok = await ThroughputService.instance.applySetting(value);
    if (!ok && value && mounted) {
      // Permission de notification manquante : la popup système vient
      // d'être affichée (côté natif) et le service démarre AUTOMATIQUEMENT
      // dès que l'utilisateur accepte (onRequestPermissionsResult). Le
      // réglage reste ON : inutile de demander de réactiver à la main —
      // c'était précisément le bug signalé (réactivation sans effet).
      _snack(AppLocale.t(
          'Accordez la notification : le débit temps réel démarrera '
          'automatiquement.',
          'Grant the notification: real-time speed will start '
          'automatically.'));
    }
  }

  // ── Collecte de couverture ────────────────────────────────────────────────

  List<Widget> _collectSection() {
    return [
      _section(AppLocale.t('Collecte de couverture', 'Coverage collection')),
      _toggle(
        AppLocale.t('Contribuer en arrière-plan', 'Contribute in the background'),
        AppLocale.t(
            'Relève la couverture réseau autour de vous, même application fermée',
            'Reports network coverage around you, even with the app closed'),
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
      _snack(AppLocale.t(
          'Autorisez la notification, puis réactivez la collecte.',
          'Allow the notification, then re-enable collection.'));
    }
  }

  Future<bool?> _showConsentDialog() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocale.t(
            'Contribuer à la carte de couverture',
            'Contribute to the coverage map')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppLocale.t(
                  'Yélé relèvera régulièrement, même lorsque l\'application '
                  'est fermée :',
                  'Yélé will report regularly, even when the app is closed:',
                ),
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 10),
              _bullet(AppLocale.t('votre position', 'your location')),
              _bullet(AppLocale.t('la technologie du réseau (2G, 3G, 4G, 5G)',
                  'the network technology (2G, 3G, 4G, 5G)')),
              _bullet(AppLocale.t('l\'opérateur de votre carte SIM',
                  'your SIM card operator')),
              _bullet(AppLocale.t('la puissance du signal', 'the signal strength')),
              const SizedBox(height: 12),
              Text(
                AppLocale.t(
                  'Aucun test de débit n\'est effectué. Chaque relève consomme '
                  'environ 4 Ko, soit une dizaine de mégaoctets par mois à la '
                  'cadence de 15 minutes — moins d\'un centième de ce que '
                  'coûterait un test de débit automatique.',
                  'No speed test is performed. Each report uses about 4 KB, '
                  'i.e. roughly ten megabytes per month at the 15-minute '
                  'rate — far less than an automatic speed test would cost.',
                ),
                style: TextStyle(fontSize: 13, color: YeleColors.surface.muted),
              ),
              const SizedBox(height: 10),
              Text(
                AppLocale.t(
                  'Une notification permanente reste affichée tant que la '
                  'collecte est active. Vous pouvez l\'arrêter à tout moment, '
                  'depuis cette notification ou depuis ces réglages.',
                  'A permanent notification stays displayed while collection '
                  'is active. You can stop it at any time, from the '
                  'notification or from these settings.',
                ),
                style: TextStyle(fontSize: 13, color: YeleColors.surface.muted),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppLocale.t('Refuser', 'Decline')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(AppLocale.t('J\'accepte', 'I agree')),
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
          Text(AppLocale.t('Fréquence des relèves', 'Report frequency'),
              style: TextStyle(fontSize: 16, color: YeleColors.surface.ink)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: BACKGROUND_INTERVAL_CHOICES.map((minutes) {
              final selected = minutes == _status.intervalMinutes;
              return ChoiceChip(
                label: Text(minutes < 60
                    ? AppLocale.t('$minutes min', '$minutes min')
                    : '${minutes ~/ 60} h'),
                selected: selected,
                selectedColor: YeleColors.primary.withValues(alpha: .18),
                onSelected: _busy ? null : (_) => _changeInterval(minutes),
              );
            }).toList(),
          ),
          const SizedBox(height: 6),
          Text(
            backgroundIntervalLabel(_status.intervalMinutes),
            style: TextStyle(fontSize: 13, color: YeleColors.surface.muted),
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
        ? AppLocale.t(
            'Aucune relève envoyée pour l\'instant', 'No report sent yet')
        : '${AppLocale.t('Dernière relève :', 'Last report:')} '
            '${_formatTime(last)}';
    final countLabel = AppLocale.t(
        '${_status.count} relève${_status.count > 1 ? 's' : ''} '
        'envoyée${_status.count > 1 ? 's' : ''}',
        '${_status.count} report${_status.count > 1 ? 's' : ''} sent');

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
                    style:
                        TextStyle(fontSize: 14, color: YeleColors.surface.ink)),
                const SizedBox(height: 2),
                Text(countLabel,
                    style: TextStyle(
                        fontSize: 13, color: YeleColors.surface.muted)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            color: YeleColors.muted,
            tooltip: AppLocale.t('Actualiser', 'Refresh'),
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
            children: [
              const Icon(Icons.battery_alert, size: 18, color: Color(0xFFEA580C)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  AppLocale.t('Collecte interrompue par le système',
                      'Collection stopped by the system'),
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFEA580C)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            AppLocale.t(
              'Votre téléphone a arrêté la collecte pour économiser la '
              'batterie. Pour qu\'elle continue, ouvrez Paramètres → '
              'Applications → Yélé → Batterie, et choisissez '
              '« Sans restriction ».',
              'Your phone stopped collection to save battery. To keep it '
              'running, open Settings → Apps → Yélé → Battery, and choose '
              '"Unrestricted".',
            ),
            style: const TextStyle(fontSize: 13, height: 1.4),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime t) {
    final now = DateTime.now();
    final diff = now.difference(t);
    if (diff.inMinutes < 1) return AppLocale.t('à l\'instant', 'just now');
    if (diff.inMinutes < 60) {
      return AppLocale.t(
          'il y a ${diff.inMinutes} min', '${diff.inMinutes} min ago');
    }
    if (diff.inHours < 24) {
      return AppLocale.t('il y a ${diff.inHours} h', '${diff.inHours} h ago');
    }
    return AppLocale.t(
        '${t.day}/${t.month} à ${t.hour}h${t.minute.toString().padLeft(2, '0')}',
        '${t.day}/${t.month} at ${t.hour}:${t.minute.toString().padLeft(2, '0')}');
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // ── Réglages généraux (ISS-12) ────────────────────────────────────────────

  String _languageLabel(AppLanguage v) {
    switch (v) {
      case AppLanguage.system:
        return AppLocale.t('Auto (langue du téléphone)', 'Auto (phone language)');
      case AppLanguage.fr:
        return AppLocale.t('Français', 'French');
      case AppLanguage.en:
        return 'English';
    }
  }

  String _defaultTestLabel(DefaultTest v) {
    switch (v) {
      case DefaultTest.full:
        return AppLocale.t('Test complet', 'Full test');
      case DefaultTest.speed:
        return 'Speed test';
      case DefaultTest.streaming:
        return AppLocale.t('Test de streaming', 'Streaming test');
      case DefaultTest.browsing:
        return AppLocale.t('Test de navigation', 'Browsing test');
    }
  }

  String _speedUnitLabel(SpeedUnit v) {
    switch (v) {
      case SpeedUnit.auto:
        return AppLocale.t('Auto (Mb/s ou Kb/s)', 'Auto (Mb/s or Kb/s)');
      case SpeedUnit.mbps:
        return 'Mb/s';
      case SpeedUnit.kbps:
        return 'Kb/s';
    }
  }

  String _appStyleLabel(AppStyle v) {
    switch (v) {
      case AppStyle.green:
        return AppLocale.t('Blanc', 'Light');
      case AppStyle.dark:
        return AppLocale.t('Sombre', 'Dark');
    }
  }

  /// Ouvre une liste de choix et persiste immédiatement la valeur retenue.
  Future<void> _pick<T>({
    required String title,
    required List<(T, String)> choices,
    required T current,
    required void Function(T) onPick,
  }) async {
    final picked = await showModalBottomSheet<T>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
              child: Text(title,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: YeleColors.surface.ink)),
            ),
            for (final (value, label) in choices)
              ListTile(
                title: Text(label),
                trailing: value == current
                    ? const Icon(Icons.check,
                        color: YeleColors.primary, size: 22)
                    : null,
                onTap: () => Navigator.pop(ctx, value),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked == null || picked == current) return;
    onPick(picked);
    _loadSettings();
  }

  Future<void> _pickLanguage() => _pick<AppLanguage>(
        title: AppLocale.t('Langue', 'Language'),
        current: _language,
        choices: [
          for (final v in AppLanguage.values) (v, _languageLabel(v)),
        ],
        onPick: (v) => _settings.language = v,
      );

  Future<void> _pickDefaultTest() => _pick<DefaultTest>(
        title: AppLocale.t(
            'Test par défaut au démarrage', 'Default test at startup'),
        current: _defaultTest,
        choices: [
          for (final v in DefaultTest.values) (v, _defaultTestLabel(v)),
        ],
        onPick: (v) {
          _settings.defaultTest = v;
          // Ce réglage décide de l'écran affiché au lancement de l'app : il
          // ne peut pas modifier rétroactivement l'écran courant.
          _snack(AppLocale.t(
              'Pris en compte au prochain démarrage de l\'application.',
              'Applied the next time the app starts.'));
        },
      );

  Future<void> _pickSpeedUnit() => _pick<SpeedUnit>(
        title: AppLocale.t('Unité de débit', 'Speed unit'),
        current: _speedUnit,
        choices: [
          for (final v in SpeedUnit.values) (v, _speedUnitLabel(v)),
        ],
        onPick: (v) => _settings.speedUnit = v,
      );

  Future<void> _pickAppStyle() => _pick<AppStyle>(
        title: AppLocale.t('Style de fond', 'Background style'),
        current: _appStyle,
        choices: [
          for (final v in AppStyle.values) (v, _appStyleLabel(v)),
        ],
        onPick: (v) => _settings.appStyle = v,
      );

  // ── Éléments de liste ─────────────────────────────────────────────────────

  /// Ligne de réglage interactive : le sous-titre affiche la valeur courante
  /// et un tap ouvre le sélecteur (ISS-12).
  Widget _choiceItem(String title, String sub, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: YeleColors.surface.line)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style:
                          TextStyle(fontSize: 16, color: YeleColors.surface.ink)),
                  const SizedBox(height: 2),
                  Text(sub,
                      style: TextStyle(
                          fontSize: 13, color: YeleColors.surface.muted)),
                ],
              ),
            ),
            Icon(Icons.chevron_right,
                size: 22, color: YeleColors.surface.muted),
          ],
        ),
      ),
    );
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 22, 18, 6),
        child: Text(t,
            style: const TextStyle(
                color: YeleColors.primary,
                fontSize: 15,
                fontWeight: FontWeight.w700)),
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
                    style: TextStyle(fontSize: 16, color: YeleColors.surface.ink)),
                const SizedBox(height: 2),
                Text(sub,
                    style:
                        TextStyle(fontSize: 13, color: YeleColors.surface.muted)),
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
