import 'package:flutter/material.dart';
import '../theme/yele_theme.dart';
import 'app_localizations.dart';

/// Tiroir de navigation latéral, repris de la maquette.
class YeleDrawer extends StatelessWidget {
  /// Route actuellement affichée (pour surligner l'entrée active).
  final String current;
  const YeleDrawer({super.key, required this.current});

  @override
  Widget build(BuildContext context) {
    // ISS-12 — libellés localisés (fr/en) du tiroir.
    final labels = <String, String>{
      '/full': AppLocale.t('Test complet', 'Full test'),
      '/speed': 'Speed test',
      '/browsing': AppLocale.t('Test de navigation', 'Browsing test'),
      '/streaming': AppLocale.t('Test de streaming', 'Streaming test'),
      '/history': AppLocale.t('Historique', 'History'),
      '/coverage': AppLocale.t('Cartes de couverture', 'Coverage maps'),
      '/settings': AppLocale.t('Réglages', 'Settings'),
    };

    return Drawer(
      backgroundColor: YeleColors.drawerBg,
      child: SafeArea(
        child: Column(
          children: [
            _header(),
            _item(context, Icons.hexagon_outlined, labels['/full']!, '/full'),
            _item(context, Icons.speed, labels['/speed']!, '/speed'),
            _item(context, Icons.public, labels['/browsing']!, '/browsing'),
            _item(context, Icons.play_circle_outline, labels['/streaming']!,
                '/streaming'),
            _item(context, Icons.history, labels['/history']!, '/history'),
            _item(context, Icons.map_outlined, labels['/coverage']!,
                '/coverage'),
            _item(context, Icons.settings, labels['/settings']!, '/settings'),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 21,
            backgroundColor: YeleColors.primary,
            child: Text('Ye',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Yélé',
                  style: TextStyle(
                      color: Colors.black,
                      fontSize: 17,
                      fontWeight: FontWeight.w700)),
              Text('Mesure de la qualité réseau',
                  style: TextStyle(
                      color: Colors.black54, fontSize: 12)),
            ],
          ),
          const Spacer(),
          const Text('v1.0.0',
              style: TextStyle(color: Colors.black54, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _item(BuildContext context, IconData icon, String label, String route) {
    final active = route == current;
    return InkWell(
      onTap: () {
        Navigator.of(context).pop(); // ferme le tiroir
        if (route != current) {
          Navigator.of(context).pushReplacementNamed(route);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.white10)),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 22,
                color: active ? YeleColors.primary : const Color(0xFFE7ECF4)),
            const SizedBox(width: 14),
            Text(label,
                style: TextStyle(
                    fontSize: 15,
                    color:
                        active ? YeleColors.primary : const Color(0xFFE7ECF4))),
          ],
        ),
      ),
    );
  }
}
