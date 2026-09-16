import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:logger/logger.dart';

import 'settings_service.dart';
import 'usage_tracker_service.dart';

/// IMP-01 — Pilote du débit temps réel affiché dans la barre d'état.
///
/// Le service qui mesure et affiche le débit vit côté natif
/// (`ThroughputService` Kotlin) : il continue de fonctionner application
/// fermée et met à jour une notification de premier plan toutes les secondes.
///
/// Désactivé par défaut : c'est le seul élément de l'app qui consomme des
/// ressources en continu. L'utilisateur l'active dans Réglages →
/// « Suivi de consommation » ; s'il l'arrête depuis la notification
/// (« Arrêter »), [syncFromNative] resynchronise le réglage au retour de
/// l'application au premier plan.
class ThroughputService {
  final logger = Logger();

  static final ThroughputService instance = ThroughputService();

  static const MethodChannel _channel = MethodChannel('com.yele/telephony');

  bool get isSupported => !kIsWeb && Platform.isAndroid;

  /// Aligne le service natif sur le réglage utilisateur.
  /// Retourne false si le service n'a pas pu démarrer (notification refusée,
  /// restriction constructeur…).
  Future<bool> applySetting(bool enabled) async {
    if (!isSupported) return false;
    try {
      if (enabled) {
        // Volume déjà consommé ce mois : la notification de premier plan
        // affiche « Données utilisées » en plus du débit instantané.
        var usageBytes = 0;
        try {
          usageBytes = UsageTrackerService.instance.monthlyTotalBytes;
        } catch (_) {
          // Tracker indisponible (web/tests) : la pastille démarre à 0.
        }
        final ok = await _channel.invokeMethod<bool>(
          'startThroughputService',
          {'usageBytes': usageBytes},
        );
        if (!(ok ?? false)) return false;
        // Le démarrage est asynchrone côté système : on vérifie que le
        // service a réellement survécu (un crash de startForeground serait
        // sinon invisible ici).
        await Future.delayed(const Duration(milliseconds: 300));
        return await isNativeRunning();
      } else {
        await _channel.invokeMethod<bool>('stopThroughputService');
        return true;
      }
    } on MissingPluginException {
      return false;
    } catch (e) {
      logger.w('Pilotage du débit temps réel impossible: $e');
      return false;
    }
  }

  /// Le service tourne-t-il côté natif ?
  Future<bool> isNativeRunning() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('isThroughputRunning') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Si l'utilisateur a arrêté le service depuis la notification, le réglage
  /// persistant est resynchronisé (à appeler au retour au premier plan).
  Future<void> syncFromNative() async {
    if (!isSupported) return;
    final running = await isNativeRunning();
    if (!running && SettingsService.realtimeSpeedNotifier.value) {
      SettingsService().realtimeSpeed = false;
      return;
    }
    await resyncUsage();
  }

  /// Resynchronise la base « Données utilisées » de la pastille sur les
  /// compteurs du suivi de consommation (même source que l'écran
  /// Consommation) : corrige la divergence constatée entre la pastille et
  /// l'app — le service natif comptait tout le trafic en continu, l'app
  /// n'échantillonne qu'au premier plan.
  Future<void> resyncUsage() async {
    if (!isSupported) return;
    try {
      var usageBytes = 0;
      try {
        usageBytes = UsageTrackerService.instance.monthlyTotalBytes;
      } catch (_) {}
      await _channel.invokeMethod('resyncThroughputUsage',
          {'usageBytes': usageBytes});
    } on MissingPluginException {
      // Tests / canal absent : rien à faire.
    } catch (_) {
      // Service arrêté : pas grave.
    }
  }
}
