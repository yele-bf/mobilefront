import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:logger/logger.dart';
import 'package:uuid/uuid.dart';

/// IMP-13 — Identifiant d'appareil stable et anonymisé.
///
/// Génère un UUID v4 aléatoire lors du premier lancement puis le réutilise à
/// l'identique : le même appareil reste traçable d'une mesure à l'autre (et
/// après réinstallation de l'application, la box Hive étant conservée).
///
/// Anonymat garanti : le UUID est un simple nombre aléatoire généré par
/// l'application. Aucune donnée privée (IMEI, numéro de série, compte,
/// empreinte matérielle) n'est lue ni transmise. Effacer les données de
/// l'application génère un nouveau UUID — c'est le comportement attendu pour
/// un identifiant sans données personnelles.
class DeviceIdentityService {
  DeviceIdentityService._();

  static final DeviceIdentityService instance = DeviceIdentityService._();

  final logger = Logger();
  static const String boxName = 'deviceIdentity';
  static const String keyUuid = 'deviceId';

  Box? _box;
  String? _cached;

  /// UUID de l'appareil : existant si déjà généré, sinon généré puis persisté.
  /// Retourne une chaîne vide en cas d'échec de stockage — mieux vaut envoyer
  /// un identifiant vide que de bloquer un envoi de mesure.
  Future<String> getUuid() async {
    if (_cached != null) return _cached!;
    try {
      if (kIsWeb) {
        await Hive.initFlutter();
      }
      _box ??= await Hive.openBox(boxName);
      final stored = _box!.get(keyUuid) as String?;
      if (stored != null && stored.isNotEmpty) {
        _cached = stored;
        return stored;
      }
      final uuid = const Uuid().v4();
      await _box!.put(keyUuid, uuid);
      _cached = uuid;
      logger.i('Nouvel UUID d\'appareil généré');
      return uuid;
    } catch (e) {
      logger.e('Erreur identité d\'appareil: $e');
      // Repli mémoire : identifiant stable pour la session en cours.
      return _cached ??= const Uuid().v4();
    }
  }
}
