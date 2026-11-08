import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../constants/config.dart';
import '../models/speed_test_result.dart';
import '../services/account_service.dart';
import '../services/local_storage_service.dart';
import '../services/packet_loss_service.dart';
import '../services/reverse_geocoding_service.dart';
import '../services/yele_scoring_engine.dart';
import '../theme/yele_theme.dart';
import '../widgets/export_sheet.dart';
import '../widgets/yele_scaffold.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _storage = LocalStorageService();
  final _date = DateFormat('dd/MM/yy');
  final _time = DateFormat('HH:mm:ss');

  /// IMP-01 : volume lisible en Ko/Mo.
  static String _formatData(int kib) {
    if (kib >= 1024) return '${(kib / 1024).toStringAsFixed(1)} Mo';
    return '$kib Ko';
  }

  List<SpeedTestResult> _all = [];
  int _tab = 0; // 0 = Complet, 1 = Speed, 2 = Navigation, 3 = Streaming
  String? _expandedId;

  final ReverseGeocodingService _geo = ReverseGeocodingService.instance;

  /// Adresses résolues par géocodage inversé, indexées par clé de cache
  /// (coordonnées arrondies à 4 décimales). Valeur null = résolution en
  /// cours ; '' = aucune adresse OSM connue à cet endroit.
  final Map<String, String?> _addresses = {};

  /// Lance (une fois par coordonnée) la résolution de l'adresse quand un
  /// test est déplié. Le résultat alimente [_addresses] via setState.
  void _ensureAddress(SpeedTestResult r) {
    final lat = r.latitude;
    final lon = r.longitude;
    if (lat == null || lon == null || lat == 0 || lon == 0) return;
    final key = ReverseGeocodingService.cacheKeyFor(lat, lon);
    if (_addresses.containsKey(key)) return; // déjà résolu ou en cours
    _addresses[key] = null; // marque « résolution en cours »
    _geo.resolveAddress(lat, lon).then((addr) {
      if (!mounted) return;
      setState(() => _addresses[key] = addr ?? '');
    });
  }

  @override
  void initState() {
    super.initState();
    // IMP-03 : chaque compte ne voit que ses mesures ; déconnecté, on voit
    // celles faites sans compte.
    _all = _storage
        .getResultsSorted()
        .where((r) => AccountService.isVisible(r.accountId))
        .toList();
  }

  /// Classification dérivée des composantes réellement mesurées (le modèle
  /// ne sérialise pas la sélection de départ) :
  /// - **Complet** : streaming ET navigation mesurés (les deux familles
  ///   caractéristiques du test complet) ;
  /// - **Streaming** : streaming seul, sans navigation ;
  /// - **Navigation** : navigation seule, sans streaming ;
  /// - **Débit** : ni l'un ni l'autre (débit/latence uniquement).
  bool _isComplet(SpeedTestResult r) => r.hasStreamingTest && r.hasBrowsingTest;

  /// Note de qualité /100 dérivée des mesures réelles (transparente) :
  /// 60 pts max pour le download, 20 pour l'upload, 20 pour la latence.
  int _score(SpeedTestResult r) {
    final dl = (r.downloadSpeed / 50 * 60).clamp(0, 60);
    final ul = (r.uploadSpeed / 25 * 20).clamp(0, 20);
    final lat = r.ping <= 20
        ? 20.0
        : r.ping >= 300
        ? 0.0
        : (300 - r.ping) / 280 * 20;
    return (dl + ul + lat).round().clamp(0, 100);
  }

  /// Score affiché dans la colonne : **score ouvert en points** (IMP-12).
  ///
  /// La méthode retenue est celle de nPerf : un score composite ouvert, exprimé
  /// en points et non plafonné. L'indice /100 n'est qu'une lecture secondaire,
  /// affichée dans le dépli — il n'est jamais la valeur principale.
  ///
  /// Résultat complet → score global ; incomplet → sous-total des composantes
  /// réellement mesurées, suivi de « * » (jamais de points fictifs) ; résultat
  /// antérieur au scoring → ancienne note dérivée des débits et de la latence.
  String _scoreText(SpeedTestResult r) {
    if (r.scoringVersion == null) return '${_score(r)}';
    final global = r.scoreGlobal;
    if (global != null) return global.toStringAsFixed(0);
    final partial = r.scoreMeasuredSubtotal;
    return partial == null ? '—' : '${partial.toStringAsFixed(0)}*';
  }

  /// Détail du scoring ouvert : score global et composantes mesurées.
  List<Widget> _openScoreLines(
    SpeedTestResult r,
    Widget Function(String k, String v) line,
  ) {
    String pts(double v) => v.toStringAsFixed(0);
    final out = <Widget>[];
    final global = r.scoreGlobal;
    // Le référentiel (r.scoringVersion) est affiché par la carte détail
    // juste après le titre « Score YÉLÉ » (plan owner du 06/11) : ici,
    // seulement le score, l'indice et les composantes.
    if (global != null) {
      out.add(
        line(
          'Score ouvert',
          '${pts(global)} pts · ${YeleScoringEngine.classify(global).label}',
        ),
      );
      out.add(
        line(
          'Indice (lecture)',
          '${r.scoreGlobalOn100!.toStringAsFixed(0)}/100',
        ),
      );
    } else {
      final sub = r.scoreMeasuredSubtotal;
      out.add(
        line(
          'Score ouvert',
          sub == null
              ? 'non mesuré'
              : 'incomplet · ${pts(sub)} pts mesurés '
                    '(composantes absentes exclues)',
        ),
      );
    }
    if (r.scoreDownload != null) {
      out.add(line('Download', '${pts(r.scoreDownload!)} pts'));
    }
    if (r.scoreUpload != null) {
      out.add(line('Upload', '${pts(r.scoreUpload!)} pts'));
    }
    if (r.scorePingJitter != null) {
      out.add(line('Latence', '${pts(r.scorePingJitter!)} pts'));
    }
    if (r.scoreBrowsing != null) {
      out.add(line('Navigation', '${pts(r.scoreBrowsing!)} pts'));
    }
    if (r.scoreStreaming != null) {
      out.add(line('Streaming', '${pts(r.scoreStreaming!)} pts'));
    }
    return out;
  }

  List<SpeedTestResult> get _filtered => _all.where((r) {
    switch (_tab) {
      case 0:
        return _isComplet(r); // streaming + navigation mesurés
      case 1:
        return !r.hasStreamingTest && !r.hasBrowsingTest; // débit seul
      case 2:
        return r.hasBrowsingTest && !r.hasStreamingTest; // navigation
      default:
        return r.hasStreamingTest && !r.hasBrowsingTest; // streaming
    }
  }).toList();

  @override
  Widget build(BuildContext context) {
    final pts = _all
        .where((r) => (r.latitude ?? 0) != 0 && (r.longitude ?? 0) != 0)
        .toList();
    final list = _filtered;
    return YeleScaffold(
      title: 'Historique',
      route: '/history',
      body: Column(
        children: [
          SizedBox(height: 200, child: _map(pts)),
          _tabs(),
          _header(),
          Expanded(
            child: list.isEmpty
                ? const Center(
                    child: Text(
                      'Aucun test pour cet onglet.',
                      style: TextStyle(color: Color(0xFF6B7689)),
                    ),
                  )
                : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (_, i) => _row(list[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _map(List<SpeedTestResult> pts) {
    final center = pts.isNotEmpty
        ? LatLng(pts.first.latitude!, pts.first.longitude!)
        : const LatLng(12.366, -1.527);
    return FlutterMap(
      options: MapOptions(initialCenter: center, initialZoom: 12),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.yele',
        ),
        MarkerLayer(
          markers: [
            for (final r in pts)
              Marker(
                point: LatLng(r.latitude!, r.longitude!),
                width: 32,
                height: 32,
                child: const Icon(
                  Icons.location_on,
                  color: Color(0xFF16557E),
                  size: 28,
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _tabs() {
    Widget tab(String label, int index) {
      final active = _tab == index;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() {
            _tab = index;
            _expandedId = null;
          }),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 15),
            decoration: BoxDecoration(
              color: YeleColors.panel2,
              border: Border(
                bottom: BorderSide(
                  color: active ? YeleColors.primary : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 11,
                letterSpacing: 0.2,
                color: active ? YeleColors.ink : const Color(0xFF5A6577),
              ),
            ),
          ),
        ),
      );
    }

    // Quatre onglets alignés horizontalement, tous visibles dès l'ouverture
    // (aucun scroll latéral) — police réduite pour tenir dans la largeur.
    return Row(
      children: [
        tab('COMPLET', 0),
        tab('SPEED', 1),
        tab('NAVIGATION', 2),
        tab('STREAMING', 3),
      ],
    );
  }

  Widget _header() {
    Widget h(IconData icon, String label, int flex) {
      return Expanded(
        flex: flex,
        child: Column(
          children: [
            Icon(icon, size: 18, color: YeleColors.field),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: YeleColors.field,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        color: YeleColors.surface.panel,
        border: Border(bottom: BorderSide(color: YeleColors.surface.line)),
      ),
      child: Row(
        children: [
          h(Icons.network_check, 'Type', 12),
          h(Icons.public, 'ISP / Réseau', 20),
          h(Icons.calendar_today, 'Date', 13),
          h(Icons.hourglass_bottom, 'Débits', 14),
          h(Icons.workspace_premium, 'Score', 12),
        ],
      ),
    );
  }

  Color _typeColor(String? net) {
    final n = (net ?? '').toUpperCase();
    if (n.contains('WIFI') || n.contains('WI-FI')) return YeleColors.primary;
    if (n.contains('5G')) return YeleColors.g5;
    if (n.contains('4G')) return YeleColors.g4;
    if (n.contains('3G')) return YeleColors.g3;
    if (n.contains('2G')) return YeleColors.g2;
    return YeleColors.muted; // Inconnu / défaut
  }

  /// Icône reflétant le type de connexion réellement utilisé pour le test.
  IconData _typeIcon(String? net) {
    final n = (net ?? '').toUpperCase();
    if (n.contains('WIFI') || n.contains('WI-FI')) return Icons.wifi;
    if (n.contains('2G') ||
        n.contains('3G') ||
        n.contains('4G') ||
        n.contains('5G')) {
      return Icons.signal_cellular_alt;
    }
    return Icons.network_check;
  }

  Widget _row(SpeedTestResult r) {
    final expanded = _expandedId == r.id;
    final net = r.networkType ?? '—';
    return Column(
      children: [
        InkWell(
          onTap: () {
            setState(() => _expandedId = expanded ? null : r.id);
            // Déclenche la résolution de l'adresse au dépliage du test.
            if (!expanded) _ensureAddress(r);
          },
          child: Container(
            decoration: const BoxDecoration(
              color: Color(0xFF10161F),
              border: Border(bottom: BorderSide(color: YeleColors.testBot)),
            ),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Type
                Expanded(
                  flex: 12,
                  child: Column(
                    children: [
                      Icon(
                        _typeIcon(net),
                        size: 16,
                        color: const Color(0xFFCFD6E0),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        net,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFFCFD6E0),
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: _typeColor(net),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          net.length > 5 ? net.substring(0, 5) : net,
                          style: const TextStyle(
                            color: Color(0xFF11210B),
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // ISP / Réseau
                Expanded(
                  flex: 20,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.operator ?? '—',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFCFD6E0),
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        r.location ?? '—',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF8FA0B8),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                // Date
                Expanded(
                  flex: 13,
                  child: Column(
                    children: [
                      Text(
                        _date.format(r.timestamp),
                        style: const TextStyle(
                          color: Color(0xFFCFD6E0),
                          fontSize: 11,
                        ),
                      ),
                      Text(
                        _time.format(r.timestamp),
                        style: const TextStyle(
                          color: Color(0xFF8FA0B8),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
                // Débits
                Expanded(
                  flex: 14,
                  child: Column(
                    children: [
                      Text(
                        '${r.downloadSpeed.toStringAsFixed(2)} Mb/s',
                        style: const TextStyle(
                          color: Color(0xFFCFD6E0),
                          fontSize: 11,
                        ),
                      ),
                      Text(
                        '${r.uploadSpeed.toStringAsFixed(2)} Mb/s',
                        style: const TextStyle(
                          color: Color(0xFF8FA0B8),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
                // Score /100 + bouton d'expansion
                Expanded(
                  flex: 12,
                  child: Column(
                    children: [
                      Text(
                        _scoreText(r),
                        style: const TextStyle(
                          color: Color(0xFFCFD6E0),
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Container(
                        width: 22,
                        height: 22,
                        decoration: const BoxDecoration(
                          color: YeleColors.testBot,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          expanded ? Icons.remove : Icons.add,
                          size: 16,
                          color: const Color(0xFF11210B),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (expanded) _detail(r),
      ],
    );
  }

  /// Ligne « Adresse » (structure validee le 06/11/2026 : Rue, Quartier,
  /// Ville, Province, Region, Pays) et ligne « GPS ». Tant que la resolution
  /// est en cours, « Adresse : recherche… » est affichee a cote des
  /// coordonnees ; en cas d'echec ou d'absence d'adresse OSM, « non
  /// disponible · GPS seul ».
  List<Widget> _coordBlock(
    SpeedTestResult r,
    Widget Function(String k, String v) line,
  ) {
    final key = ReverseGeocodingService.cacheKeyFor(r.latitude!, r.longitude!);
    final address = _addresses[key];
    final coords =
        '${r.latitude!.toStringAsFixed(4)}, ${r.longitude!.toStringAsFixed(4)}';
    if (address == null) {
      // Resolution en cours.
      return [line('Adresse', 'recherche…'), line('GPS', coords)];
    }
    if (address.isEmpty) {
      // Aucune adresse OSM connue a ces coordonnees (ou hors Burkina).
      return [
        line('Adresse', 'non disponible · GPS seul'),
        line('GPS', coords),
      ];
    }
    return [line('Adresse', address), line('GPS', coords)];
  }

  Widget _detail(SpeedTestResult r) {
    Widget line(String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '$k :',
            style: const TextStyle(color: Color(0xFF1F3A00), fontSize: 12),
          ),
          Flexible(
            child: Text(
              v,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Color(0xFF1F3A00),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );

    final wifi = (r.networkType ?? '').toUpperCase().contains('WIFI');

    // Revue du 06/11 — la carte de détail est rangée en six catégories
    // (plan de l'owner, façon nPerf) ; une catégorie vide ne s'affiche pas.
    Widget group(String title, List<Widget> lignes) => lignes.isEmpty
        ? const SizedBox.shrink()
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 2),
                child: Row(
                  children: [
                    Container(
                      width: 3,
                      height: 12,
                      color: const Color(0xFF1F3A00),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFF1F3A00),
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              ...lignes,
            ],
          );

    return Container(
      width: double.infinity,
      color: YeleColors.testMid,
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          // 0 … Position — la localisation se lit en premier (plan owner).
          group(
            'Position',
            (r.latitude ?? 0) != 0 ? _coordBlock(r, line) : <Widget>[],
          ),
          // 1 … Connexion — identité du lien réellement utilisé.
          // Règle produit B1 : FAI et SSID Wi-Fi seulement en Wi-Fi ;
          // une seule ligne « Réseau mobile » (nom canonique, jamais le
          // code brut) et la Technologie en test SIM.
          group('Connexion', [
            line('Serveur', serverHumanLabel(r.server)),
            if (wifi)
              line('FAI', r.operator ?? '—')
            else
              line(
                'Réseau mobile',
                (r.simOperator ?? '').isNotEmpty ? r.simOperator! : '—',
              ),
            if (wifi)
              line(
                'SSID Wi-Fi',
                (r.wifiSsid != null && r.wifiSsid!.trim().isNotEmpty)
                    ? r.wifiSsid!.trim()
                    : 'n.d.',
              ),
            // Règle produit B1 (plan owner Confirmed) : la Technologie
            // (2G/3G/4G/5G) reste affichée pour un test SIM ; « n.d. »
            // pour les anciens enregistrements antérieurs à ce champ.
            if (!wifi)
              line(
                'Technologie',
                (r.technology ?? '').isNotEmpty
                    ? r.technology!
                    : (r.cellularTech ?? 'n.d.'),
              ),
            if ((r.deviceModel ?? '').isNotEmpty)
              line('Appareil', r.deviceModel!),
          ]),
          // 2 … Débit & Latence — ISS-06 (min/moy/max, masqués pour les
          // anciens résultats), IMP-07 (perte, masquée si non mesurée),
          // IMP-01 (données consommées par le test).
          group('Débit & Latence', [
            if (r.downloadStats != null)
              line(
                'Download min / moy / max',
                _minMeanMax(r.downloadStats!, 'Mb/s', 2),
              ),
            if (r.uploadStats != null)
              line(
                'Upload min / moy / max',
                _minMeanMax(r.uploadStats!, 'Mb/s', 2),
              ),
            if (r.pingStats != null)
              line(
                'Latence min / moy / max',
                _minMeanMax(r.pingStats!, 'ms', 0),
              ),
            // Sans stats ISS-06 (anciens enregistrements), le ping
            // moyen reste visible seul.
            if (r.pingStats == null)
              line('Latence', '${r.ping.toStringAsFixed(0)} ms'),
            line('Gigue', '${r.jitter.toStringAsFixed(0)} ms'),
            if (r.packetLoss != null)
              line('Perte de paquets', formatPacketLoss(r.packetLoss!)),
            if ((r.dataUsedKiB ?? -1) >= 0)
              line('Données consommées', _formatData(r.dataUsedKiB!)),
          ]),
          // 3 … Signal radio.
          group('Signal radio', _signalLines(r, line)),
          // 4 … Qualité perçue.
          group('Qualité perçue', [
            if (r.hasStreamingTest) ...[
              // Note /100 de la carte : agrège les 3 résolutions mesurées
              // (ISS-07) et les critères ARCEP — pas une seule résolution.
              line(
                'Streaming',
                '${r.streamingMaxResolution ?? '—'} · ${r.streamingScore!.toStringAsFixed(0)}/100',
              ),
              // Détail par résolution : le taux de performance de chaque
              // palier mesuré (720p, 1080p, 1440p, 2160p).
              for (final q in r.streamingQualities.where((q) => q.reached))
                line(
                  '↳ ${q.label}',
                  '${q.performanceRate.toStringAsFixed(0)} %',
                ),
            ],
            if (r.hasBrowsingTest)
              line(
                'Navigation',
                '${(r.browsingAvgLoadMs! / 1000).toStringAsFixed(1)} s · ${r.browsingScore!.toStringAsFixed(0)}/100',
              ),
            if (r.qoeRating != null && r.qoeRating! > 0)
              line('QoE', '${r.qoeRating}/5'),
          ]),
          // 5 … Score YÉLÉ — le référentiel est cité juste après le titre
          // de catégorie (plan owner), puis score / indice / composantes.
          group('Score YÉLÉ', [
            if (r.scoringVersion != null)
              line('Référentiel', r.scoringVersion!),
            if (r.scoringVersion != null) ..._openScoreLines(r, line),
          ]),
          // IMP-11 — Export de cette mesure (CSV / Excel / PDF / PNG).
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => showExportSheet(context, r),
              icon: const Icon(Icons.ios_share, size: 18),
              label: const Text('Exporter la mesure'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: YeleColors.ink,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Lignes « Puissance du Signal » / « Qualité du Signal » : métriques radio
  /// typées selon la connexion utilisée pour le test. Rien ne s'affiche si
  /// rien n'a été mesuré (iOS, Android < 9, appareils qui n'exposent pas les
  /// compteurs).
  List<Widget> _signalLines(
    SpeedTestResult r,
    Widget Function(String k, String v) line,
  ) {
    // Seuils et libellés alignés sur le tableau de référence qualité signal
    // (IUT) : RSRP −80/−95/−105 et RSSI Wi-Fi −65/−75/−85 ; RSRQ −8/−10/−13
    // (seuils adoptés en revue produit du 05/11 ; libellés harmonisés en
    // revue du 06/11 : un seul mot par palier — Excellent / Bon / Moyen /
    // Faible).
    String qualityLabel(int dbm, {required String kind}) {
      final t = switch (kind) {
        'rsrq' => [-8, -10, -13],
        'rssi' => [-65, -75, -85],
        _ => [-80, -95, -105],
      };
      if (dbm >= t[0]) return 'Excellent';
      if (dbm >= t[1]) return 'Bon';
      if (dbm >= t[2]) return 'Moyen';
      return 'Faible';
    }

    final lines = <Widget>[];

    // Puissance du signal (dBm), avec libellé de qualité.
    if ((r.signalRsrp ?? 0) != 0) {
      lines.add(
        line(
          'Puissance du Signal',
          'RSRP ${r.signalRsrp} dBm '
              '(${qualityLabel(r.signalRsrp!, kind: 'rsrp')})',
        ),
      );
    }
    if ((r.signalNrRsrp ?? 0) != 0) {
      lines.add(line('Puissance du Signal', 'NR RSRP ${r.signalNrRsrp} dBm'));
    }
    if ((r.wifiRssi ?? 0) != 0) {
      lines.add(
        line(
          'Puissance du Signal',
          'RSSI ${r.wifiRssi} dBm '
              '(${qualityLabel(r.wifiRssi!, kind: 'rssi')})',
        ),
      );
      // Règle produit (plan owner 06/11) : en Wi-Fi le seul indicateur
      // radio pertinent est le RSSI — pas de ligne « Qualité du Signal »
      // fantôme (le RSRQ ne concerne que le lien cellulaire).
    }

    // Qualité du signal (dB), ligne dédiée avec libellé (seuils RSRQ).
    if ((r.signalRsrq ?? 0) != 0) {
      lines.add(
        line(
          'Qualité du Signal',
          'RSRQ ${r.signalRsrq} dB '
              '(${qualityLabel(r.signalRsrq!, kind: 'rsrq')})',
        ),
      );
    }
    if ((r.signalNrRsrq ?? 0) != 0) {
      lines.add(line('Qualité du Signal', 'NR RSRQ ${r.signalNrRsrq} dB'));
    }

    // Repli : mesure générique seule, si aucune métrique typée n'est
    // disponible — affichée sur « Puissance du Signal » sans libellé.
    if (lines.isEmpty && (r.signalDbm ?? 0) != 0) {
      lines.add(line('Puissance du Signal', '${r.signalDbm} dBm'));
    }
    return lines;
  }

  /// ISS-06 : « 3.20 / 18.40 / 41.00 Mb/s ».
  String _minMeanMax(MinMeanMax s, String unit, int digits) =>
      '${s.min.toStringAsFixed(digits)} / ${s.mean.toStringAsFixed(digits)} / '
      '${s.max.toStringAsFixed(digits)} $unit';
}
