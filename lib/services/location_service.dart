
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:geolocator/geolocator.dart';
import '../constants/config.dart';

/// Service de localisation — GPS réel avec fallback IP
class LocationService {
  // ignore: avoid_print
  void _log(String msg) => print('[YELE-DIAG-LOC] $msg');
  void _logErr(String msg) => print('[YELE-DIAG-LOC-ERR] $msg');
  void _logWarn(String msg) => print('[YELE-DIAG-LOC-WARN] $msg');
  late final Dio _dio;

  LocationService() {
    _log('[DIAG-LOC] LocationService init, baseUrl=$API_BASE_URL');
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
        _logWarn('Service GPS désactivé');
        return null;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _logWarn('Permission GPS refusée');
          return null;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        _logWarn('Permission GPS refusée définitivement');
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      _log('📍 GPS: ${position.latitude}, ${position.longitude}');
      return position;
    } catch (e) {
      _logErr('Erreur GPS: $e');
      return null;
    }
  }

  /// Récupère la localisation basée sur l'IP publique (pour l'accueil)
  Future<LocationData?> getCurrentLocation() async {
    try {
      _log('[DIAG-LOC] getCurrentLocation: appel /getIP?isp=true vers $API_BASE_URL');
      final response = await _dio.get('/getIP', queryParameters: {'isp': 'true'});
      _log('[DIAG-LOC] getCurrentLocation: reponse HTTP ${response.statusCode}');
      _log('[DIAG-LOC] getCurrentLocation: data brute = ${response.data}');

      if (response.statusCode == 200 && response.data != null) {
        // Dio peut retourner une chaîne brute si le Content-Type n'est pas
        // application/json : on décode explicitement dans ce cas.
        final data = response.data is String
            ? jsonDecode(response.data as String) as Map<String, dynamic>
            : response.data as Map<String, dynamic>;

        if (data['rawIspInfo'] != null) {
          final ispInfo = data['rawIspInfo'];
          _log('[DIAG-LOC] getCurrentLocation: rawIspInfo.loc = "${ispInfo["loc"]}"');
          final locStr = (ispInfo['loc'] as String?) ?? '';
          if (locStr.isEmpty) {
            _logWarn('[DIAG-LOC] getCurrentLocation: rawIspInfo.loc est VIDE - fallback GPS/IP impossible');
          }
          final loc = locStr.split(',');

          final locationData = LocationData(
            latitude: double.tryParse(loc.isNotEmpty ? loc[0] : '') ?? 0.0,
            longitude: double.tryParse(loc.length > 1 ? loc[1] : '') ?? 0.0,
            city: ispInfo['city'] ?? 'Unknown',
            region: ispInfo['region'] ?? '',
            country: ispInfo['country'] ?? 'Unknown',
            countryName: _getCountryName(ispInfo['country'] ?? ''),
            operator: ispInfo['org']?.toString().split(' ').skip(1).join(' ') ?? 'Unknown',
            ip: ispInfo['ip'] ?? 'Unknown',
            timezone: ispInfo['timezone'] ?? 'UTC',
            processedString: data['processedString'] ?? '',
          );

          _log('[DIAG-LOC] getCurrentLocation: RESULTAT lat=${locationData.latitude} lng=${locationData.longitude} city=${locationData.city} country=${locationData.country} operator=${locationData.operator}');
          return locationData;
        } else {
          _logWarn('[DIAG-LOC] getCurrentLocation: rawIspInfo est null');
        }
      }
    } on DioException catch (e) {
      _logErr('[DIAG-LOC] getCurrentLocation ERREUR DIO: ${e.message} type=${e.type}');
    } catch (e) {
      _logErr('[DIAG-LOC] getCurrentLocation ERREUR INATTENDUE: $e');
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
      _logErr('Erreur récupération nom localisation: $e');
    }
    return null;
  }

  Future<bool> isLocationServiceEnabled() async {
    return await Geolocator.isLocationServiceEnabled();
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
