import 'dart:math' as math;

/// Moteur de scoring YELE — Option A « échelle ouverte » (version yele-open-1.0.0).
///
/// Rôle : transformer des mesures brutes (débit, latence, navigation, streaming)
/// en scores de points. Aucune dépendance Flutter : ce fichier ne fait que des
/// calculs, il ne touche ni l'interface, ni le stockage, ni la collecte.
///
/// Le score global est la somme des cinq composantes. La somme de référence
/// des allocations est 75 000 points, mais le score global n'est PAS plafonné
/// (les composantes download et upload ne le sont pas non plus).
///
/// Convention « zéro = non mesuré » : un score absent est [null] avec un
/// statut explicite, jamais 0 — 0 est réservé à une mesure valide qui donne
/// réellement zéro point.
class YeleScoringEngine {
  /// Version du modèle de scoring, enregistrée avec chaque résultat.
  static const String version = 'yele-open-1.0.0';

  /// Somme de référence des allocations (informatif, pas un plafond).
  static const int referenceTotal = 75000;

  // Allocations maximales par composante.
  static const double maxDownload = 17500;
  static const double maxUpload = 7500;
  static const double maxPingJitter = 15000;
  static const double maxBrowsing = 17500;
  static const double maxStreaming = 17500;

  /// Seuil minimal de débit en Mbps : en dessous, le score vaut 0.
  static const double speedFloorMbps = 0.1;

  /// Latence effective au-delà de laquelle le score ping/jitter vaut 0 (ms).
  static const double latencyCeilingMs = 250;

  /// Délai de chargement de référence pour une page web (s) : au-delà,
  /// la page rapporte 0 point de QoE.
  static const double pageLoadReferenceSec = 10;

  /// Pénalité par interruption de lecture vidéo, en points de QoE.
  static const double stallPenaltyQoe = 15;

  // ── Score Download ────────────────────────────────────────────────────────

  /// S_D = 17500 × log10(1 + D) si D >= 0,1, sinon 0. Non plafonné.
  ///
  /// [downloadMbps] invalide (négatif, NaN, infini) → retourne null avec
  /// statut invalid.
  ScoreComponent scoreDownload(double? downloadMbps) {
    final v = _validateSpeed(downloadMbps, 'download');
    if (v != null) return v;
    final d = downloadMbps!;
    if (d < speedFloorMbps) {
      return const ScoreComponent(
        status: MeasurementStatus.completed,
        score: 0,
      );
    }
    return ScoreComponent(
      status: MeasurementStatus.completed,
      score: maxDownload * math.log(1 + d) / math.ln10,
    );
  }

  // ── Score Upload ──────────────────────────────────────────────────────────

  /// S_U = 7500 × log10(1 + U) si U >= 0,1, sinon 0. Non plafonné.
  ScoreComponent scoreUpload(double? uploadMbps) {
    final v = _validateSpeed(uploadMbps, 'upload');
    if (v != null) return v;
    final u = uploadMbps!;
    if (u < speedFloorMbps) {
      return const ScoreComponent(
        status: MeasurementStatus.completed,
        score: 0,
      );
    }
    return ScoreComponent(
      status: MeasurementStatus.completed,
      score: maxUpload * math.log(1 + u) / math.ln10,
    );
  }

  // ── Score Ping et jitter ──────────────────────────────────────────────────

  /// Latence effective : L = Ping + 2 × Jitter (ms).
  ///
  /// S_P = 15000 × (1 - L/250)² si L < 250, sinon 0 (formule quadratique
  /// décroissante — ne PAS remplacer par une exponentielle).
  ScoreComponent scorePingJitter(double? pingMs, double? jitterMs) {
    if (pingMs == null || jitterMs == null) {
      return const ScoreComponent(
        status: MeasurementStatus.unavailable,
        message: 'Latence ou gigue absente',
      );
    }
    if (_bad(pingMs) || _bad(jitterMs)) {
      return const ScoreComponent(
        status: MeasurementStatus.invalid,
        message: 'Latence ou gigue non finie ou négative',
      );
    }
    final effective = pingMs + 2 * jitterMs;
    if (effective >= latencyCeilingMs) {
      return ScoreComponent(
        status: MeasurementStatus.completed,
        score: 0,
        intermediate: effective,
      );
    }
    final factor = 1 - effective / latencyCeilingMs;
    return ScoreComponent(
      status: MeasurementStatus.completed,
      score: maxPingJitter * factor * factor,
      intermediate: effective,
    );
  }

  // ── Score Navigation web ──────────────────────────────────────────────────

  /// QoE d'une page : max(0, 100 × (1 - T/10)), T en secondes.
  ///
  /// Une entrée à [null] est une mesure manquante (timeout, erreur technique,
  /// page non testée) : elle ne compte PAS dans la moyenne — elle est signalée
  /// dans [ScoreComponent.message] sans transformer l'absence en zéro.
  ///
  /// Politique de score partiel : le test est « complet » uniquement si toutes
  /// les pages ont un temps valide. Sinon la composante est [partial] et le
  /// score reste calculable sur les pages valides, mais l'appelant ne doit pas
  /// le présenter comme un score complet (voir [YeleScoringResult.isComplete]).
  ///
  /// [expectedPages] = nombre de pages du test. Aucune page n'est ajoutée ou
  /// supprimée : la moyenne porte sur le nombre réel de pages mesurées.
  ScoreComponent scoreBrowsing(
    List<double?> loadTimesSec, {
    int? expectedPages,
  }) {
    if (loadTimesSec.isEmpty) {
      return const ScoreComponent(
        status: MeasurementStatus.unavailable,
        message: 'Aucun temps de chargement disponible',
      );
    }
    final expected = expectedPages ?? loadTimesSec.length;
    final qoes = <double>[];
    var missing = 0;
    var invalid = 0;
    for (final t in loadTimesSec) {
      if (t == null) {
        missing++;
        continue;
      }
      if (_bad(t)) {
        invalid++;
        continue;
      }
      final q = 100 * (1 - t / pageLoadReferenceSec);
      qoes.add(q > 0 ? q : 0);
    }
    if (qoes.isEmpty) {
      return ScoreComponent(
        status: MeasurementStatus.failed,
        message: missing + invalid > 0
            ? 'Aucune page chargée ($missing manquante(s), $invalid invalide(s))'
            : 'Test de navigation sans résultat exploitable',
      );
    }
    final qoeWeb = qoes.fold<double>(0, (a, b) => a + b) / qoes.length;
    final complete = qoes.length == expected && missing == 0 && invalid == 0;
    final notes = <String>[];
    if (missing > 0) notes.add('$missing page(s) sans mesure');
    if (invalid > 0) notes.add('$invalid mesure(s) invalide(s)');
    return ScoreComponent(
      status: complete
          ? MeasurementStatus.completed
          : MeasurementStatus.partial,
      score: maxBrowsing * qoeWeb / 100,
      message: notes.isEmpty ? null : notes.join(' ; '),
    );
  }

  // ── Score Streaming vidéo ─────────────────────────────────────────────────

  /// QoE_video = max(0, 100 × (1 - T_buf/T_total) - 15 × N_stalls).
  ///
  /// Règles de validité (cahier des charges §4.5) :
  /// - T_total strictement positif ;
  /// - 0 <= T_buf <= T_total ;
  /// - N_stalls entier non négatif ;
  /// - mesures indispensables absentes → composante indisponible, jamais un
  ///   score artificiel.
  ///
  /// [totalDurationSec] = durée totale de la session vidéo (somme des paliers
  /// réellement joués, mesurée à la montre). [bufferingSec] inclut le
  /// démarrage initial et les interruptions.
  ScoreComponent scoreStreaming({
    double? totalDurationSec,
    double? bufferingSec,
    int? stallCount,
  }) {
    if (totalDurationSec == null ||
        bufferingSec == null ||
        stallCount == null) {
      return const ScoreComponent(
        status: MeasurementStatus.unavailable,
        message: 'Mesures de streaming absentes (test non effectué)',
      );
    }
    if (_bad(totalDurationSec) || _bad(bufferingSec) || stallCount < 0) {
      return const ScoreComponent(
        status: MeasurementStatus.invalid,
        message: 'Mesures de streaming incohérentes',
      );
    }
    if (totalDurationSec <= 0) {
      return const ScoreComponent(
        status: MeasurementStatus.failed,
        message: 'Durée de session nulle — test non exploitable',
      );
    }
    if (bufferingSec > totalDurationSec) {
      return const ScoreComponent(
        status: MeasurementStatus.invalid,
        message: 'Temps de buffering supérieur à la durée totale',
      );
    }
    final qoe = math.max(
      0,
      100 * (1 - bufferingSec / totalDurationSec) -
          stallPenaltyQoe * stallCount,
    );
    return ScoreComponent(
      status: MeasurementStatus.completed,
      score: maxStreaming * qoe / 100,
      intermediate: totalDurationSec,
    );
  }

  // ── Score global ──────────────────────────────────────────────────────────

  /// Calcule les cinq composantes puis le score global.
  ///
  /// Politique de complétude (décision explicite, voir §6 du cahier des
  /// charges) : le score global n'est fourni que si les cinq composantes sont
  /// « completed ». Sinon, [YeleScoringResult.globalScore] vaut null et le
  /// statut global est [MeasurementStatus.partial], [MeasurementStatus.failed]
  /// ou [MeasurementStatus.unavailable] — l'interface ne doit pas présenter un
  /// total partiel comme un score complet.
  YeleScoringResult scoreAll({
    double? downloadMbps,
    double? uploadMbps,
    double? pingMs,
    double? jitterMs,
    List<double?> browsingLoadTimesSec = const [],
    int? browsingExpectedPages,
    double? streamingTotalSec,
    double? streamingBufferingSec,
    int? streamingStallCount,
  }) {
    final d = scoreDownload(downloadMbps);
    final u = scoreUpload(uploadMbps);
    final p = scorePingJitter(pingMs, jitterMs);
    final b = scoreBrowsing(
      browsingLoadTimesSec,
      expectedPages: browsingExpectedPages,
    );
    final v = scoreStreaming(
      totalDurationSec: streamingTotalSec,
      bufferingSec: streamingBufferingSec,
      stallCount: streamingStallCount,
    );

    final components = [d, u, p, b, v];
    final allCompleted = components.every(
      (c) => c.status == MeasurementStatus.completed,
    );
    final anyFailed = components.any(
      (c) => c.status == MeasurementStatus.failed,
    );
    final anyInvalid = components.any(
      (c) => c.status == MeasurementStatus.invalid,
    );
    final anyUnavailable = components.any(
      (c) => c.status == MeasurementStatus.unavailable,
    );

    MeasurementStatus globalStatus;
    if (allCompleted) {
      globalStatus = MeasurementStatus.completed;
    } else if (anyInvalid) {
      globalStatus = MeasurementStatus.invalid;
    } else if (anyFailed) {
      globalStatus = MeasurementStatus.failed;
    } else if (anyUnavailable) {
      globalStatus = MeasurementStatus.unavailable;
    } else {
      globalStatus = MeasurementStatus.partial;
    }

    final global = allCompleted
        ? components.fold<double>(0, (a, c) => a + c.score!)
        : null;

    return YeleScoringResult(
      version: version,
      download: d,
      upload: u,
      pingJitter: p,
      browsing: b,
      streaming: v,
      globalStatus: globalStatus,
      globalScore: global,
    );
  }

  // ── Validation interne ────────────────────────────────────────────────────

  /// Non fini (NaN ou infini) ou négatif.
  static bool _bad(double v) => v.isNaN || v.isInfinite || v < 0;

  ScoreComponent? _validateSpeed(double? value, String label) {
    if (value == null) {
      return ScoreComponent(
        status: MeasurementStatus.unavailable,
        message: 'Débit $label absent',
      );
    }
    if (_bad(value)) {
      return ScoreComponent(
        status: MeasurementStatus.invalid,
        message: 'Débit $label non fini ou négatif',
      );
    }
    return null;
  }

  // ── Classification indicative ─────────────────────────────────────────────

  /// Seuils PROVISOIRES, non calibrés sur un échantillon représentatif.
  /// Centralisés ici pour pouvoir être recalibrés en un seul endroit.
  static ({String label}) classify(double globalScore) {
    if (globalScore <= 30000) return (label: 'Très faible');
    if (globalScore <= 70000) return (label: 'Moyen');
    if (globalScore <= 110000) return (label: 'Bon');
    if (globalScore <= 160000) return (label: 'Très bon');
    return (label: 'Excellent / élite');
  }
}

/// Statut d'une composante ou du score global.
enum MeasurementStatus {
  /// Test effectué et mesure exploitable.
  completed,

  /// Test tenté mais échoué.
  failed,

  /// Test volontairement ignoré.
  skipped,

  /// Test ou mesure indisponible (y compris ancien enregistrement sans champ).
  unavailable,

  /// Mesures présentes mais incohérentes (négatif, NaN, incohérence).
  invalid,

  /// Partiellement disponible — voir [ScoreComponent.message].
  partial,
}

/// Résultat d'une composante : score (points), statut et contexte.
class ScoreComponent {
  final MeasurementStatus status;

  /// Score en points. null quand la composante n'est pas [completed] ni
  /// [partial] (une absence n'est jamais un zéro).
  final double? score;

  /// Valeur intermédiaire utile (ex. latence effective en ms).
  final double? intermediate;

  /// Explication d'un statut non complet.
  final String? message;

  const ScoreComponent({
    required this.status,
    this.score,
    this.intermediate,
    this.message,
  });

  /// Score arrondi à l'entier (arrondi uniquement à la présentation).
  int? get rounded => score?.round();

  Map<String, dynamic> toJson() => {
    'status': status.name,
    if (score != null) 'score': score,
    if (intermediate != null) 'intermediate': intermediate,
    if (message != null) 'message': message,
  };
}

/// Résultat complet du moteur pour un test.
class YeleScoringResult {
  final String version;
  final ScoreComponent download;
  final ScoreComponent upload;
  final ScoreComponent pingJitter;
  final ScoreComponent browsing;
  final ScoreComponent streaming;
  final MeasurementStatus globalStatus;

  /// Somme des cinq composantes, uniquement si toutes sont complètes.
  /// Non plafonné (dépasse 75 000 dès que les débits le justifient).
  final double? globalScore;

  const YeleScoringResult({
    required this.version,
    required this.download,
    required this.upload,
    required this.pingJitter,
    required this.browsing,
    required this.streaming,
    required this.globalStatus,
    this.globalScore,
  });

  /// Vrai si le score global est complet — à vérifier avant tout affichage
  /// présentant le total comme un score définitif.
  bool get isComplete => globalStatus == MeasurementStatus.completed;

  /// Libellé de classification (seuils provisoires).
  String get classification =>
      globalScore == null ? '' : YeleScoringEngine.classify(globalScore!).label;

  /// Score global arrondi à l'entier (arrondi uniquement à la présentation).
  int? get globalRounded => globalScore?.round();
}
