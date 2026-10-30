import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:logger/logger.dart';

import '../constants/config.dart';

/// Compte connecté (IMP-03).
class Account {
  final String id;
  final String email;
  final String name;

  const Account({required this.id, required this.email, required this.name});

  factory Account.fromJson(Map<String, dynamic> j) => Account(
        id: (j['id'] ?? '').toString(),
        email: (j['email'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
      );

  Map<String, dynamic> toJson() => {'id': id, 'email': email, 'name': name};
}

/// Erreur lisible renvoyée à l'écran « Mon compte ».
class AccountException implements Exception {
  final String message;
  const AccountException(this.message);
  @override
  String toString() => message;
}

/// IMP-03 — Comptes utilisateurs : création, connexion, déconnexion, profil.
///
/// Le jeton de session et le compte sont gardés dans la boîte Hive `account`
/// (stockage privé de l'application). Chaque mesure faite en étant connecté
/// porte l'identifiant du compte, localement (historique isolé par compte)
/// et sur le serveur (jeton joint à l'envoi) : chaque compte retrouve ses
/// mesures, et seulement les siennes. Le compte reste facultatif.
class AccountService {
  static const String boxName = 'account';
  static const String _tokenKey = 'token';
  static const String _accountKey = 'account';

  static Box? _box;
  static final logger = Logger();

  /// Compte connecté, null si aucun : les écrans l'écoutent.
  static final ValueNotifier<Account?> current = ValueNotifier(null);

  /// Ouvre la boîte et recharge le compte mémorisé. Hive doit déjà être
  /// initialisé (LocalStorageService au démarrage, `Hive.init` en test).
  static Future<void> initialize() async {
    if (!(_box?.isOpen ?? false)) _box = await Hive.openBox(boxName);
    current.value = _load();
  }

  static Account? _load() {
    try {
      final j = _box?.get(_accountKey);
      if (j is Map && _box?.get(_tokenKey) != null) {
        return Account.fromJson(Map<String, dynamic>.from(j));
      }
    } catch (e) {
      logger.w('Compte mémorisé illisible : $e');
    }
    return null;
  }

  static String? get token => _box?.get(_tokenKey) as String?;

  /// Identifiant du compte connecté, null si l'utilisateur est anonyme.
  static String? get currentId => current.value?.id;

  /// En-tête d'authentification à joindre aux requêtes, ou vide.
  static Map<String, String> get authHeaders =>
      token == null ? const {} : {'Authorization': 'Bearer $token'};

  /// Mesures visibles dans l'historique : celles du compte connecté ou,
  /// déconnecté, celles faites sans compte.
  static bool isVisible(String? resultAccountId) =>
      resultAccountId == currentId;

  /// Mémorise une session ouverte (réponse de /api/auth/register ou login).
  @visibleForTesting
  static Future<Account> saveSession(String token, Account account) async {
    await _box?.put(_tokenKey, token);
    await _box?.put(_accountKey, account.toJson());
    current.value = account;
    return account;
  }

  /// Oublie la session (déconnexion, suppression du compte).
  @visibleForTesting
  static Future<void> clearSession() async {
    await _box?.delete(_tokenKey);
    await _box?.delete(_accountKey);
    current.value = null;
  }

  final Dio _dio = Dio(BaseOptions(
    baseUrl: API_BASE_URL,
    connectTimeout: const Duration(seconds: 30),
    // Le serveur gratuit peut mettre une minute à se réveiller.
    receiveTimeout: const Duration(seconds: 90),
  ));

  Future<Account> register(String email, String password, String name) =>
      _auth('/api/auth/register', {
        'email': email.trim(),
        'password': password,
        'name': name.trim(),
      });

  Future<Account> login(String email, String password) =>
      _auth('/api/auth/login', {'email': email.trim(), 'password': password});

  Future<Account> _auth(String path, Map<String, dynamic> body) async {
    try {
      final res = await _dio.post(path, data: body);
      final data = Map<String, dynamic>.from(res.data as Map);
      final account =
          Account.fromJson(Map<String, dynamic>.from(data['user'] as Map));
      return await saveSession(data['token'] as String, account);
    } on DioException catch (e) {
      throw AccountException(messageFor(e.response?.statusCode));
    }
  }

  Future<void> logout() async {
    try {
      await _dio.post('/api/auth/logout',
          options: Options(headers: authHeaders));
    } catch (_) {
      // Hors ligne : la session expirera seule côté serveur.
    }
    await clearSession();
  }

  Future<void> updateName(String name) async {
    try {
      final res = await _dio.put('/api/me',
          data: {'name': name.trim()}, options: Options(headers: authHeaders));
      final account =
          Account.fromJson(Map<String, dynamic>.from(res.data as Map));
      await _box?.put(_accountKey, account.toJson());
      current.value = account;
    } on DioException catch (e) {
      throw AccountException(messageFor(e.response?.statusCode));
    }
  }

  /// Supprime le compte. Ses mesures restent sur la carte, rendues anonymes.
  Future<void> deleteAccount() async {
    try {
      await _dio.delete('/api/me', options: Options(headers: authHeaders));
    } on DioException catch (e) {
      throw AccountException(messageFor(e.response?.statusCode));
    }
    await clearSession();
  }

  /// Nombre de mesures rattachées au compte sur le serveur.
  Future<int?> serverResultCount() async {
    try {
      final res = await _dio.get('/api/me/results',
          queryParameters: {'limit': 1},
          options: Options(headers: authHeaders));
      return ((res.data as Map)['total'] as num?)?.toInt();
    } catch (_) {
      return null;
    }
  }

  /// Message affiché pour un code de réponse du serveur.
  static String messageFor(int? status) {
    switch (status) {
      case 400:
        return "Vérifiez l'adresse e-mail et le mot de passe (8 caractères "
            'au moins).';
      case 401:
        return 'E-mail ou mot de passe incorrect.';
      case 409:
        return 'Un compte existe déjà avec cette adresse e-mail.';
      case 429:
        return 'Trop de tentatives. Réessayez dans quelques minutes.';
    }
    return 'Serveur injoignable. Vérifiez la connexion et réessayez.';
  }
}
