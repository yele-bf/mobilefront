import 'package:logger/logger.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart';
import '../constants/config.dart';

/// Résultat du garde-fou GPS avant de lancer un test (ISS-09).
enum GpsGateResult { ok, gpsDisabled, permissionDenied }

/// Service de localisation — GPS réel avec fallback IP
class LocationService {
  final logger = Logger();
  late final Dio _dio;

  LocationService() {
    _dio = Dio(
      BaseOptions(
        baseUrl: API_BASE_URL,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
      ),
    );
  }

  /// Demande la permission GPS et retourne la position réelle.
  /// Retourne null si l'utilisateur refuse ou si le GPS est indisponible.
  Future<Position?> requestGpsPosition() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        logger.w('Service GPS désactivé');
        return null;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          logger.w('Permission GPS refusée');
          return null;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        logger.w('Permission GPS refusée définitivement');
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      logger.i('📍 GPS: ${position.latitude}, ${position.longitude}');
      return position;
    } catch (e) {
      logger.e('Erreur GPS: $e');
      return null;
    }
  }

  /// Récupère la localisation basée sur l'IP publique (pour l'accueil)
  Future<LocationData?> getCurrentLocation() async {
    try {
      final response = await _dio.get('/getIP', queryParameters: {'isp': 'true'});

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;

        if (data['rawIspInfo'] != null) {
          final ispInfo = data['rawIspInfo'];
          final loc = (ispInfo['loc'] as String).split(',');

          final locationData = LocationData(
            latitude: double.tryParse(loc[0]) ?? 0.0,
            longitude: double.tryParse(loc[1]) ?? 0.0,
            city: ispInfo['city'] ?? 'Unknown',
            region: ispInfo['region'] ?? '',
            country: ispInfo['country'] ?? 'Unknown',
            countryName: _getCountryName(ispInfo['country'] ?? ''),
            operator: ispInfo['org']?.toString().split(' ').skip(1).join(' ') ?? 'Unknown',
            ip: ispInfo['ip'] ?? 'Unknown',
            timezone: ispInfo['timezone'] ?? 'UTC',
            processedString: data['processedString'] ?? '',
          );

          logger.i('🌍 Localisation IP: ${locationData.city}, ${locationData.countryName}');
          return locationData;
        }
      }
    } on DioException catch (e) {
      logger.e('❌ Erreur localisation IP: ${e.message}');
    } catch (e) {
      logger.e('❌ Erreur inattendue localisation: $e');
    }

    return null;
  }

  /// Récupère le nom de la localisation (ville, pays) depuis les coordonnées IP
  Future<String?> getLocationName(double lat, double lng) async {
    try {
      final location = await getCurrentLocation();
      if (location != null) {
        return '${location.city}, ${location.countryName}';
      }
    } catch (e) {
      logger.e('Erreur récupération nom localisation: $e');
    }
    return null;
  }

  Future<bool> isLocationServiceEnabled() async {
    return await Geolocator.isLocationServiceEnabled();
  }

  /// Garde-fou ISS-09 : vérifie que le test peut être lancé côté localisation.
  ///
  /// - **Web** : pas de GPS système (isLocationServiceEnabled → toujours vrai) et
  ///   les réglages système sont inaccessibles ; on ne bloque pas, le repli IP
  ///   reste utilisé (tests possibles depuis Chrome, comme avant).
  /// - **Natif (Android/iOS)** : GPS système éteint → [GpsGateResult.gpsDisabled] ;
  ///   permission refusée définitivement → [GpsGateResult.permissionDenied].
  ///   La permission « denied » simple déclenche ici la demande système.
  Future<GpsGateResult> ensureGpsForTest() async {
    if (kIsWeb) return GpsGateResult.ok;
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        logger.w('GPS système désactivé → test bloqué (ISS-09)');
        return GpsGateResult.gpsDisabled;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        logger.w('Permission localisation refusée → test bloqué (ISS-09)');
        return GpsGateResult.permissionDenied;
      }
      return GpsGateResult.ok;
    } catch (e) {
      // En cas d'erreur inattendue, on ne bloque pas le test : le comportement
      // d'origine (repli IP) reste la solution de repli.
      logger.e('Erreur garde-fou GPS: $e');
      return GpsGateResult.ok;
    }
  }

  /// Ouvre les réglages système de localisation (natif uniquement).
  Future<void> openLocationSettings() async {
    if (kIsWeb) return;
    try {
      await Geolocator.openLocationSettings();
    } catch (e) {
      logger.e('Erreur ouverture réglages localisation: $e');
    }
  }

  /// Ouvre les réglages de l'application (pour ré-autoriser la permission).
  Future<void> openAppSettings() async {
    if (kIsWeb) return;
    try {
      await Geolocator.openAppSettings();
    } catch (e) {
      logger.e('Erreur ouverture réglages app: $e');
    }
  }

  Future<dynamic> requestLocationPermission() async {
    return await requestGpsPosition();
  }

  String _getCountryName(String countryCode) {
    const countryNames = {
      'US': 'États-Unis',
      'GB': 'Royaume-Uni',
      'FR': 'France',
      'DE': 'Allemagne',
      'IT': 'Italie',
      'ES': 'Espagne',
      'CA': 'Canada',
      'AU': 'Australie',
      'JP': 'Japon',
      'CN': 'Chine',
      'IN': 'Inde',
      'BR': 'Brésil',
      'MX': 'Mexique',
      'SN': 'Sénégal',
      'MA': 'Maroc',
      'NG': 'Nigeria',
      'ZA': 'Afrique du Sud',
      'BF': 'Burkina Faso',
      'CI': "Côte d'Ivoire",
      'ML': 'Mali',
      'NE': 'Niger',
      'TG': 'Togo',
      'BJ': 'Bénin',
      'GH': 'Ghana',
      'KE': 'Kenya',
      'RW': 'Rwanda',
      'UG': 'Ouganda',
    };
    return countryNames[countryCode] ?? countryCode;
  }
}

class LocationData {
  final double latitude;
  final double longitude;
  final String city;
  final String region;
  final String country;
  final String countryName;
  final String operator;
  final String ip;
  final String timezone;
  final String processedString;

  LocationData({
    required this.latitude,
    required this.longitude,
    required this.city,
    required this.region,
    required this.country,
    required this.countryName,
    required this.operator,
    required this.ip,
    required this.timezone,
    required this.processedString,
  });

  @override
  String toString() => '$city, $countryName ($ip - $operator)';
}
