import 'dart:io' show Platform;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:logger/logger.dart';

/// État réseau à un instant donné.
///
/// Distingue deux notions volontairement séparées :
///  - [connectionType] : par où passe Internet *maintenant* (WiFi ou mobile) ;
///  - [cellularTech] / [simOperator] : la techno et l'opérateur de la **SIM**,
///    lisibles même quand Internet passe par le WiFi.
class NetworkStatus {
  /// 'WiFi', 'Mobile', 'Ethernet', 'Aucune', 'Web' ou 'Inconnu'.
  final String connectionType;

  /// Techno radio mobile : '2G'/'3G'/'4G'/'5G', ou null si indisponible.
  final String? cellularTech;

  /// Nom de l'opérateur SIM (Android). null/n.d. sur iOS 16+ ou sans SIM.
  final String? simOperator;

  /// Emplacement 0-indexé de l'abonnement data actif sur Android.
  final int? dataSimSlot;

  /// Nombre d'abonnements SIM actifs sur Android.
  final int simCount;

  const NetworkStatus({
    required this.connectionType,
    this.cellularTech,
    this.simOperator,
    this.dataSimSlot,
    this.simCount = 0,
  });

  bool get isWifi => connectionType == 'WiFi';

  /// Badge réseau affiché et stocké : 'WiFi' en WiFi, sinon la techno mobile.
  String get networkBadge =>
      isWifi ? 'WiFi' : (cellularTech ?? connectionType);

  @override
  String toString() =>
      'NetworkStatus($connectionType, tech=$cellularTech, sim=$simOperator, '
      'slot=$dataSimSlot/$simCount)';
}

/// Service d'information réseau : type de connexion (connectivity_plus) +
/// opérateur SIM et techno radio (canal natif [_channel]).
class NetworkInfoService {
  final logger = Logger();
  final Connectivity _connectivity = Connectivity();

  static const MethodChannel _channel = MethodChannel('com.yele/telephony');

  // Repli MCC/MNC → nom d'opérateur, utilisé uniquement quand le nom natif est
  // vide. Le nom fourni par le système reste la source principale. Limité au
  // Burkina Faso (pays de déploiement) pour éviter des libellés erronés.
  static const Map<String, String> operatorsByMccMnc = {
    '61301': 'Telmob (Onatel)', // MCC 613 = Burkina Faso
    '61302': 'Orange Burkina Faso',
    '61303': 'Telecel Faso',
  };

  /// Récupère l'état réseau complet.
  Future<NetworkStatus> getStatus() async {
    if (kIsWeb) {
      return const NetworkStatus(connectionType: 'Web');
    }

    final connectionType = await _connectionType();

    String? cellularTech;
    String? simOperator;
    int? dataSimSlot;
    var simCount = 0;

    // Sur Android, on s'assure d'avoir la permission avant de lire.
    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod<bool>('requestPhonePermission');
      } catch (_) {
        // Permission non demandable : lecture en mode dégradé.
      }
    }

    try {
      final info = await _channel.invokeMapMethod<String, dynamic>('getTelephony');
      if (info != null) {
        cellularTech = (info['cellularTech'] as String?)?.trim();
        if (cellularTech != null && cellularTech.isEmpty) cellularTech = null;

        simOperator = (info['simOperator'] as String?)?.trim();
        if (simOperator == null || simOperator.isEmpty) {
          final mccMnc = (info['mccMnc'] as String?)?.trim();
          simOperator = _operatorFromMccMnc(mccMnc);
        }
        dataSimSlot = (info['dataSimSlot'] as num?)?.toInt();
        simCount = (info['simCount'] as num?)?.toInt() ?? 0;
      }
    } on MissingPluginException {
      // Canal natif absent (ex. tests) : on reste sur le type de connexion.
    } catch (e) {
      logger.w('Lecture téléphonie échouée: $e');
    }

    final status = NetworkStatus(
      connectionType: connectionType,
      cellularTech: cellularTech,
      simOperator: simOperator,
      dataSimSlot: dataSimSlot,
      simCount: simCount,
    );
    logger.i('📶 $status');
    return status;
  }

  Future<String> _connectionType() async {
    try {
      final results = await _connectivity.checkConnectivity();
      // connectivity_plus 6.x renvoie une liste ; on prend le lien actif.
      if (results.contains(ConnectivityResult.wifi)) return 'WiFi';
      if (results.contains(ConnectivityResult.mobile)) return 'Mobile';
      if (results.contains(ConnectivityResult.ethernet)) return 'Ethernet';
      if (results.contains(ConnectivityResult.none)) return 'Aucune';
      return 'Inconnu';
    } catch (e) {
      logger.e('Erreur détection connexion: $e');
      return 'Inconnu';
    }
  }

  String? _operatorFromMccMnc(String? mccMnc) {
    if (mccMnc == null || mccMnc.isEmpty) return null;
    return operatorsByMccMnc[mccMnc];
  }

  // ── Compatibilité : anciens appels ponctuels ────────────────────────────────

  /// Badge réseau (WiFi / 4G / …). Conserve l'ancienne signature.
  Future<String?> getNetworkType() async => (await getStatus()).networkBadge;
}
