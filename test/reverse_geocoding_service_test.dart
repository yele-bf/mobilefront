import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yele/services/quartier_index.dart';
import 'package:yele/services/reverse_geocoding_service.dart';

/// Réponse Nominatim réelle capturée pour 12.3855, -1.5702 (Piis Zuure,
/// Tampouy, Ouagadougou — ligne « Adresse » produite dans l'historique).
const _bfResponse = {
  'place_id': 299843447,
  'osm_type': 'way',
  'osm_id': 28150631,
  'lat': '12.3855027',
  'lon': '-1.5701995',
  'category': 'highway',
  'type': 'residential',
  'addresstype': 'road',
  'name': 'Piis Zuure',
  'display_name': 'Piis Zuure, Tampouy, Ouagadougou, Kadiogo, Centre, Burkina Faso',
  'address': {
    'road': 'Piis Zuure',
    'suburb': 'Tampouy',
    'city': 'Ouagadougou',
    'county': 'Ouagadougou',
    'state_district': 'Kadiogo',
    'state': 'Centre',
    'country': 'Burkina Faso',
    'country_code': 'bf',
  },
};

/// Réponse type pour une position rurale sans route connue : Nominatim ne
/// renvoie pas de champ `address` détaillé exploitable.
const _ruralResponse = {
  'place_id': 1,
  'category': 'boundary',
  'type': 'administrative',
  'addresstype': 'village',
  'name': 'Ziniaré',
  'display_name': 'Ziniaré, Oubritenga, Plateau-Central, Burkina Faso',
  'address': {
    'village': 'Ziniaré',
    'county': 'Oubritenga',
    'state': 'Plateau-Central',
    'country': 'Burkina Faso',
    'country_code': 'bf',
  },
};

void main() {
  setUp(() {
    ReverseGeocodingService.resetForTest();
  });

  group('formatAddress (parsing Nominatim)', () {
    test(
        'exemple valide produit 06/11 : Rue, Quartier, Ville, Province, '
        'Region, Pays', () {
      final address = ReverseGeocodingService.formatAddress(_bfResponse);
      expect(
        address,
        'Piis Zuure, Tampouy, Ouagadougou, Kadiogo, Centre, Burkina Faso',
      );
    });

    test('zone rurale : pas de route ni de quartier → tirets, province via county', () {
      final address = ReverseGeocodingService.formatAddress(_ruralResponse);
      expect(
        address,
        '-, -, Ziniaré, Oubritenga, Plateau-Central, Burkina Faso',
      );
    });

    test('county recopie la commune : Province en tiret (jamais la ville en 4e place)', () {
      final address = ReverseGeocodingService.formatAddress({
        'address': {
          'road': 'Rue X',
          'city': 'Ouagadougou',
          'county': 'Ouagadougou', // recopie la commune : pas une province
        },
      });
      expect(address, 'Rue X, -, Ouagadougou, -, -, -');
    });

    test('champ quartier qui recopie la ville : Quartier en tiret', () {
      // NB du propriétaire 07/11 : Ouagadougou est une ville, jamais un
      // quartier — le suburb qui la recopie est ignoré.
      final address = ReverseGeocodingService.formatAddress({
        'address': {
          'suburb': 'Ouagadougou',
          'city': 'Ouagadougou',
          'state': 'Centre',
          'country': 'Burkina Faso',
        },
      });
      expect(address, '-, -, Ouagadougou, -, Centre, Burkina Faso');
    });

    test('repli display_name sans champ address', () {
      final address = ReverseGeocodingService.formatAddress({
        'display_name': 'Rue 12.146, Zone du Bois, Ouagadougou, Centre, Burkina Faso',
      });
      expect(address, 'Rue 12.146, Zone du Bois, Ouagadougou, Centre');
    });

    test('retourne null sans adresse exploitable', () {
      expect(ReverseGeocodingService.formatAddress({}), isNull);
    });
  });

  group('cacheKeyFor (arrondi 4 décimales)', () {
    test('arrondit à 4 décimales pour la clé de cache', () {
      expect(
        ReverseGeocodingService.cacheKeyFor(12.3855027, -1.5701995),
        '12.3855,-1.5702',
      );
    });

    test('deux points à ~10 m partagent la même clé', () {
      final a = ReverseGeocodingService.cacheKeyFor(12.38550, -1.57019);
      final b = ReverseGeocodingService.cacheKeyFor(12.38554, -1.57021);
      expect(a, equals(b));
    });
  });

  group('resolveAddress (réseau simulé via dioOverride)', () {
    late Dio dio;
    late List<String> requestedPaths;

    setUp(() {
      requestedPaths = [];
      dio = Dio(BaseOptions())
        ..interceptors.add(InterceptorsWrapper(
          onRequest: (options, handler) {
            requestedPaths.add(options.uri.toString());
            handler.resolve(Response<String>(
              requestOptions: options,
              statusCode: 200,
              data: jsonEncode(_bfResponse),
            ));
          },
        ));
    });

    test('retourne l\'adresse formatée pour des coordonnées de Ouaga', () async {
      final svc = ReverseGeocodingService.forTest(dio: dio);
      final address = await svc.resolveAddress(12.3855, -1.5702);
      expect(
        address,
        'Piis Zuure, Tampouy, Ouagadougou, Kadiogo, Centre, Burkina Faso',
      );
      // Une résolution = 1 requête (zoom 18), respectant le débit Nominatim.
      expect(requestedPaths, hasLength(1));
      expect(
          requestedPaths.first, contains('nominatim.openstreetmap.org/reverse'));
    });

    test('utilise le cache mémoire au deuxième appel (1 seule requête)',
        () async {
      final svc = ReverseGeocodingService.forTest(dio: dio);
      await svc.resolveAddress(12.3855, -1.5702);
      await svc.resolveAddress(12.3855, -1.5702);
      expect(requestedPaths, hasLength(1));
    });

    test('injecte le quartier embarqué quand OSM n\'en fournit pas', () async {
      // Réponse réelle zoom 18 pour 12.3815, -1.4856 : malgré le quartier
      // réel Zogona (validé terrain), OSM ne porte aucun champ quartier.
      const streetOnly = {
        'place_id': 298260283,
        'display_name': 'Rue 13.58, Ouagadougou, Kadiogo, Centre, Burkina Faso',
        'address': {
          'road': 'Rue 13.58',
          'city': 'Ouagadougou',
          'county': 'Ouagadougou',
          'state_district': 'Kadiogo',
          'state': 'Centre',
          'country': 'Burkina Faso',
        },
      };
      final streetDio = Dio(BaseOptions())
        ..interceptors.add(InterceptorsWrapper(
          onRequest: (options, handler) => handler.resolve(Response<String>(
            requestOptions: options,
            statusCode: 200,
            data: jsonEncode(streetOnly),
          )),
        ));

      // Base embarquée minimale : Zogona à ~700 m du point ; un autre
      // quartier volontairement plus loin (doit être ignoré).
      QuartierIndex.setInstanceForTest(QuartierIndex.withEntries(const [
        QuartierEntry(
            name: 'Zogona', lat: 12.37990, lon: -1.49090, kind: 'manual'),
        QuartierEntry(
            name: 'Kalgodin', lat: 12.35623, lon: -1.50336, kind: 'suburb'),
      ]));

      final svc = ReverseGeocodingService.forTest(dio: streetDio);
      final address = await svc.resolveAddress(12.3815, -1.4856);
      expect(
        address,
        'Rue 13.58, Zogona, Ouagadougou, Kadiogo, Centre, Burkina Faso',
      );
      QuartierIndex.setInstanceForTest(QuartierIndex.empty());
    });

    test('ne fabrique pas de quartier au-delà de 2 km', () {
      const streetOnly = {
        'address': {
          'road': 'Rue 13.58',
          'city': 'Ouagadougou',
          'country': 'Burkina Faso',
        },
      };
      QuartierIndex.setInstanceForTest(QuartierIndex.withEntries(const [
        QuartierEntry(
            name: 'Kalgodin', lat: 12.35623, lon: -1.50336, kind: 'suburb'),
      ]));
      // Le quartier le plus proche est à plus de 2 km : rien n'est injecté,
      // la ligne garde ses 6 places avec les tirets des absences.
      final merged = ReverseGeocodingService.injectMissingQuartier(
          Map<String, dynamic>.from(streetOnly), 12.3815, -1.4856);
      expect(
        ReverseGeocodingService.formatAddress(merged!),
        'Rue 13.58, -, Ouagadougou, -, -, Burkina Faso',
      );
      QuartierIndex.setInstanceForTest(QuartierIndex.empty());
    });

    test('ne requête pas hors du Burkina Faso', () async {
      final svc = ReverseGeocodingService.forTest(dio: dio);
      final address = await svc.resolveAddress(48.8566, 2.3522); // Paris
      expect(address, isNull);
      expect(requestedPaths, isEmpty);
    });

    test('retourne null sur erreur réseau sans lever', () async {
      final failingDio = Dio(BaseOptions())
        ..interceptors.add(InterceptorsWrapper(
          onRequest: (options, handler) {
            requestedPaths.add(options.uri.toString());
            handler.reject(DioException(
              requestOptions: options,
              type: DioExceptionType.connectionError,
              error: 'réseau coupé',
            ));
          },
        ));
      final svc = ReverseGeocodingService.forTest(dio: failingDio);
      final address = await svc.resolveAddress(12.3855, -1.5702);
      expect(address, isNull);
    });
  });
}
