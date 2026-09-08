import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:logger/logger.dart';

import '../constants/config.dart';
import 'device_identity_service.dart';

/// État de la collecte passive en arrière-plan.
class CollectStatus {
  /// Vrai si le service tourne effectivement en ce moment.
  final bool running;

  /// Vrai si l'utilisateur a activé la collecte. Peut différer de [running]
  /// quand le système a tué le service — c'est précisément le symptôme des
  /// gestionnaires de batterie agressifs.
  final bool enabled;

  final int intervalMinutes;

  /// Date de la dernière relève envoyée avec succès, null si aucune.
  final DateTime? lastCollectAt;

  /// Nombre de relèves envoyées depuis l'activation.
  final int count;

  const CollectStatus({
    required this.running,
    required this.enabled,
    required this.intervalMinutes,
    this.lastCollectAt,
    this.count = 0,
  });

  static const unavailable = CollectStatus(
    running: false,
    enabled: false,
    intervalMinutes: BACKGROUND_DEFAULT_INTERVAL_MIN,
  );

  /// L'utilisateur a demandé la collecte mais le service ne tourne pas : le
  /// système l'a très probablement arrêté.
  bool get wasKilled => enabled && !running;
}

/// Pilote la collecte passive de couverture réseau exécutée en natif.
///
/// La collecte elle-même vit dans un service Android de premier plan
/// ([SignalCollectorService] côté Kotlin) : elle survit à la fermeture de
/// l'application et ne s'arrête que sur demande explicite de l'utilisateur,
/// depuis les réglages ou depuis la notification permanente.
///
/// Cette classe ne fait que démarrer, arrêter et interroger ce service.
class BackgroundCollectionService {
  final logger = Logger();

  static const MethodChannel _channel = MethodChannel('com.yele/telephony');

  /// La collecte passive n'existe que sur Android : iOS n'autorise aucune
  /// exécution périodique garantie en arrière-plan.
  bool get isSupported => !kIsWeb && Platform.isAndroid;

  /// Démarre la collecte.
  ///
  /// Retourne false si Android a demandé l'autorisation de notification :
  /// l'appel doit alors être refait une fois l'utilisateur a répondu, sans
  /// quoi le service serait tué aussitôt lancé.
  Future<bool> start({int intervalMinutes = BACKGROUND_DEFAULT_INTERVAL_MIN}) async {
    if (!isSupported) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('startCollect', {
        'intervalMinutes': intervalMinutes,
        'apiBaseUrl': API_BASE_URL,
        // IMP-13 : l'UUID d'appareil accompagne le démarrage du service natif
        // pour que les relèves passives portent le même identifiant que les
        // tests actifs.
        'deviceId': await DeviceIdentityService.instance.getUuid(),
      });
      logger.i('Collecte passive démarrée (toutes les $intervalMinutes min)');
      return ok ?? false;
    } on MissingPluginException {
      return false;
    } catch (e) {
      logger.e('Démarrage de la collecte impossible: $e');
      return false;
    }
  }

  Future<void> stop() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<bool>('stopCollect');
      logger.i('Collecte passive arrêtée');
    } on MissingPluginException {
      // Canal absent (tests) : rien à arrêter.
    } catch (e) {
      logger.e('Arrêt de la collecte impossible: $e');
    }
  }

  Future<CollectStatus> status() async {
    if (!isSupported) return CollectStatus.unavailable;
    try {
      final info =
          await _channel.invokeMapMethod<String, dynamic>('getCollectStatus');
      if (info == null) return CollectStatus.unavailable;

      final lastMs = (info['lastCollectAt'] as num?)?.toInt() ?? 0;
      return CollectStatus(
        running: info['running'] as bool? ?? false,
        enabled: info['enabled'] as bool? ?? false,
        intervalMinutes: (info['intervalMinutes'] as num?)?.toInt() ??
            BACKGROUND_DEFAULT_INTERVAL_MIN,
        lastCollectAt:
            lastMs > 0 ? DateTime.fromMillisecondsSinceEpoch(lastMs) : null,
        count: (info['count'] as num?)?.toInt() ?? 0,
      );
    } on MissingPluginException {
      return CollectStatus.unavailable;
    } catch (e) {
      logger.w('Lecture de l\'état de collecte échouée: $e');
      return CollectStatus.unavailable;
    }
  }
}
