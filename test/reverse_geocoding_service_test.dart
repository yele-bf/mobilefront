import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yele/services/reverse_geocoding_service.dart';

/// Réponse Nominatim réelle capturée pour 12.3855, -1.5702 (Piis Zuure,
/// Tampouy, Ouagadougou — voir la demande produit sur le champ « Coord. »).
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
    'country': 'Burke',
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
    test('exemple produit : Piis Zuure, Tampouy, Ouagadougou, Centre', () {
      final address = ReverseGeocodingService.formatAddress(_bfResponse);
      expect(address, 'Piis Zuure, Tampouy, Ouagadougou, Centre');
    });

    test('zone rurale : village sans route', () {
      final address = ReverseGeocodingService.formatAddress(_ruralResponse);
      expect(address, 'Ziniaré, Plateau-Central');
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
      expect(address, 'Piis Zuure, Tampouy, Ouagadougou, Centre');
      expect(requestedPaths, hasLength(1));
      expect(requestedPaths.single, contains('nominatim.openstreetmap.org/reverse'));
    });

    test('utilise le cache mémoire au deuxième appel (1 seule requête)', () async {
      final svc = ReverseGeocodingService.forTest(dio: dio);
      await svc.resolveAddress(12.3855, -1.5702);
      await svc.resolveAddress(12.3855, -1.5702);
      expect(requestedPaths, hasLength(1));
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
