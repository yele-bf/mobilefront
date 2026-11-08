import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/config.dart';
import '../services/background_collection_service.dart';
import '../services/consent_service.dart';
// IMP-08 — Réglages de consommation : seuil mensuel d'alerte et débit
// temps réel, connectés au service de réglages persistant (Hive).
import '../services/settings_service.dart';
import '../services/throughput_service.dart';
import '../services/usage_tracker_service.dart'
    show UsageTrackerService, formatGb;
import '../services/permission_service.dart';
import '../theme/yele_theme.dart';
import '../widgets/app_localizations.dart';
import '../widgets/yele_scaffold.dart';

/// Réglages — reconstitution additive (réparation ISS-12, 08/11/2026) :
/// le PR #48 (IMP-02) avait réduit l'écran en maquette statique ; les
/// sections ISS-12 (langue / test / unité / style fonctionnels), les
/// autorisations Android et la collecte de couverture sont restaurées
/// depuis `709dd26`, SANS effacer les ajouts postérieurs (consommation
/// IMP-08, assistance IMP-02, conditions IMP-14).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  bool _useGps = true;

  // IMP-08 — État courant des réglages de consommation (chargés depuis la
  // box Hive ; conservés localement au cas où la box ne serait pas
  // prête — l'écran doit s'afficher sans crash, réglages par défaut).
  double _limitGb = 0;
  bool _realtimeSpeed = false;

  // ISS-12 — Collecte de couverture.
  final _collect = BackgroundCollectionService();
  CollectStatus _status = CollectStatus.unavailable;
  bool _busy = false;

  // ISS-12 — Autorisations du téléphone.
  final _perms = PermissionService();
  Map<YelePermission, PermissionState> _permStates = {};
  final Set<YelePermission> _busyPerms = {};
  bool _gpsOn = true;

  // ISS-12 — Réglages généraux fonctionnels et persistants (Hive).
  final _settings = SettingsService();
  AppLanguage _language = AppLanguage.system;
  DefaultTest _defaultTest = DefaultTest.full;
  SpeedUnit _speedUnit = SpeedUnit.auto;
  AppStyle _appStyle = AppStyle.green;

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
    _loadConsumptionSettings();
    // Reste synchronisé si le réglage change ailleurs (resynchro du débit
    // temps réel au retour au premier plan, par exemple).
    SettingsService.monthlyLimitGbNotifier.addListener(_onConsChanged);
    SettingsService.realtimeSpeedNotifier.addListener(_onConsChanged);
  }

  void _onLanguageChanged() {
    if (mounted) setState(() {});
  }

  void _loadSettings() {
    setState(() {
      _language = _settings.language;
      _defaultTest = _settings.defaultTest;
      _speedUnit = _settings.speedUnit;
      _appStyle = _settings.appStyle;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SettingsService.languageNotifier.removeListener(_onLanguageChanged);
    SettingsService.monthlyLimitGbNotifier.removeListener(_onConsChanged);
    SettingsService.realtimeSpeedNotifier.removeListener(_onConsChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Retour des réglages système : relire l'état des permissions.
    if (state == AppLifecycleState.resumed) {
      _refreshStatus();
      _refreshPermissions();
      _loadSettings();
      _loadConsumptionSettings();
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
  Widget build(BuildContext context) {
    // ISS-12 — libellés localisés de l'écran Réglages (fr/en).
    final title = AppLocale.t('Réglages', 'Settings');
    return YeleScaffold(
      title: title,
      route: '/settings',
      body: Container(
        color: YeleColors.panel,
        child: ListView(
          children: [
            _section(AppLocale.t('Général', 'General')),
            _choiceItem(
              AppLocale.t('Langue', 'Language'),
              _languageLabel(_language),
              _pickLanguage,
            ),
            _choiceItem(
              AppLocale.t(
                'Test par défaut au démarrage',
                'Default test at startup',
              ),
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
            _toggle(
              AppLocale.t('Utiliser le GPS', 'Use GPS'),
              AppLocale.t(
                'Active/désactive la géolocalisation des tests',
                'Toggles geolocation of the tests',
              ),
              _useGps,
              (v) => setState(() => _useGps = v),
            ),
            // IMP-08 — Réglages du suivi de consommation : le seuil
            // alimente la jauge, le bandeau « seuil dépassé » et la
            // notification native de l'écran Consommation ; le débit temps
            // réel pilote le service Android (pastille de la barre d'état).
            _section(AppLocale.t('Consommation', 'Data usage')),
            _actionItem(
              icon: Icons.data_usage,
              title: AppLocale.t(
                'Limite mensuelle de données',
                'Monthly data limit',
              ),
              sub: _limitLabel(),
              onTap: _pickLimit,
            ),
            _toggle(
              AppLocale.t('Débit temps réel', 'Real-time speed'),
              AppLocale.t(
                "Affiche le débit instantané dans la barre d'état Android",
                "Shows the instant speed in the Android status bar",
              ),
              _realtimeSpeed,
              (v) => _setRealtimeSpeed(v),
            ),
            ..._permissionsSection(),
            if (_collect.isSupported) ..._collectSection(),
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
                  // Imp08 v4 — Remise à zéro complète (revue du 08/11) :
                  // le seuil repart à zéro ET la consommation du mois est
                  // purgée — sans purge, le mois déjà accumulé (4,23 Go)
                  // dépassait tout nouveau seuil bas et l'alerte repartait
                  // aussitôt, invalidée d'avance. Sentinelle -1.0 pour
                  // distinguer la ligne du simple preset « Aucune alerte ».
                  InkWell(
                    onTap: () => Navigator.of(ctx).pop(-1.0),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.restart_alt,
                            size: 18,
                            color: YeleColors.primary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              "Réinitialiser la limite et la consommation "
                              "du mois",
                              style: TextStyle(
                                fontSize: 14.5,
                                color: YeleColors.ink,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
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
                          go == 0
                              ? AppLocale.t('Aucune alerte', 'No alert')
                              : AppLocale.t(
                                  '${formatGb(go)} Go',
                                  '${formatGb(go)} GB',
                                ),
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
                      labelText: AppLocale.t(
                        'Valeur manuelle (Go)',
                        'Manual value (GB)',
                      ),
                      hintText: AppLocale.t('Ex. 0,5', 'E.g. 0.5'),
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
                      () => errorText = AppLocale.t(
                        'Valeur invalide (0,01 à 1 000 Go)',
                        'Invalid value (0.01 to 1000 GB)',
                      ),
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
    if (chosen == null) return;
    // Sentinelle de la ligne « Réinitialiser la limite et la
    // consommation » : purge d'abord (total du mois = 0), puis seuil à
    // zéro — le notificateur du seuil repart d'un compteur nettoyé, donc
    // aucune alerte parasite au retour dans l'écran Consommation.
    if (chosen < 0) {
      try {
        await UsageTrackerService.instance.resetCurrentMonth();
        SettingsService().monthlyLimitGb = 0;
      } catch (_) {
        if (!mounted) return;
        _snack(
          "Réinitialisation impossible (suivi ou réglages indisponibles).",
        );
        return;
      }
      if (!mounted) return;
      setState(() => _limitGb = 0);
      _snack('Limite et consommation du mois remises à zéro.');
      return;
    }
    if (chosen == _limitGb) return;
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

  // ── Autorisations du téléphone ────────────────────────────────────────────

  /// Section groupant les autorisations Android requises par l'application :
  /// la localisation et le réseau mobile sont obligatoires, les notifications
  /// facultatives.
  List<Widget> _permissionsSection() {
    return [
      _section(AppLocale.t('Autorisations', 'Permissions')),
      Container(
        padding: const EdgeInsets.fromLTRB(18, 2, 18, 10),
        child: Text(
          AppLocale.t(
            "Ces autorisations s'appliquent à l'application Android installée "
                'sur le téléphone. Sur le web, aucune permission système '
                "n'est requise : la localisation utilise l'adresse IP.",
            'These permissions apply to the Android app installed on your '
                'phone. On the web, no system permission is required: '
                'location uses the IP address.',
          ),
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
    final gpsWarn =
        !web &&
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
                      child: Text(
                        p.label,
                        style: TextStyle(
                          fontSize: 16,
                          color: YeleColors.surface.ink,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
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
                Text(
                  p.description,
                  style: TextStyle(
                    fontSize: 13,
                    color: YeleColors.surface.muted,
                  ),
                ),
                if (deniedForever) ...[
                  const SizedBox(height: 5),
                  Text(
                    AppLocale.t(
                      'Refus définitif : touchez la bascule pour ouvrir '
                          "les réglages Android et autoriser.",
                      'Permanently denied: tap the switch to open Android '
                          'settings and allow.',
                    ),
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: YeleColors.danger,
                      height: 1.3,
                    ),
                  ),
                ],
                if (unavailable) ...[
                  const SizedBox(height: 5),
                  Text(
                    web
                        ? AppLocale.t(
                            "Non requise sur le web (la localisation utilise "
                                "l'adresse IP).",
                            'Not required on the web (location uses the IP '
                                'address).',
                          )
                        : AppLocale.t(
                            'Non requise sur cette plateforme.',
                            'Not required on this platform.',
                          ),
                    style: TextStyle(
                      fontSize: 12.5,
                      color: YeleColors.surface.muted,
                      height: 1.3,
                    ),
                  ),
                ],
                if (gpsWarn) ...[
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      const Icon(
                        Icons.warning_amber,
                        size: 14,
                        color: YeleColors.warn,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          AppLocale.t(
                            'GPS du téléphone éteint : les tests '
                                "resteront bloqués tant qu'il est désactivé.",
                            'Phone GPS off: tests stay blocked until it is '
                                'enabled.',
                          ),
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: YeleColors.warn,
                            height: 1.3,
                          ),
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
          'Désactiver « ${p.label} » ?',
          "Turn off '${p.label}'?",
        ),
        message: AppLocale.t(
          "Yélé ne peut pas retirer elle-même une autorisation déjà "
              "accordée à Android. La page « Applications → Yélé » va "
              "s'ouvrir : désactivez-y l'interrupteur « ${p.label} », puis "
              "revenez dans l'application.",
          "Yélé cannot revoke an already granted Android permission. The "
              "'Applications → Yélé' page will open: turn off "
              "'${p.label}' there, then come back to the app.",
        ),
      );
      if (go != true || !mounted) return;
      await _openSettings(p);
      return;
    }

    if (state == PermissionState.deniedForever) {
      final go = await _showPermissionDialog(
        title: AppLocale.t('Autoriser « ${p.label} » ?', "Allow '${p.label}'?"),
        message: AppLocale.t(
          "Android a mémorisé votre refus et ne réaffichera plus la "
              "demande. La page « Applications → Yélé » va s'ouvrir : "
              "autorisez-y « ${p.label} », puis revenez dans l'application.",
          "Android memorized your refusal and will not show the prompt "
              "again. The 'Applications → Yélé' page will open: allow "
              "'${p.label}' there, then come back to the app.",
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
            child: const Text('Annuler'),
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
      _snack(
        AppLocale.t(
          'Refus définitif : touchez la bascule pour ouvrir les réglages '
              'Android et autoriser.',
          'Permanently denied: tap the switch to open Android settings and '
              'allow.',
        ),
      );
    } else if (after == PermissionState.denied) {
      _snack(
        AppLocale.t(
          "Si la fenêtre système est affichée, accordez l'autorisation.",
          'If the system prompt is shown, grant the permission.',
        ),
      );
    }
  }

  Future<void> _openSettings(YelePermission p) async {
    await _perms.openAppSettings();
  }

  // ── Collecte de couverture ────────────────────────────────────────────────

  List<Widget> _collectSection() {
    return [
      _section(AppLocale.t('Collecte de couverture', 'Coverage collection')),
      _toggle(
        AppLocale.t('Contribuer en arrière-plan', 'Contribute in background'),
        AppLocale.t(
          'Relève la couverture réseau autour de vous, même application '
              'fermée',
          'Collects network coverage around you, even when the app is '
              'closed',
        ),
        _status.enabled,
        _busy ? null : _onToggleCollect,
      ),
      if (_status.enabled) ...[_intervalPicker(), _statusTile()],
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
    final started = await _collect.start(
      intervalMinutes: _status.intervalMinutes,
    );
    await _refreshStatus();
    if (!mounted) return;
    setState(() => _busy = false);

    if (!started) {
      // Le plus souvent : Android vient d'afficher la demande d'autorisation
      // de notification. Sans notification, le service est tué aussitôt.
      _snack(
        AppLocale.t(
          'Autorisez la notification, puis réactivez la collecte.',
          'Allow the notification, then re-enable collection.',
        ),
      );
    }
  }

  Future<bool?> _showConsentDialog() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          AppLocale.t(
            'Contribuer à la carte de couverture',
            'Contribute to the coverage map',
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppLocale.t(
                  "Yélé relèvera régulièrement, même lorsque l'application "
                      'est fermée :',
                  'Yélé will periodically collect, even when the app is '
                      'closed:',
                ),
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 10),
              _bullet(AppLocale.t('votre position', 'your position')),
              _bullet(
                AppLocale.t(
                  'la technologie du réseau (2G, 3G, 4G, 5G)',
                  'the network technology (2G, 3G, 4G, 5G)',
                ),
              ),
              _bullet(
                AppLocale.t(
                  "l'opérateur de votre carte SIM",
                  'your SIM card operator',
                ),
              ),
              _bullet(
                AppLocale.t('la puissance du signal', 'the signal strength'),
              ),
              const SizedBox(height: 12),
              Text(
                AppLocale.t(
                  "Aucun test de débit n'est effectué. Chaque relève "
                      'consomme environ 4 Ko, soit une dizaine de '
                      'mégaoctets par mois à la cadence de 15 minutes — '
                      'moins d\'un centième de ce que coûterait un test de '
                      'débit automatique.',
                  'No speed test is performed. Each collection uses about '
                      '4 KB, i.e. some ten megabytes per month at 15-minute '
                      'intervals — a hundredth of what an automatic speed '
                      'test would cost.',
                ),
                style: TextStyle(fontSize: 13, color: YeleColors.surface.muted),
              ),
              const SizedBox(height: 10),
              Text(
                AppLocale.t(
                  'Une notification permanente reste affichée tant que la '
                      "collecte est active. Vous pouvez l'arrêter à tout "
                      'moment, depuis cette notification ou depuis ces '
                      'réglages.',
                  'A permanent notification stays visible while collection '
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
            child: Text(AppLocale.t("J'accepte", 'I accept')),
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
          Text(
            AppLocale.t('Fréquence des relèves', 'Collection frequency'),
            style: TextStyle(fontSize: 16, color: YeleColors.surface.ink),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: BACKGROUND_INTERVAL_CHOICES.map((minutes) {
              final selected = minutes == _status.intervalMinutes;
              return ChoiceChip(
                label: Text(
                  minutes < 60 ? '$minutes min' : '${minutes ~/ 60} h',
                ),
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
            "Aucune relève envoyée pour l'instant",
            'No collection sent yet',
          )
        : AppLocale.t(
            'Dernière relève : ${_formatTime(last)}',
            'Last collection: ${_formatTime(last)}',
          );

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
                Text(
                  lastLabel,
                  style: TextStyle(fontSize: 14, color: YeleColors.surface.ink),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_status.count} ${AppLocale.t("relève", "collection")}'
                  '${_status.count > 1 ? 's' : ''} '
                  '${AppLocale.t('envoyée', 'sent')}'
                  '${_status.count > 1 ? 's' : ''}',
                  style: TextStyle(
                    fontSize: 13,
                    color: YeleColors.surface.muted,
                  ),
                ),
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
            children: const [
              Icon(Icons.battery_alert, size: 18, color: Color(0xFFEA580C)),
              SizedBox(width: 8),
              Text(
                'Collecte interrompue par le système',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFEA580C),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Votre téléphone a arrêté la collecte pour économiser la batterie. '
            "Pour qu'elle continue, ouvrez Paramètres → Applications → Yélé → "
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
    if (diff.inMinutes < 1) return AppLocale.t("à l'instant", 'just now');
    if (diff.inMinutes < 60) return '${diff.inMinutes} min';
    if (diff.inHours < 24) return '${diff.inHours} h';
    return '${t.day}/${t.month} ${t.hour}h${t.minute.toString().padLeft(2, '0')}';
  }

  void _snack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // ── Réglages généraux (ISS-12) ────────────────────────────────────────────

  String _languageLabel(AppLanguage v) {
    switch (v) {
      case AppLanguage.system:
        return AppLocale.t(
          'Auto (langue du téléphone)',
          'Auto (device language)',
        );
      case AppLanguage.fr:
        return 'Français';
      case AppLanguage.en:
        return 'English';
    }
  }

  String _defaultTestLabel(DefaultTest v) {
    switch (v) {
      case DefaultTest.full:
        return AppLocale.t('Test complet', 'Full test');
      case DefaultTest.speed:
        return AppLocale.t('Speed test', 'Speed test');
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
        return AppLocale.t('Blanc', 'White');
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
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: YeleColors.surface.ink,
                ),
              ),
            ),
            for (final (value, label) in choices)
              ListTile(
                title: Text(label),
                trailing: value == current
                    ? const Icon(
                        Icons.check,
                        color: YeleColors.primary,
                        size: 22,
                      )
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
    choices: [for (final v in AppLanguage.values) (v, _languageLabel(v))],
    onPick: (v) => _settings.language = v,
  );

  Future<void> _pickDefaultTest() => _pick<DefaultTest>(
    title: AppLocale.t(
      'Test par défaut au démarrage',
      'Default test at startup',
    ),
    current: _defaultTest,
    choices: [for (final v in DefaultTest.values) (v, _defaultTestLabel(v))],
    onPick: (v) {
      _settings.defaultTest = v;
      // Ce réglage décide de l'écran affiché au lancement de l'app : il
      // ne peut pas modifier rétroactivement l'écran courant.
      _snack(
        AppLocale.t(
          "Pris en compte au prochain démarrage de l'application.",
          'Applied the next time the app starts.',
        ),
      );
    },
  );

  Future<void> _pickSpeedUnit() => _pick<SpeedUnit>(
    title: AppLocale.t('Unité de débit', 'Speed unit'),
    current: _speedUnit,
    choices: [for (final v in SpeedUnit.values) (v, _speedUnitLabel(v))],
    onPick: (v) => _settings.speedUnit = v,
  );

  Future<void> _pickAppStyle() => _pick<AppStyle>(
    title: AppLocale.t('Style de fond', 'Background style'),
    current: _appStyle,
    choices: [for (final v in AppStyle.values) (v, _appStyleLabel(v))],
    onPick: (v) => _settings.appStyle = v,
  );

  // ── Assistance (FAQ + Contactez-nous) ────────────────────────────────────

  static const _supportEmail = 'support@yele.bf';
  // Numéro fictif (à remplacer par la vraie ligne support avant publication)
  static const _supportPhone = '+226 25 00 00 00';
  static const _supportPhoneRaw = '+22625000000';

  Widget _supportSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section(AppLocale.t('Assistance', 'Support')),
        _actionItem(
          icon: Icons.help_outline,
          title: AppLocale.t('FAQ', 'FAQ'),
          sub: AppLocale.t(
            "Questions fréquentes sur les mesures et l'application",
            'Frequently asked questions about measurements and the app',
          ),
          onTap: _openFaq,
        ),
        _actionItem(
          icon: Icons.mail_outline,
          title: AppLocale.t('Contactez-nous', 'Contact us'),
          sub: AppLocale.t(
            'Signaler un problème ou poser une question ($_supportEmail)',
            'Report an issue or ask a question ($_supportEmail)',
          ),
          onTap: _contactSupport,
        ),
        _actionItem(
          icon: Icons.phone_outlined,
          title: AppLocale.t('Appelez-nous', 'Call us'),
          sub: AppLocale.t(
            'Assistance téléphonique ($_supportPhone)',
            'Phone support ($_supportPhone)',
          ),
          onTap: _callSupport,
        ),
        // IMP-14 : relire les conditions acceptées au premier lancement, ou
        // retirer son accord.
        _actionItem(
          icon: Icons.policy_outlined,
          title: AppLocale.t("Conditions d'utilisation", 'Terms of use'),
          sub: AppLocale.t(
            'Données collectées, usage et vos droits',
            'Data collected, usage and your rights',
          ),
          onTap: () => Navigator.of(context).pushNamed('/conditions'),
        ),
        _actionItem(
          icon: Icons.block_outlined,
          title: AppLocale.t('Retirer mon accord', 'Withdraw my consent'),
          sub: AppLocale.t(
            'Les conditions vous seront présentées à nouveau',
            'The terms will be presented again',
          ),
          onTap: _withdrawConsent,
        ),
        _actionItem(
          icon: Icons.info_outline,
          title: AppLocale.t('À propos de Yélé', 'About Yélé'),
          sub: AppLocale.t(
            "Version de l'application et mentions légales",
            'App version and legal notices',
          ),
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
        _snack(
          AppLocale.t(
            "Aucune application e-mail trouvée. Écrivez à $_supportEmail",
            'No e-mail app found. Write to $_supportEmail',
          ),
        );
      }
    } catch (_) {
      _snack(
        AppLocale.t(
          "Aucune application e-mail trouvée. Écrivez à $_supportEmail",
          'No e-mail app found. Write to $_supportEmail',
        ),
      );
    }
  }

  Future<void> _callSupport() async {
    final uri = Uri(scheme: 'tel', path: _supportPhoneRaw);
    try {
      final ok = await launchUrl(uri).catchError((_) => false);
      if (!ok) {
        _snack(
          AppLocale.t(
            'Appel impossible. Appelez le $_supportPhone',
            'Call failed. Dial $_supportPhone',
          ),
        );
      }
    } catch (_) {
      _snack(
        AppLocale.t(
          'Appel impossible. Appelez le $_supportPhone',
          'Call failed. Dial $_supportPhone',
        ),
      );
    }
  }

  Future<void> _withdrawConsent() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          AppLocale.t('Retirer mon accord ?', 'Withdraw my consent?'),
        ),
        content: Text(
          AppLocale.t(
            "Aucun test ne sera possible tant que vous n'aurez pas accepté "
                "à nouveau les conditions d'utilisation.",
            'No test will be possible until you accept the terms again.',
          ),
          style: TextStyle(fontSize: 14, height: 1.5, color: YeleColors.ink),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(AppLocale.t('Annuler', 'Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(AppLocale.t('Retirer', 'Withdraw')),
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
        title: Text(AppLocale.t('À propos de Yélé', 'About Yélé')),
        content: Text(
          'Version 1.0.0\n\n'
          'Mesure de la qualité des réseaux mobiles au Burkina Faso',
          style: TextStyle(fontSize: 14, height: 1.5, color: YeleColors.ink),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(AppLocale.t('Fermer', 'Close')),
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

  // ── Éléments de liste ─────────────────────────────────────────────────────

  /// Ligne de réglage interactive : le sous-titre affiche la valeur courante
  /// et un tap ouvre le sélecteur (ISS-12).
  Widget _choiceItem(String title, String sub, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
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
                    style: TextStyle(
                      fontSize: 16,
                      color: YeleColors.surface.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sub,
                    style: TextStyle(
                      fontSize: 13,
                      color: YeleColors.surface.muted,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 22,
              color: YeleColors.surface.muted,
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String t) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 22, 18, 6),
    child: Text(
      t,
      style: const TextStyle(
        color: YeleColors.primary,
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
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
                  style: TextStyle(fontSize: 16, color: YeleColors.surface.ink),
                ),
                const SizedBox(height: 2),
                Text(
                  sub,
                  style: TextStyle(
                    fontSize: 13,
                    color: YeleColors.surface.muted,
                  ),
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
