// IMP-14 — Texte des conditions d'utilisation et de la politique de
// confidentialité, affiché au premier lancement (/consent) et depuis les
// réglages (/conditions). Toute modification des données collectées ou des
// règles d'usage doit être reportée ici ET s'accompagner d'une hausse de
// ConsentService.termsVersion, pour que l'accord soit redemandé.

/// Date de la version affichée en tête du texte.
const String CONDITIONS_DATE = '15 novembre 2026 (version 2)';

/// Adresse à laquelle écrire pour exercer ses droits (accès, suppression).
const String CONDITIONS_CONTACT_EMAIL = 'support@yele.bf';

class ConditionsSection {
  final String title;
  final List<String> paragraphs;
  final List<String> bullets;

  const ConditionsSection(this.title,
      {this.paragraphs = const [], this.bullets = const []});
}

/// Ce qui part au serveur à chaque test, résumé pour l'écran du premier
/// lancement.
const List<String> CONSENT_SUMMARY = [
  'les résultats des tests : débits, latence, navigation web, streaming',
  'votre position GPS au moment du test et l\'adresse approchée qui en '
      'découle',
  'votre opérateur, le type de connexion et la technologie (2G à 5G), avec '
      'la qualité du signal radio',
  'votre adresse IP publique et le fournisseur d\'accès qui lui correspond',
  'le modèle de votre téléphone et un identifiant aléatoire de l\'appareil, '
      'qui ne révèle ni votre identité ni votre numéro',
  'les données consommées par le test',
];

const List<ConditionsSection> CONDITIONS_UTILISATION = [
  ConditionsSection(
    'Objet de Yélé',
    paragraphs: [
      'Yélé mesure la qualité des réseaux mobiles au Burkina Faso. Les '
          'mesures des utilisateurs alimentent une carte publique de '
          'couverture et des statistiques comparant les opérateurs.',
    ],
  ),
  ConditionsSection(
    'Conditions d\'utilisation',
    bullets: [
      'l\'application est gratuite et ne contient aucune publicité',
      'un test consomme des données mobiles (plusieurs dizaines de Mo pour '
          'un test complet) : ils sont décomptés de votre forfait par votre '
          'opérateur',
      'les résultats sont indicatifs : ils dépendent du lieu, de l\'heure, '
          'du téléphone et du serveur de mesure, et n\'engagent ni Yélé ni '
          'les opérateurs',
      'n\'utilisez pas Yélé pour perturber un réseau ou fausser les '
          'statistiques (tests en boucle, positions falsifiées)',
      'la localisation doit être activée pour lancer un test : une mesure '
          'sans position ne peut pas figurer sur la carte',
    ],
  ),
  ConditionsSection(
    'Données envoyées à chaque test',
    paragraphs: [
      'À chaque test que vous lancez, Yélé enregistre sur votre téléphone '
          'puis envoie à son serveur :',
    ],
    bullets: CONSENT_SUMMARY,
  ),
  ConditionsSection(
    'Collecte en arrière-plan',
    paragraphs: [
      'Une collecte automatique en arrière-plan (relever la technologie '
          'réseau et le niveau de signal sans lancer de test) est prévue, '
          'mais elle n\'est pas encore proposée : elle sera réintroduite '
          'dans une prochaine version de l\'application, avec les mêmes '
          'garanties de consentement et de désactivation à tout moment.',
    ],
  ),
  ConditionsSection(
    'Ce que Yélé ne collecte pas',
    bullets: [
      'votre nom, votre numéro de téléphone ou votre adresse e-mail',
      'vos contacts, messages, photos ou fichiers',
      'l\'IMEI ou le numéro de série de votre téléphone',
    ],
  ),
  ConditionsSection(
    'Utilisation des données',
    bullets: [
      'construire la carte publique de couverture, où les mesures '
          'apparaissent comme des points sans nom',
      'calculer des statistiques par opérateur, par zone et par technologie',
      'détecter les anomalies et prévoir la qualité du réseau',
    ],
    paragraphs: [
      'Vos données ne sont ni vendues ni utilisées à des fins publicitaires.',
    ],
  ),
  ConditionsSection(
    'Services tiers',
    paragraphs: [
      'Pour fonctionner, Yélé fait appel à des services extérieurs qui voient '
          'passer votre adresse IP :',
    ],
    bullets: [
      'le serveur de mesure Yélé, hébergé chez Render, et sa base de données',
      'OpenStreetMap, pour le fond de la carte de couverture et pour '
          'traduire la position d\'un test en adresse lisible (Nominatim)',
      'le test de streaming : YouTube, ou une vidéo de test hébergée chez '
          'Netlify avec ses bibliothèques de lecture (jsDelivr)',
      'les sites chargés par le test de navigation : Google, Wikipédia, '
          'Facebook, lefaso.net, YouTube et Bing',
    ],
  ),
  ConditionsSection(
    'Vos choix et vos droits',
    bullets: [
      'refuser : l\'application se ferme sans rien mesurer ni envoyer',
      'retirer votre accord à tout moment depuis Réglages → Assistance → '
          'Retirer mon accord : les conditions ET les autorisations '
          '(localisation, réseau mobile, notifications) vous seront de '
          'nouveau demandées',
      'désactiver la localisation dans les paramètres Android : les tests '
          'sont alors bloqués',
      'demander l\'accès à vos mesures ou leur suppression en écrivant à '
          '$CONDITIONS_CONTACT_EMAIL',
    ],
  ),
];
