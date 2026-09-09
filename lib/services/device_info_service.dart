import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:logger/logger.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

class DeviceInfoService {
  final logger = Logger();
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  /// IMP-13/retour produit : « A059 » est un code constructeur (ro.product.model),
  /// pas le nom commercial. device_info_plus n'expose pas le nom marketing ;
  /// on maintient une table de correspondance pour les modèles courants du
  /// terrain (Burkina Faso), avec repli sur le code brut si inconnu.
  static const Map<String, String> _commercialNames = {
    // Samsung
    'SM-A057F': 'Samsung Galaxy A05s',
    'SM-A055F': 'Samsung Galaxy A05',
    'SM-A155F': 'Samsung Galaxy A15',
    'SM-A156E': 'Samsung Galaxy A15',
    'SM-A125F': 'Samsung Galaxy A12',
    'SM-A135F': 'Samsung Galaxy A13',
    'SM-A146B': 'Samsung Galaxy A14',
    'SM-A245F': 'Samsung Galaxy A24',
    'SM-A256E': 'Samsung Galaxy A24',
    'SM-A305F': 'Samsung Galaxy A30',
    'SM-A315F': 'Samsung Galaxy A31',
    'SM-A325F': 'Samsung Galaxy A32',
    'SM-A336E': 'Samsung Galaxy A33 5G',
    'SM-A346E': 'Samsung Galaxy A34 5G',
    'SM-A515F': 'Samsung Galaxy A51',
    'SM-A525F': 'Samsung Galaxy A52',
    'SM-A536E': 'Samsung Galaxy A53 5G',
    'SM-A546E': 'Samsung Galaxy A54 5G',
    'SM-A715F': 'Samsung Galaxy A71',
    'SM-S911B': 'Samsung Galaxy S23',
    'SM-S921B': 'Samsung Galaxy S24',
    // Tecno
    'TECNO-KG5p': 'Tecno Spark 8C',
    'TECNO-KG5n': 'Tecno Spark 8C',
    'TECNO-KF6k': 'Tecno Spark 10C',
    'TECNO-KF6j': 'Tecno Spark 10C',
    'TECNO-KJ6': 'Tecno Spark 20',
    'TECNO-BG6n': 'Tecno Pop 8',
    'TECNO-CH6n': 'Tecno Pop 7 Pro',
    'TECNO-CH7n': 'Tecno Pop 9',
    'TECNO-KC6': 'Tecno Camon 19',
    'TECNO-CK6n': 'Tecno Camon 20',
    // Infinix
    'Infinix-X6525': 'Infinix Hot 30i',
    'Infinix-X669': 'Infinix Hot 11 Play',
    'Infinix-X6819': 'Infinix Hot 12 Play',
    'Infinix-X6837': 'Infinix Hot 30 Play',
    'Infinix-X6511': 'Infinix Smart 6',
    'Infinix-X6517': 'Infinix Smart 7',
    'Infinix-X6528': 'Infinix Smart 8',
    // Nothing — A059 = Phone (3a), A059P = Phone (3a Pro)
    'A059': 'Nothing Phone (3a)',
    'A059P': 'Nothing Phone (3a) Pro',
    'A001': 'CMF Phone 1',
    'A024': 'Nothing Phone (3)',
    // itel
    'itel-A56': 'itel A56',
    'itel-S16': 'itel S16',
    'itel-A662L': 'itel A70',
    // Oppo / Xiaomi / Honor / Huawei
    'CPH2381': 'Oppo A17',
    'CPH2531': 'Oppo A18',
    '22120RN86G': 'Xiaomi Redmi 12C',
    '23106RP0CG': 'Xiaomi Redmi 13C',
    'M2010J19CG': 'Xiaomi Redmi 9A',
    '2201117TY': 'Xiaomi Redmi 10A',
    'LX1': 'Huawei P30 lite',
    'JNY-LX1': 'Huawei P30 lite',
    'DUA-L22': 'Huawei Y6 2018',
    'MED-LX9': 'Huawei Y6p',
    'JAT-L41': 'Honor 9X',
    'VNE-LX1': 'Huawei Y7 Prime 2018',
  };

  static const MethodChannel _channel = MethodChannel('com.yele/telephony');

  /// Nom commercial du téléphone, par ordre de fiabilité :
  /// 1. propriété système native `ro.product.marketname` (canal
  ///    `getDeviceMarketingName`) — la source exacte utilisée par les
  ///    constructeurs (Samsung, Xiaomi, Tecno, Nothing…) ;
  /// 2. table de correspondance locale (modèles courants du terrain) ;
  /// 3. « marque + modèle » (ex. « Nothing A059 ») — toujours plus lisible
  ///    qu'un code brut ;
  /// 4. code brut en dernier recours.
  Future<String?> getDeviceDisplayName() async {
    try {
      if (kIsWeb) {
        return await getDeviceModel();
      }
      if (Platform.isAndroid) {
        // 1. Nom marketing lu nativement (fonctionne hors app aussi).
        try {
          final marketing =
              await _channel.invokeMethod<String>('getDeviceMarketingName');
          if (marketing != null && marketing.trim().isNotEmpty) {
            return marketing.trim();
          }
        } on MissingPluginException {
          // Canal indisponible (tests, hot reload) : on poursuit.
        }

        final info = await _deviceInfo.androidInfo;
        final mapped = _commercialNames[info.model];
        if (mapped != null) return mapped;

        // 3. Marque + modèle : « Nothing A059 » plutôt que « A059 ».
        final brand = info.brand.trim();
        final model = info.model.trim();
        if (model.isEmpty) return brand.isEmpty ? null : brand;
        if (brand.isEmpty || model.toLowerCase().startsWith(brand.toLowerCase())) {
          return model;
        }
        return '$brand $model';
      }
      if (Platform.isIOS) {
        final info = await _deviceInfo.iosInfo;
        return info.name; // nom convivial attribué par iOS
      }
    } catch (e) {
      logger.e('Erreur nom d\'appareil: $e');
    }
    return null;
  }

  Future<String?> getDeviceModel() async {
    try {
      if (kIsWeb) {
        WebBrowserInfo webInfo = await _deviceInfo.webBrowserInfo;
        return webInfo.browserName.toString().split('.').last.toUpperCase();
      }
      if (Platform.isAndroid) {
        AndroidDeviceInfo androidInfo = await _deviceInfo.androidInfo;
        return androidInfo.model;
      } else if (Platform.isIOS) {
        IosDeviceInfo iosInfo = await _deviceInfo.iosInfo;
        return iosInfo.model;
      }
    } catch (e) {
      logger.e('Erreur récupération modèle: $e');
    }
    return null;
  }

  Future<String?> getOSVersion() async {
    try {
      if (kIsWeb) {
        WebBrowserInfo webInfo = await _deviceInfo.webBrowserInfo;
        return webInfo.platform;
      }
      if (Platform.isAndroid) {
        AndroidDeviceInfo androidInfo = await _deviceInfo.androidInfo;
        return 'Android ${androidInfo.version.release}';
      } else if (Platform.isIOS) {
        IosDeviceInfo iosInfo = await _deviceInfo.iosInfo;
        return 'iOS ${iosInfo.systemVersion}';
      }
    } catch (e) {
      logger.e('Erreur récupération OS version: $e');
    }
    return null;
  }

  Future<String?> getProcessorName() async {
    try {
      if (kIsWeb) {
        return 'Web CPU';
      }
      if (Platform.isAndroid) {
        AndroidDeviceInfo androidInfo = await _deviceInfo.androidInfo;
        return androidInfo.hardware; // CPU
      }
    } catch (e) {
      logger.e('Erreur récupération processeur: $e');
    }
    return null;
  }

  Future<int?> getTotalMemory() async {
    // totalMemory not available in device_info_plus
    logger.w('Total memory not available');
    return null;
  }

  Future<Map<String, dynamic>> getFullDeviceInfo() async {
    return {
      'model': await getDeviceModel(),
      'osVersion': await getOSVersion(),
      'processor': await getProcessorName(),
      'totalMemory': await getTotalMemory(),
    };
  }
}
