import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:yele/models/speed_test_result.dart';
import 'package:yele/services/account_service.dart';

/// IMP-03 — comptes utilisateurs et isolation des historiques.
void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('yele_account');
    Hive.init(tmp.path);
    await AccountService.initialize();
  });

  tearDown(() async {
    await AccountService.clearSession();
    await Hive.close();
    await tmp.delete(recursive: true);
  });

  const awa = Account(id: 'u-awa', email: 'awa@exemple.bf', name: 'Awa');
  const ali = Account(id: 'u-ali', email: 'ali@exemple.bf', name: 'Ali');

  test('sans session : anonyme, aucun en-tête d\'authentification', () {
    expect(AccountService.current.value, isNull);
    expect(AccountService.currentId, isNull);
    expect(AccountService.authHeaders, isEmpty);
  });

  test('la session est mémorisée et rechargée au lancement suivant',
      () async {
    await AccountService.saveSession('jeton-awa', awa);
    expect(AccountService.authHeaders, {'Authorization': 'Bearer jeton-awa'});

    await Hive.close();
    await AccountService.initialize();
    expect(AccountService.currentId, 'u-awa');
    expect(AccountService.current.value!.email, 'awa@exemple.bf');
  });

  test('chaque compte ne voit que ses mesures', () async {
    // Mesures d'Awa, d'Ali et sans compte sur le même téléphone.
    const ids = ['u-awa', 'u-ali', null];

    await AccountService.saveSession('jeton-awa', awa);
    expect(ids.where(AccountService.isVisible), ['u-awa']);

    await AccountService.saveSession('jeton-ali', ali);
    expect(ids.where(AccountService.isVisible), ['u-ali']);

    await AccountService.clearSession();
    expect(ids.where(AccountService.isVisible), [null]);
  });

  test('accountId survit au stockage Hive (index 59)', () async {
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(SpeedTestResultAdapter());
    }
    final box = await Hive.openBox<SpeedTestResult>('comptes');
    await box.put(
        'r',
        SpeedTestResult(
            downloadSpeed: 10,
            uploadSpeed: 2,
            ping: 40,
            jitter: 5,
            server: 's',
            accountId: 'u-awa'));
    await box.close();
    final relu = (await Hive.openBox<SpeedTestResult>('comptes')).get('r')!;
    expect(relu.accountId, 'u-awa');
  });

  test('messages d\'erreur lisibles', () {
    expect(AccountService.messageFor(401), contains('incorrect'));
    expect(AccountService.messageFor(409), contains('existe déjà'));
    expect(AccountService.messageFor(429), contains('Trop de tentatives'));
    expect(AccountService.messageFor(null), contains('injoignable'));
  });
}
