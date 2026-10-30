import 'package:flutter/material.dart';

import '../services/account_service.dart';
import '../theme/yele_theme.dart';
import '../widgets/yele_scaffold.dart';

/// IMP-03 — Mon compte : connexion ou création de compte, puis profil,
/// mesures du compte, déconnexion et suppression.
class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return YeleScaffold(
      title: 'Mon compte',
      route: '/account',
      body: Container(
        color: YeleColors.panel,
        child: ValueListenableBuilder<Account?>(
          valueListenable: AccountService.current,
          builder: (context, account, _) => account == null
              ? const _AuthForms()
              : _Profile(key: ValueKey(account.id), account: account),
        ),
      ),
    );
  }
}

class _AuthForms extends StatefulWidget {
  const _AuthForms();

  @override
  State<_AuthForms> createState() => _AuthFormsState();
}

class _AuthFormsState extends State<_AuthForms> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  bool _register = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final s = AccountService();
      if (_register) {
        await s.register(_email.text, _password.text, _name.text);
      } else {
        await s.login(_email.text, _password.text);
      }
    } on AccountException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(_register ? 'Créer un compte' : 'Se connecter',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: YeleColors.ink)),
        const SizedBox(height: 6),
        Text(
          'Facultatif : un compte permet de retrouver vos mesures et de '
          'séparer les historiques de plusieurs personnes sur un même '
          'téléphone. Sans compte, Yélé fonctionne normalement.',
          style: TextStyle(color: YeleColors.muted, fontSize: 13),
        ),
        const SizedBox(height: 16),
        if (_register)
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Nom (facultatif)'),
          ),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          decoration: const InputDecoration(labelText: 'E-mail'),
        ),
        TextField(
          controller: _password,
          obscureText: true,
          autofillHints: [
            _register ? AutofillHints.newPassword : AutofillHints.password
          ],
          decoration: InputDecoration(
              labelText: 'Mot de passe',
              helperText: _register ? '8 caractères au moins' : null),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_error!,
                style: const TextStyle(color: YeleColors.danger)),
          ),
        const SizedBox(height: 18),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: YeleColors.primary),
          onPressed: _busy ? null : _submit,
          child: Text(_busy
              ? 'Patientez…'
              : (_register ? 'Créer mon compte' : 'Se connecter')),
        ),
        TextButton(
          onPressed: _busy
              ? null
              : () => setState(() {
                    _register = !_register;
                    _error = null;
                  }),
          child: Text(
              _register ? "J'ai déjà un compte" : 'Pas de compte ? En créer un'),
        ),
      ],
    );
  }
}

class _Profile extends StatefulWidget {
  final Account account;
  const _Profile({super.key, required this.account});

  @override
  State<_Profile> createState() => _ProfileState();
}

class _ProfileState extends State<_Profile> {
  late final _name = TextEditingController(text: widget.account.name);
  int? _serverCount;

  @override
  void initState() {
    super.initState();
    AccountService().serverResultCount().then((n) {
      if (mounted) setState(() => _serverCount = n);
    });
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _saveName() async {
    try {
      await AccountService().updateName(_name.text);
      if (mounted) _snack('Profil enregistré.');
    } on AccountException catch (e) {
      if (mounted) _snack(e.message);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer le compte ?'),
        content: const Text(
            'Le compte et ses sessions sont supprimés. Vos mesures restent '
            'sur la carte, mais ne sont plus rattachées à vous.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: YeleColors.danger),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await AccountService().deleteAccount();
      if (mounted) _snack('Compte supprimé.');
    } on AccountException catch (e) {
      if (mounted) _snack(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.account;
    final initial = (a.name.isNotEmpty ? a.name : a.email);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: YeleColors.primary,
              child: Text(
                initial.isEmpty ? '?' : initial.substring(0, 1).toUpperCase(),
                style: const TextStyle(color: Colors.white, fontSize: 20),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(a.email,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: YeleColors.ink)),
            ),
          ],
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _name,
          decoration: InputDecoration(
            labelText: 'Nom affiché',
            suffixIcon: IconButton(
                icon: const Icon(Icons.check), onPressed: _saveName),
          ),
        ),
        const SizedBox(height: 18),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.cloud_done_outlined),
          title: Text('Mesures rattachées au compte',
              style: TextStyle(color: YeleColors.ink)),
          subtitle: Text(
              _serverCount == null
                  ? 'Chargement…'
                  : '$_serverCount mesure${_serverCount! > 1 ? 's' : ''} sur le serveur',
              style: TextStyle(color: YeleColors.muted)),
        ),
        Text(
          "L'historique de ce téléphone n'affiche que les mesures faites avec "
          'ce compte. Déconnecté, il affiche les mesures faites sans compte.',
          style: TextStyle(color: YeleColors.muted, fontSize: 13),
        ),
        const SizedBox(height: 22),
        OutlinedButton.icon(
          onPressed: () => AccountService().logout(),
          icon: const Icon(Icons.logout),
          label: const Text('Se déconnecter'),
        ),
        TextButton(
          onPressed: _delete,
          style: TextButton.styleFrom(foregroundColor: YeleColors.danger),
          child: const Text('Supprimer mon compte'),
        ),
      ],
    );
  }
}
