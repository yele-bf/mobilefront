import 'package:flutter/material.dart';

import '../constants/config.dart';
import '../services/background_collection_service.dart';
import '../services/streaming_backend_setting.dart';
import '../theme/yele_theme.dart';
import '../widgets/yele_scaffold.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _useGps = true;

  final _collect = BackgroundCollectionService();
  CollectStatus _status = CollectStatus.unavailable;
  bool _busy = false;

  final _backendSetting = StreamingBackendSetting();
  String _streamBackend = streamingBackend; // moteur effectif affiché

  @override
  void initState() {
    super.initState();
    _refreshStatus();
    _loadBackend();
  }

  Future<void> _loadBackend() async {
    await _backendSetting.initialize();
    if (!mounted) return;
    setState(() => _streamBackend = _backendSetting.effectiveBackend);
  }

  Future<void> _refreshStatus() async {
    final status = await _collect.status();
    if (!mounted) return;
    setState(() => _status = status);
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
            _toggle('Utiliser le GPS',
                'Active/désactive la géolocalisation des tests', _useGps,
                (v) => setState(() => _useGps = v)),
            if (_collect.isSupported) ..._collectSection(),
            ..._debugSection(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
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

  // ── Débogage ─────────────────────────────────────────────────────────────

  /// Sélection à chaud du moteur du test de streaming : la surcharge est
  /// persistée et s'applique dès le prochain test, sans recompiler l'APK.
  /// Outil de test A/B terrain — les deux moteurs produisent le même résultat.
  List<Widget> _debugSection() {
    return [
      _section('Débogage'),
      _streamingBackendTile(),
    ];
  }

  Widget _streamingBackendTile() {
    final override = _backendSetting.hasOverride;
    return InkWell(
      onTap: _pickStreamingBackend,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0x11000000))),
        ),
        child: Row(
          children: [
            const Icon(Icons.science_outlined, size: 20, color: YeleColors.muted),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Moteur du test de streaming',
                      style: TextStyle(fontSize: 16, color: YeleColors.ink)),
                  const SizedBox(height: 2),
                  Text(
                    override
                        ? '$_streamBackend (surcharge runtime)'
                        : '$_streamBackend (défaut compilé)',
                    style: const TextStyle(fontSize: 13, color: YeleColors.muted),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 20, color: YeleColors.muted),
          ],
        ),
      ),
    );
  }

  Future<void> _pickStreamingBackend() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Moteur du test de streaming'),
        content: RadioGroup<String>(
          groupValue: _streamBackend,
          onChanged: (v) => Navigator.pop(ctx, v),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final c in StreamingBackendSetting.choices)
                RadioListTile<String>(
                  value: c,
                  title: Text(c == 'youtube'
                      ? 'YouTube (ABR dynamique)'
                      : 'HLS/DASH (qualité verrouillée)'),
                  subtitle: Text(
                    c == 'youtube'
                        ? 'Ce que sert l\'algorithme de YouTube — proche de l\'usage réel'
                        : 'Paliers servis tels que demandés — mesure reproductible',
                  ),
                ),
            const SizedBox(height: 4),
            Text('Défaut compilé : $streamingBackend',
                style:
                    const TextStyle(fontSize: 12, color: YeleColors.muted)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, ''),
            child: const Text('Retour au défaut'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
        ],
      ),
    );
    if (choice == null) return; // annulé
    if (choice.isEmpty) {
      await _backendSetting.resetToDefault();
    } else {
      await _backendSetting.setBackend(choice);
    }
    if (!mounted) return;
    setState(() => _streamBackend = _backendSetting.effectiveBackend);
    _snack('Moteur effectif dès le prochain test : $_streamBackend');
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
