import 'dart:convert';

/// Réponses au questionnaire de qualité perçue (QoE), alignées sur le
/// XLSForm terrain `fiche_enquete_qoe_2026`.
///
/// Les clés de [toJson] reprennent les noms des questions du formulaire
/// (`tranche_age`, `vitesse_internet`, `ameliorations_mobile`…) afin que le
/// dashboard puisse agréger les réponses sans table de correspondance.
/// Le type de test et le réseau mesuré sont ajoutés en contexte.
class QoeAnswers {
  /// `speedtest`, `navigation`, `streaming` ou `complet`.
  final String testType;

  /// `mobile` (SIM) ou `fixe` (Wi-Fi).
  final String reseau;

  String? trancheAge; // moins_20 · 20_40 · plus_40
  String? genre; // masculin · feminin
  String? dureeUtilisation; // moins_6_mois · 1_5_ans · plus_5_ans
  int? vitesseInternet; // 1 à 5 étoiles
  String? difficultePagesWeb; // frequemment · souvent · rarement · jamais
  String? qualiteStreaming; // Tres_bonne … Tres_mauvaise
  String? buffering; // frequemment · souvent · rarement · jamais
  String? evaluationGlobaleReseau; // Tres_bonne … Tres_mauvaise
  final Set<String> ameliorations = {};
  String? ameliorationsAutre;
  String? commentaire;

  QoeAnswers({
    required this.testType,
    required this.reseau,
    this.trancheAge,
    this.genre,
    this.dureeUtilisation,
    this.vitesseInternet,
    this.difficultePagesWeb,
    this.qualiteStreaming,
    this.buffering,
    this.evaluationGlobaleReseau,
    this.ameliorationsAutre,
    this.commentaire,
  });

  // ── Libellés (source : feuille `choices` du XLSForm) ──

  static const ageOptions = <String, String>{
    'moins_20': 'Moins de 20 ans',
    '20_40': '20 à 40 ans',
    'plus_40': 'Plus de 40 ans',
  };

  static const genreOptions = <String, String>{
    'masculin': 'Masculin',
    'feminin': 'Féminin',
  };

  static const ancienneteOptions = <String, String>{
    'moins_6_mois': 'Moins de 6 mois',
    '1_5_ans': '1 à 5 ans',
    'plus_5_ans': 'Plus de 5 ans',
  };

  static const frequenceOptions = <String, String>{
    'frequemment': 'Fréquemment',
    'souvent': 'Souvent',
    'rarement': 'Rarement',
    'jamais': 'Jamais',
  };

  static const niveauOptions = <String, String>{
    'Tres_bonne': 'Très bonne',
    'Bonne': 'Bonne',
    'Moyenne': 'Moyenne',
    'Mauvaise': 'Mauvaise',
    'Tres_mauvaise': 'Très mauvaise',
  };

  static const ameliorationsMobileOptions = <String, String>{
    'aucune_reponse': 'Aucune réponse en particulier',
    'baisser_prix': 'Baisser le prix des forfaits Internet',
    'pluie_vent': 'Éviter les coupures du réseau pendant la pluie ou le vent',
    'coupures_electricite':
        'Garder le réseau disponible pendant les coupures d\'électricité',
    'gestion_data': 'Éviter que les mégas Internet finissent trop vite',
    'indoor': 'Améliorer le réseau à l\'intérieur des maisons et bureaux',
    'heures_pointe':
        'Rendre l\'Internet plus rapide aux heures de pointe, surtout le soir',
    'evenements_fetes':
        'Améliorer le réseau pendant les grands événements et fêtes',
    'deplacement': 'Éviter les coupures Internet lors des déplacements',
    'zones_rurales': 'Étendre le réseau mobile dans les zones rurales',
    'autre': 'Autre amélioration à préciser',
  };

  static const ameliorationsFixeOptions = <String, String>{
    'aucune_reponse': 'Aucune réponse en particulier',
    'baisser_prix': 'Baisser le prix des forfaits Internet',
    'reduire_delais_installation':
        'Réduire les délais d\'installation et de raccordement',
    'reparer_pannes_rapidement': 'Réparer plus rapidement les pannes',
    'etendre_fibre': 'Étendre la fibre dans plus de quartiers et de villes',
    'autre': 'Autre amélioration à préciser',
  };

  static Map<String, String> ameliorationsOptions(bool isMobile) =>
      isMobile ? ameliorationsMobileOptions : ameliorationsFixeOptions;

  static const etoilesLabels = <int, String>{
    1: 'Très lente',
    2: 'Lente',
    3: 'Moyenne',
    4: 'Rapide',
    5: 'Très rapide',
  };

  /// Nombre de questions posées pour ce type de test (profil inclus,
  /// commentaire facultatif exclu) — sert de repère dans l'interface.
  static int questionCount(String testType) {
    const specific = {
      'speedtest': 2, // vitesse + satisfaction globale
      'navigation': 2, // pages web + satisfaction globale
      'streaming': 3, // qualité vidéo + coupures + satisfaction globale
      'complet': 5, // vitesse + pages + vidéo + coupures + satisfaction
    };
    return 3 + (specific[testType] ?? 2) + 1; // profil + spécifiques + améliorations
  }

  /// Note 1-5 conservée pour le dashboard : étoiles de vitesse si la
  /// question a été posée, sinon conversion de la satisfaction globale.
  int? get rating {
    if (vitesseInternet != null) return vitesseInternet;
    switch (evaluationGlobaleReseau) {
      case 'Tres_bonne':
        return 5;
      case 'Bonne':
        return 4;
      case 'Moyenne':
        return 3;
      case 'Mauvaise':
        return 2;
      case 'Tres_mauvaise':
        return 1;
    }
    return null;
  }

  /// Satisfaction au format historique du dashboard
  /// (`very_satisfied` … `very_unsatisfied`).
  String? get satisfaction {
    switch (evaluationGlobaleReseau) {
      case 'Tres_bonne':
        return 'very_satisfied';
      case 'Bonne':
        return 'satisfied';
      case 'Moyenne':
        return 'neutral';
      case 'Mauvaise':
        return 'unsatisfied';
      case 'Tres_mauvaise':
        return 'very_unsatisfied';
    }
    return null;
  }

  bool get isEmpty =>
      trancheAge == null &&
      genre == null &&
      dureeUtilisation == null &&
      vitesseInternet == null &&
      difficultePagesWeb == null &&
      qualiteStreaming == null &&
      buffering == null &&
      evaluationGlobaleReseau == null &&
      ameliorations.isEmpty &&
      (commentaire == null || commentaire!.trim().isEmpty);

  /// Profil seul — mémorisé pour pré-remplir le questionnaire suivant.
  Map<String, dynamic> profileJson() => {
        'tranche_age': trancheAge,
        'genre': genre,
        'duree_utilisation': dureeUtilisation,
      };

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'test_type': testType,
      'reseau': reseau,
      if (trancheAge != null) 'tranche_age': trancheAge,
      if (genre != null) 'genre': genre,
      if (dureeUtilisation != null) 'duree_utilisation': dureeUtilisation,
      if (vitesseInternet != null) 'vitesse_internet': vitesseInternet,
      if (difficultePagesWeb != null) 'difficulte_pages_web': difficultePagesWeb,
      if (qualiteStreaming != null) 'qualite_streaming': qualiteStreaming,
      if (buffering != null) 'buffering': buffering,
      if (evaluationGlobaleReseau != null)
        'evaluation_globale_reseau': evaluationGlobaleReseau,
      if (ameliorations.isNotEmpty)
        reseau == 'mobile' ? 'ameliorations_mobile' : 'ameliorations_fixe':
            ameliorations.toList(),
      if (ameliorationsAutre != null && ameliorationsAutre!.trim().isNotEmpty)
        'amelioration_autre': ameliorationsAutre!.trim(),
      if (commentaire != null && commentaire!.trim().isNotEmpty)
        'commentaire': commentaire!.trim(),
    };
    return json;
  }

  factory QoeAnswers.fromJson(
    Map<String, dynamic> json, {
    String testType = 'speedtest',
    String reseau = 'mobile',
  }) {
    final a = QoeAnswers(
      testType: (json['test_type'] ?? testType).toString(),
      reseau: (json['reseau'] ?? reseau).toString(),
      trancheAge: json['tranche_age']?.toString(),
      genre: json['genre']?.toString(),
      dureeUtilisation: json['duree_utilisation']?.toString(),
      difficultePagesWeb: json['difficulte_pages_web']?.toString(),
      qualiteStreaming: json['qualite_streaming']?.toString(),
      buffering: json['buffering']?.toString(),
      evaluationGlobaleReseau: json['evaluation_globale_reseau']?.toString(),
      ameliorationsAutre: json['amelioration_autre']?.toString(),
      commentaire: json['commentaire']?.toString(),
    );
    final v = json['vitesse_internet'];
    if (v is num) a.vitesseInternet = v.toInt();
    final raw = json['ameliorations_mobile'] ?? json['ameliorations_fixe'];
    if (raw is List) {
      a.ameliorations.addAll(raw.map((e) => e.toString()));
    }
    return a;
  }

  /// Décodage tolérant du champ Hive `qoeAnswersJson`.
  static QoeAnswers? tryDecode(String? raw, {String? testType, String? reseau}) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return QoeAnswers.fromJson(
        Map<String, dynamic>.from(decoded),
        testType: testType ?? 'speedtest',
        reseau: reseau ?? 'mobile',
      );
    } catch (_) {
      return null;
    }
  }

  /// Résumé lisible affiché sur la carte « Évaluation enregistrée ».
  List<String> get summaryParts {
    final parts = <String>[];
    if (vitesseInternet != null) {
      parts.add('Vitesse ${etoilesLabels[vitesseInternet]}');
    }
    if (difficultePagesWeb != null) {
      parts.add('Pages web : ${frequenceOptions[difficultePagesWeb]}');
    }
    if (qualiteStreaming != null) {
      parts.add('Vidéos : ${niveauOptions[qualiteStreaming]}');
    }
    if (buffering != null) {
      parts.add('Coupures : ${frequenceOptions[buffering]}');
    }
    if (evaluationGlobaleReseau != null) {
      parts.add('Satisfaction : ${niveauOptions[evaluationGlobaleReseau]}');
    }
    return parts;
  }
}
