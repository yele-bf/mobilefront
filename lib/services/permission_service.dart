import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:logger/logger.dart';

import '../widgets/app_localizations.dart';

/// État d'une permission du point de vue de l'app.
enum PermissionState {
  /// Accordée (ou sans objet, ex. notifications avant Android 13).
  granted,

  /// Refusée une fois — l'app peut redemander.
  denied,

  /// Refusée définitivement — seul un passage par les réglages système débloque.
  deniedForever,

  /// Non pertinente sur cette plateforme (ex. sur le web / Chrome).
  unavailable,
}

/// Les permissions Android que l'app gère, affichées dans la section
/// « Autorisations » des Réglages.
enum YelePermission {
  location,
  phoneState,
  notifications;

  /// Nom court affiché dans les Réglages (localisé fr/en, ISS-12).
  String get label {
    switch (this) {
      case YelePermission.location:
        return AppLocale.t('Localisation', 'Location');
      case YelePermission.phoneState:
        return AppLocale.t('Réseau mobile', 'Mobile network');
      case YelePermission.notifications:
        return AppLocale.t('Notifications', 'Notifications');
    }
  }

  /// Explication en langage simple de l'usage de la permission (localisée).
  String get description {
    switch (this) {
      case YelePermission.location:
        return AppLocale.t('Géolocalise chaque test sur la carte de couverture.',
            'Geo-locates each test on the coverage map.');
      case YelePermission.phoneState:
        return AppLocale.t(
            'Détecte l\'opérateur de la carte SIM et la technologie 2G/3G/4G/5G.',
            'Detects the SIM operator and the 2G/3G/4G/5G technology.');
      case YelePermission.notifications:
        return AppLocale.t(
            'Affiche la notification de la collecte de couverture en arrière-plan.',
            'Shows the notification of background coverage collection.');
    }
  }

  /// Autorisations obligatoires pour des mesures exploitables : la
  /// localisation (position sur la carte) et le réseau mobile (opérateur et
  /// technologie). Les notifications restent facultatives.
  bool get required {
    switch (this) {
      case YelePermission.location:
      case YelePermission.phoneState:
        return true;
      case YelePermission.notifications:
        return false;
    }
  }
}

/// Service centralisé de permissions Android.
///
/// Source de vérité de la section « Autorisations » des Réglages (IMP-04) :
/// tout passe par ici pour qu'un même état ne soit pas évalué différemment
/// selon l'endroit de l'app. Sur le web (Chrome), ces permissions système
/// n'existent pas : les états renvoyés sont alors [PermissionState.unavailable].
class PermissionService {
  final logger = Logger();

  static const MethodChannel _channel = MethodChannel('com.yele/telephony');

  bool get _native => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  // ── État courant ──────────────────────────────────────────────────────────

  /// État actuel d'une permission, sans demander quoi que ce soit.
  Future<PermissionState> check(YelePermission permission) async {
    switch (permission) {
      case YelePermission.location:
        return _checkLocation();
      case YelePermission.phoneState:
        return _checkPhoneState();
      case YelePermission.notifications:
        return _checkNotifications();
    }
  }

  /// État de toutes les permissions en parallèle.
  Future<Map<YelePermission, PermissionState>> checkAll() async {
    final results = await Future.wait(YelePermission.values.map(check));
    return {
      for (var i = 0; i < YelePermission.values.length; i++)
        YelePermission.values[i]: results[i],
    };
  }

  // ── Demande (récupère l'état après la demande) ─────────────────────────────

  /// Demande une permission et renvoie l'état final.
  Future<PermissionState> request(YelePermission permission) async {
    switch (permission) {
      case YelePermission.location:
        return _requestLocation();
      case YelePermission.phoneState:
        return _requestPhoneState();
      case YelePermission.notifications:
        return _requestNotifications();
    }
  }

  // ── Localisation (geolocator) ─────────────────────────────────────────────

  Future<PermissionState> _checkLocation() async {
    if (kIsWeb) return PermissionState.unavailable;
    try {
      final permission = await Geolocator.checkPermission();
      return _mapLocationPermission(permission);
    } catch (e) {
      logger.e('Erreur vérif permission localisation: $e');
      return PermissionState.unavailable;
    }
  }

  Future<PermissionState> _requestLocation() async {
    if (kIsWeb) return PermissionState.unavailable;
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      return _mapLocationPermission(permission);
    } catch (e) {
      logger.e('Erreur demande permission localisation: $e');
      return PermissionState.unavailable;
    }
  }

  PermissionState _mapLocationPermission(LocationPermission p) {
    switch (p) {
      case LocationPermission.always:
      case LocationPermission.whileInUse:
        return PermissionState.granted;
      case LocationPermission.deniedForever:
        return PermissionState.deniedForever;
      case LocationPermission.denied:
        return PermissionState.denied;
      case LocationPermission.unableToDetermine:
        return PermissionState.denied;
    }
  }

  /// Vrai si le service de localisation (GPS) du téléphone est activé.
  /// Sur le web, il n'existe pas de GPS système : on renvoie true pour que la
  /// section Autorisations reste simple (le web utilise la localisation IP).
  Future<bool> isGpsServiceEnabled() async {
    if (kIsWeb) return true;
    try {
      return await Geolocator.isLocationServiceEnabled();
    } catch (e) {
      logger.e('Erreur vérif service GPS: $e');
      return true;
    }
  }

  // ── État du téléphone / réseau mobile (canal natif) ───────────────────────

  Future<PermissionState> _checkPhoneState() async {
    if (!_native) return PermissionState.unavailable;
    try {
      final granted = await _channel.invokeMethod<bool>('hasPhonePermission');
      return (granted ?? false)
          ? PermissionState.granted
          : PermissionState.denied;
    } on MissingPluginException {
      return PermissionState.unavailable;
    } catch (e) {
      logger.e('Erreur vérif permission téléphone: $e');
      return PermissionState.unavailable;
    }
  }

  Future<PermissionState> _requestPhoneState() async {
    if (!_native) return PermissionState.unavailable;
    try {
      // Le canal déclenche la demande système et renvoie si elle est déjà
      // accordée. La réponse de la popup arrive de manière asynchrone : on
      // revérifie l'état réel juste après.
      await _channel.invokeMethod<bool>('requestPhonePermission');
      return await _checkPhoneState();
    } on MissingPluginException {
      return PermissionState.unavailable;
    } catch (e) {
      logger.e('Erreur demande permission téléphone: $e');
      return PermissionState.unavailable;
    }
  }

  // ── Notifications (Android 13+) ───────────────────────────────────────────

  Future<PermissionState> _checkNotifications() async {
    if (!_native) return PermissionState.unavailable;
    try {
      final granted =
          await _channel.invokeMethod<bool>('checkNotificationPermission');
      // Avant Android 13, la permission est accordée d'office (côté natif).
      return (granted ?? false)
          ? PermissionState.granted
          : PermissionState.denied;
    } on MissingPluginException {
      return PermissionState.unavailable;
    } catch (e) {
      logger.e('Erreur vérif permission notifications: $e');
      return PermissionState.unavailable;
    }
  }

  Future<PermissionState> _requestNotifications() async {
    if (!_native) return PermissionState.unavailable;
    try {
      await _channel.invokeMethod<bool>('requestNotificationPermission');
      return await _checkNotifications();
    } on MissingPluginException {
      return PermissionState.unavailable;
    } catch (e) {
      logger.e('Erreur demande permission notifications: $e');
      return PermissionState.unavailable;
    }
  }

  // ── Raccourcis pratiques ──────────────────────────────────────────────────

  /// Ouvre les réglages système de l'application (cas `deniedForever`).
  Future<void> openAppSettings() async {
    if (kIsWeb) return;
    try {
      await Geolocator.openAppSettings();
    } catch (e) {
      logger.e('Erreur ouverture réglages app: $e');
    }
  }
}
