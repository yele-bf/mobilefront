import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:hive_flutter/hive_flutter.dart';

import 'quartier_index.dart';

/// Géocodage inversé (coordonnées → adresse lisible) via OpenStreetMap
/// Nominatim, le même fournisseur que la recherche d'adresse du dashboard.
///
/// Politique d'usage Nominatim (https://operations.osmfoundation.org/policies/nominatim/) :
/// au plus 1 requête par seconde et un User-Agent applicatif identifiable.
/// Deux garde-fous sont implémentés :
///  - intervalle minimal de 1 s entre deux requêtes réseau ;
///  - cache mémoire + disque (Hive) : une même coordonnée n'est jamais
///    demandée deux fois, et les adresses survivent au redémarrage.
/// Le service ne requête que pour des coordonnées situées dans la bounding
/// box du Burkina Faso : en dehors, pas d'appel Nominatim du tout.
///
/// Quand Nominatim ne renvoie pas de quartier à ces coordonnées (cas fréquent
/// à Ouagadougou — ex. « Rue 13.58 » sans quartier), l'app le complète via
/// [QuartierIndex], la base embarquée de quartiers du Burkina : le choix
/// reste unique et fondé sur ces mêmes coordonnées.
class ReverseGeocodingService {
  ReverseGeocodingService._() : useDiskCache = true;

  static const String _boxName =
      'reverse_geocoding_cache_v3'; // v3 : règle « 6 places + tirets » du 07/11/2026
  static const String _userAgent =
      'YeleMobileApp/1.0 (qualite-reseaux Burkina Faso)';
  static const String _reverseUrl =
      'https://nominatim.openstreetmap.org/reverse';

  /// Bounding box Burkina Faso : en dehors, pas d'appel Nominatim.
  static const double _bfLatMin = 9.0;
  static const double _bfLatMax = 15.5;
  static const double _bfLonMin = -6.5;
  static const double _bfLonMax = 2.5;

  /// Débit max Nominatim : 1 requête/seconde.
  static const Duration _minRequestInterval = Duration(seconds: 1);

  /// Marqueur stocké en cache pour « Nominatim n'a pas d'adresse ici »,
  /// pour ne pas re-demande à chaque affichage du même test.
  static const String _noAddressSentinel = '\u0000no-address';

  static ReverseGeocodingService? _instance;
  static ReverseGeocodingService get instance =>
      _instance ??= ReverseGeocodingService._();

  /// Dernière date d'émission d'une requête réseau (toutes instances).
  static DateTime _lastRequestAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Chaîne de sérialisation : chaque requête attend la fin de la précédente.
  static Future<void> _lastRequestFuture = Future<void>.value();

  Dio? _dio;
  Box<String>? _cacheBox;
  bool _boxFailed = false;

  /// Cache disque activé ? Désactivé par [forTest] : sans Hive.init, openBox
  /// lève une erreur dont le Completer interne devient une erreur asynchrone
  /// non gérée (indomptable même par try/catch).
  final bool useDiskCache;

  /// Adresses résolues pendant la vie du process (réplète du cache Hive).
  final Map<String, String> _memoryCache = {};

  /// Résolutions en cours, indexées par clé de cache (dédoublonnage).
  final Map<String, Future<String?>> _inFlight = {};

  /// Dio injecté par les tests ; sinon initialisé paresseusement.
  @visibleForTesting
  Dio? dioOverride;

  Dio get _client => dioOverride ?? (_dio ??= _buildDio());

  /// Constructeur de test : cache disque désactivé par défaut (voir
  /// [useDiskCache]).
  ReverseGeocodingService.forTest({Dio? dio, bool? useDiskCache})
      : dioOverride = dio,
        useDiskCache = useDiskCache ?? false;

  static Dio _buildDio() => Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
        headers: {'User-Agent': _userAgent},
      ));

  /// Ouvre (une fois) la box Hive du cache disque.
  Future<Box<String>?> _box() async {
    if (!useDiskCache || _boxFailed) return _cacheBox;
    try {
      if (!Hive.isBoxOpen(_boxName)) {
        await Hive.openBox<String>(_boxName);
      }
      _cacheBox = Hive.box<String>(_boxName);
    } catch (_) {
      // Sans Hive disponible, on retombe sur le cache mémoire seul.
      _boxFailed = true;
    }
    return _cacheBox;
  }

  /// Clé de cache : coordonnées arrondies à 4 décimales (≈ 11 m) — même
  /// convention d'arrondi que l'affichage « Coord. » de l'historique.
  static String cacheKeyFor(double lat, double lon) =>
      '${lat.toStringAsFixed(4)},${lon.toStringAsFixed(4)}';

  static bool _inBurkinaFaso(double lat, double lon) =>
      lat >= _bfLatMin &&
      lat <= _bfLatMax &&
      lon >= _bfLonMin &&
      lon <= _bfLonMax;

  /// Retourne l'adresse lisible pour ces coordonnées, ou null si
  /// indisponible (pas d'adresse OSM connue, hors Burkina, erreur réseau).
  /// Ne lève jamais : l'appelant garde ses coordonnées en repli.
  Future<String?> resolveAddress(double lat, double lon) async {
    if (!_inBurkinaFaso(lat, lon)) return null;
    final key = cacheKeyFor(lat, lon);

    // 1. Cache mémoire.
    final mem = _memoryCache[key];
    if (mem != null) return _unwrap(mem);

    // 2. Cache disque.
    final box = await _box();
    final disk = box?.get(key);
    if (disk != null) {
      _memoryCache[key] = disk;
      return _unwrap(disk);
    }

    // 3. Requête en cours pour cette clé ? On la partage.
    final pending = _inFlight[key];
    if (pending != null) return pending;

    final future = _resolveFromNetwork(key, lat, lon);
    _inFlight[key] = future;
    try {
      return await future;
    } finally {
      _inFlight.remove(key);
    }
  }

  Future<String?> _resolveFromNetwork(String key, double lat, double lon) async {
    try {
      final json = await _enqueueRequest(lat, lon);
      // Quand OSM ne rattache pas de quartier au GPS (cas fréquent à
      // Ouagadougou), la base embarquée prend le quartier le plus proche.
      await QuartierIndex.instance.load();
      final String? address = formatAddress(
        // Non null par construction : json est toujours fourni, et
        // injectMissingQuartier ne rend null que si json est null.
        injectMissingQuartier(
            json ?? const <String, dynamic>{}, lat, lon)!,
      );
      if (address == null || address.isEmpty) {
        // Pas d'adresse OSM à cet endroit : on ne re-demandera pas.
        await _store(key, _noAddressSentinel);
        return null;
      }
      await _store(key, address);
      return address;
    } catch (_) {
      // Erreur réseau/parse : pas de mise en cache, nouvelle tentative
      // possible au prochain affichage.
      return null;
    }
  }

  /// Complète l'adresse d'OSM avec le composant Quartier si tous les champs
  /// quartier (`suburb`/`neighbourhood`/`quarter`/`city_district`) manquent
  /// : le nom vient alors de la base embarquée ([QuartierIndex.nearest]).
  /// Sans réponse OSM, l'injection ne s'applique pas (pas de quartier seul).
  @visibleForTesting
  static Map<String, dynamic>? injectMissingQuartier(
      Map<String, dynamic>? json, double lat, double lon) {
    if (json == null) return null;
    final address = json['address'];
    if (address is! Map<String, dynamic>) return json;
    const quartierKeys = ['suburb', 'neighbourhood', 'quarter', 'city_district'];
    final present = quartierKeys.any((k) =>
        address[k] is String && (address[k] as String).isNotEmpty);
    if (present) return json;
    final fromIndex = QuartierIndex.instance.nearest(lat, lon);
    if (fromIndex == null) return json;
    return {
      ...json,
      'address': {...address, 'suburb': fromIndex},
    };
  }

  /// Sérialise les requêtes réseau globalement : chaque appel attend la fin
  /// du précédent puis respecte l'intervalle minimal (1 req/s chez Nominatim).
  Future<Map<String, dynamic>?> _enqueueRequest(double lat, double lon) {
    final Future<Map<String, dynamic>?> myTurn =
        _lastRequestFuture.then((_) async {
      final since = DateTime.now().difference(_lastRequestAt);
      if (since < _minRequestInterval) {
        await Future<void>.delayed(_minRequestInterval - since);
      }
      _lastRequestAt = DateTime.now();
      return _doRequest(lat, lon);
    });
    // Le tour suivant ne doit pas hériter d'une erreur de celui-ci.
    _lastRequestFuture = myTurn.then<void>((_) {}, onError: (Object _) {});
    return myTurn;
  }

  /// Traduit une entrée de cache en résultat pour l'appelant : le marqueur
  /// « pas d'adresse » devient null (pas d'adresse OSM connue ici).
  static String? _unwrap(String cached) =>
      cached == _noAddressSentinel ? null : cached;

  Future<void> _store(String key, String value) async {
    _memoryCache[key] = value;
    final box = await _box();
    await box?.put(key, value);
  }

  Future<Map<String, dynamic>?> _doRequest(double lat, double lon) async {
    final response = await _client.get<String>(
      _reverseUrl,
      queryParameters: {
        'lat': lat.toStringAsFixed(6),
        'lon': lon.toStringAsFixed(6),
        'format': 'jsonv2',
        'zoom': 18,
        'addressdetails': 1,
        'accept-language': 'fr',
      },
    );

    if (response.statusCode != 200) {
      throw const FormatException('Nominatim: statut HTTP non 200');
    }
    final data = response.data;
    if (data == null || data.isEmpty) {
      throw const FormatException('Nominatim: réponse vide');
    }
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(data) as Map<String, dynamic>;
    } catch (_) {
      throw const FormatException('Nominatim: JSON invalide');
    }
    final error = json['error'];
    if (error != null) {
      // Nominatim renvoie {"error":"Unable to geocode"} quand rien n'est trouvé.
      return null;
    }
    return json;
  }

  /// Adresse à 6 places fixes (règle validée le 07/11/2026) :
  /// Rue, Quartier, Ville (la commune), Province, Région, Pays.
  /// Un composant indisponible s'affiche « - » : la ligne garde toujours
  /// 6 éléments séparés par « , » — jamais 4 ni 5. Règles :
  ///  - Province : `state_district` (ex. Kadiogo) ; le repli `county`
  ///    n'est retenu QUE s'il ne recopie pas la commune — le nom de la
  ///    commune n'est jamais une province (ex. county « Ouagadougou »)
  ///    → Province = « - ».
  ///  - Quartier : jamais le nom de la commune (Ouagadougou est une
  ///    ville) ; s'il recopie la ville → « - ».
  ///  - un composant déjà affiché plus tôt dans la ligne → « - »
  ///    (dédoublonnage, idem ancienne règle « redondant sauté »).
  /// Repli `display_name` conservé pour une réponse sans champ `address`,
  /// y compris retire le suffixe « …, Burkina Faso » (redondant).
  @visibleForTesting
  static String? formatAddress(Map<String, dynamic> json) {
    final address = json['address'];
    if (address is Map<String, dynamic>) {
      String? pick(List<String> keys) {
        for (final k in keys) {
          final v = address[k];
          if (v is String && v.isNotEmpty) return v;
        }
        return null;
      }

      final rue =
          pick(['road', 'pedestrian', 'footway', 'residential']);
      var quartier =
          pick(['suburb', 'neighbourhood', 'quarter', 'city_district']);
      final ville = pick(['city', 'town', 'municipality', 'village']);
      final district = pick(['state_district']);
      final county = pick(['county']);
      final region = pick(['state']);
      final pays = pick(['country']);

      // Le quartier est une division *interne* de la commune : si le champ
      // d'OSM recopie simplement la ville, il n'apporte rien → tiret.
      if (quartier != null && quartier == ville) quartier = null;
      // Province : le district est la vraie province ; county n'est un
      // repli valable que s'il ne recopie pas la commune.
      final province =
          district ?? (county != null && county != ville ? county : null);

      final slots = [rue, quartier, ville, province, region, pays];
      // Un composant déjà vu plus tôt dans la ligne → tiret.
      final seen = <String>{};
      final parts = slots
          .map((s) => (s != null && seen.add(s)) ? s : '-')
          .toList(growable: false);
      if (parts.any((p) => p != '-')) return parts.join(', ');
    }
    final displayName = json['display_name'];
    if (displayName is String && displayName.isNotEmpty) {
      var name = displayName;
      // Retire le suffixe « , Burkina Faso » (redondant dans l'app).
      name = name.replaceFirst(RegExp(r',\s*Burkina Faso\s*$'), '');
      return name;
    }
    return null;
  }

  /// Réinitialise l'état interne (tests uniquement).
  @visibleForTesting
  static void resetForTest() {
    _instance = null;
    _lastRequestAt = DateTime.fromMillisecondsSinceEpoch(0);
    _lastRequestFuture = Future<void>.value();
  }
}
