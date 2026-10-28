import 'package:flutter/material.dart';

import '../theme/yele_theme.dart';
import '../widgets/yele_scaffold.dart';

/// FAQ native de l'application : toutes les questions sont affichées dans
/// l'app même, sous forme d'accordéons dépliables — aucune page web externe.
class FaqScreen extends StatelessWidget {
  const FaqScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return YeleScaffold(
      title: 'FAQ',
      route: '/faq',
      body: Container(
        color: YeleColors.panel,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 28),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 10, 4, 2),
              child: Text(
                'Questions fréquentes',
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: YeleColors.ink),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 0, 4, 14),
              child: Text(
                "Tout ce qu'il faut savoir sur Yélé et la mesure de la "
                'qualité des réseaux mobiles au Burkina Faso.',
                style: TextStyle(fontSize: 14, color: YeleColors.muted),
              ),
            ),
            for (final section in _sections) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                child: Text(
                  section.title,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: YeleColors.primary),
                ),
              ),
              for (final qa in section.items)
                _FaqCard(question: qa.question, answer: qa.answer),
            ],
            _contactCard(context),
          ],
        ),
      ),
    );
  }

  Widget _contactCard(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 18),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: YeleColors.primary.withValues(alpha: .08),
        border: Border.all(color: YeleColors.primary, width: 1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Une autre question ?',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: YeleColors.primary)),
          const SizedBox(height: 6),
          const Text(
            "Écrivez-nous à support@yele.bf — nous répondons au mieux sous "
            "quelques jours ouvrés. Vous pouvez aussi signaler un problème "
            "directement depuis l'application : Réglages → Contactez-nous.",
            style: TextStyle(fontSize: 14, height: 1.5, color: YeleColors.ink),
          ),
        ],
      ),
    );
  }
}

// ── Données de la FAQ ────────────────────────────────────────────────────────

class _Section {
  final String title;
  final List<_Qa> items;
  const _Section(this.title, this.items);
}

class _Qa {
  final String question;
  final String answer;
  const _Qa(this.question, this.answer);
}

// Réponses : les segments entre **…** sont rendus en gras.
const _sections = <_Section>[
  _Section('Général', [
    _Qa('Qu\'est-ce que Yélé ?', 'Yélé est un projet de **mesure de la qualité '
        'des réseaux mobiles au Burkina Faso**. L\'application mesure le '
        'débit, la latence (ping), la qualité de streaming vidéo et la '
        'navigation web, puis géolocalise chaque test pour construire une '
        'carte publique de la couverture des opérateurs (ONATEL/Telmob, '
        'Orange, Telecel/Moov).'),
    _Qa('Combien de données consomme un test ?',
        'Un test complet consomme en moyenne **20 à 40 Mo** selon la qualité '
        'de votre connexion : environ 10 s de téléchargement, 10 s d\'envoi, '
        'une courte vidéo de streaming et quelques pages web. La collecte de '
        'couverture en arrière-plan est beaucoup plus légère : environ '
        '**4 Ko par relève**, soit moins de 10 Mo par mois.'),
    _Qa('À quoi servent mes données et ma position ?',
        'La position GPS, l\'opérateur de votre SIM et la technologie réseau '
        '(2G/3G/4G/5G) sont attachés à chaque mesure pour savoir **où** le '
        'réseau est bon ou faible. Aucune donnée nominative n\'est collectée : '
        "aucune inscription n'est requise."),
    _Qa('Comment obtenir des résultats fiables ?',
        'Restez **immobile et en extérieur si possible** pendant le test, ne '
        "consommez pas d'autres contenus (vidéo, téléchargement) en même "
        'temps, et évitez le Wi-Fi : l\'objectif est de mesurer le réseau '
        'mobile. Refaites le test à différents moments de la journée pour '
        'capturer les variations.'),
    _Qa('Qu\'est-ce que le « score » affiché après un test ?',
        'Le score résume la qualité de connexion sur 100, en combinant le '
        'débit descendant, le débit montant, le ping et la réussite des tests '
        'de streaming et de navigation — selon des critères inspirés des '
        "barèmes de l'ARCEP."),
    _Qa("Pourquoi la collecte en arrière-plan s'arrête parfois ?",
        'Certains téléphones (Tecno, Infinix, Xiaomi, Oppo…) arrêtent les '
        "services d'arrière-plan pour économiser la batterie. Dans les "
        'réglages Android, allez dans **Paramètres → Applications → Yélé → '
        'Batterie** et choisissez **« Sans restriction »**. Une notification '
        'permanente reste affichée tant que la collecte est active.'),
    _Qa("L'application est-elle disponible sur iPhone ?",
        'La mesure active (tests de débit) fonctionne sur Android et iOS, '
        'mais la **collecte de couverture en arrière-plan** est actuellement '
        'limitée à Android pour des raisons techniques de plateforme.'),
    _Qa('Comment sont établis les classements des opérateurs ?',
        'Les classements agrègent toutes les mesures anonymisées par '
        'opérateur et par zone : débit médian, latence médiane, taux de '
        'réussite du streaming et de la navigation. Plus il y a de tests '
        'réalisés dans une zone, plus le résultat est représentatif.'),
  ]),
  _Section('La méthodologie des tests en détail', [
    _Qa('Comment fonctionne le test de débit descendant (download) ?',
        "L'application télécharge pendant environ **10 secondes** des données "
        'depuis plusieurs serveurs en parallèle (comme si vous regardiez '
        'plusieurs vidéos simultanément), puis calcule le débit moyen atteint '
        'en **Mbps**. C\'est le chiffre qui compte le plus pour le chargement '
        'de pages web, les vidéos et les téléchargements. Le test utilise '
        'plusieurs connexions simultanées afin de saturer la capacité réelle '
        'de votre réseau, comme le fait nPerf.'),
    _Qa('Comment fonctionne le test de débit montant (upload) ?',
        "Le principe est inverse : l'application envoie des données vers le "
        'serveur pendant environ **10 secondes**. Ce débit est important pour '
        "l'envoi de photos et vidéos sur WhatsApp, les pièces jointes "
        "d'e-mails, les appels vidéo et les diffusions en direct. Sur les "
        'réseaux mobiles, le débit montant est presque toujours inférieur au '
        'descendant : c\'est normal, le réseau consacre plus de capacité au '
        'téléchargement.'),
    _Qa('Comment est mesurée la latence (ping) ?',
        'La latence est le temps aller-retour d\'un petit paquet entre votre '
        'téléphone et le serveur, exprimé en **millisecondes (ms)**. Plus la '
        'valeur est basse, plus la connexion est réactive (jeux en ligne, '
        'appels, navigation fluide). Yélé mesure aussi le **jitter**, '
        'c\'est-à-dire la variabilité de la latence : un ping de 40 ms stable '
        'est meilleure qu\'un ping de 40 ms qui oscille entre 10 et 120 ms.'),
    _Qa('Comment fonctionne le test de streaming vidéo ?',
        "L'application lit une vidéo réelle et mesure la **plus haute "
        'résolution** que votre connexion peut maintenir sans coupure : 480p, '
        '720p, 1080p (Full HD), 1440p ou 2160p (4K). Elle compte aussi le '
        'nombre d\'interruptions (mises en mémoire tampon, « buffering »). Le '
        'résultat est exprimé en **score de qualité d\'expérience (QoE)** sur '
        '100, comme nPerf : 100 signifie que la 4K est lue sans aucune '
        'interruption.'),
    _Qa('Comment fonctionne le test de navigation web ?',
        "L'application charge une série de pages web de référence (composées "
        'comme des pages réelles : texte, images, styles) et mesure le temps '
        'de chargement de chacune. Le résultat est un **score de navigation '
        'sur 100** : plus les pages se chargent vite et complètement, plus le '
        'score est élevé. Ce test reflète l\'expérience réelle de navigation '
        'mieux que le seul débit brut.'),
  ]),
  _Section('Bien tester et comprendre ses résultats', [
    _Qa('Pourquoi mes résultats varient-ils d\'un test à l\'autre ?',
        "C'est normal et même attendu. Le réseau mobile est **partagé** entre "
        'tous les utilisateurs de la cellule : aux heures de pointe (soirée, '
        'pause déjeuner), le débit baisse. La position joue aussi : à '
        "l'intérieur d'un bâtiment, le signal est plus faible qu'en "
        'extérieur. Enfin, la météo, la distance à l\'antenne et la charge du '
        'serveur influencent chaque test. Refaites le test à différents '
        'moments et endroits pour voir la tendance réelle.'),
    _Qa('Pourquoi le débit mesuré est-il inférieur à celui annoncé par mon '
        'opérateur ?',
        'Les vitesses annoncées (« jusqu\'à 100 Mbps ») sont des **maximums '
        'théoriques** dans des conditions idéales : antenne proche, réseau '
        'vide, appareil compatible le mieux du marché. En pratique, le débit '
        "dépend du nombre d'utilisateurs connectés à l'antenne, de la "
        'technologie (2G, 3G, 4G, 5G), de la bande de fréquences utilisée et '
        'de votre modèle de téléphone. Un débit 4G mesuré entre 10 et 40 Mbps '
        'est parfaitement normal au Burkina Faso.'),
    _Qa('Faut-il désactiver le Wi-Fi et le VPN avant de tester ?',
        '**Oui pour le Wi-Fi** : si le Wi-Fi reste actif, votre test risque '
        'de mesurer la box au lieu du réseau mobile. Désactivez-le ou '
        'coupez-le depuis les réglages rapides. **Oui pour le VPN** : un VPN '
        'fait transiter vos données par un serveur distant, ce qui ajoute de '
        'la latence et réduit le débit — le résultat ne refléterait plus '
        'votre réseau. Désactivez aussi le mode économie d\'énergie, qui peut '
        'brider la connexion.'),
    _Qa('Que signifient Mbps et Mo ?',
        '**Mbps** (mégabits par seconde) mesure la **vitesse** : plus '
        "c'est élevé, plus la connexion est rapide. **Mo** (mégaoctets) "
        'mesure la **quantité de données** consommée de votre forfait. Il y '
        'a 8 bits dans un octet : télécharger un fichier de 100 Mo à 20 Mbps '
        'prend environ 40 secondes. Un test Yélé complet consomme 20 à 40 Mo, '
        "soit bien moins qu'une vidéo de 10 minutes sur les réseaux sociaux."),
    _Qa('Comment lire la carte de couverture ?',
        'La carte du tableau de bord agrège toutes les mesures anonymisées '
        'par opérateur et par zone. Les couleurs indiquent la **qualité '
        'moyenne mesurée** (débit, latence, streaming, navigation) et non une '
        'couverture théorique. Vous pouvez filtrer par opérateur (ONATEL, '
        'Orange, Telecel), par technologie (2G à 5G), par usage (débit, '
        'streaming, navigation) et par période. Vous n\'êtes pas dans la '
        'carte ? Faites un test là où vous êtes, votre mesure enrichira la '
        'zone en quelques minutes.'),
    _Qa('Yélé est-il comparable à nPerf ?',
        'Yélé s\'inspire des meilleures pratiques de nPerf et des outils '
        'grand public : mêmes grandes familles de tests (débit, ping, '
        'streaming, navigation), géolocalisation des mesures et cartes par '
        'opérateur. La différence est le **terrain** : Yélé est conçu pour le '
        'Burkina Faso, avec une méthodologie alignée sur les critères de '
        "l'ARCEP, des données ouvertes et sous contrôle national — chaque "
        'mesure contribue à une carte publique indépendante de la qualité '
        'réelle des réseaux.'),
  ]),
  _Section('Questions pratiques & communauté', [
    _Qa('Quel débit faut-il pour quel usage ?',
        'Repères utiles pour situer votre résultat : **WhatsApp / messages** : '
        '0,5 Mbps suffit · **appels vidéo** : 1 à 3 Mbps · **réseaux sociaux '
        'et musique** : 2 à 5 Mbps · **vidéo HD 1080p** : 5 à 10 Mbps · '
        '**vidéo 4K** : 25 Mbps et plus · **téléchargement d\'une '
        'application** : 10 Mbps rend le téléchargement confortable. En '
        'dessous de 1 Mbps, la navigation devient difficile. Votre score '
        'Yélé tient compte de ces seuils pour juger la qualité réelle de '
        "votre expérience."),
    _Qa('Comment interpréter le score sur 100 ?',
        'Comme le barème de nPerf, le score combine débit, latence, streaming '
        'et navigation : **90 – 100** : excellente connexion, tout est fluide '
        '(4K sans coupure) · **70 – 89** : bonne connexion (Full HD '
        'confortable) · **50 – 69** : moyenne (HD possible, navigation un peu '
        'lente) · **30 – 49** : faible (vidéo SD avec coupures, pages '
        'lentes) · **0 – 29** : très faible (usage minimal). Un score '
        "au-dessus de 70 signifie que vous pouvez faire tout ce qu'un "
        'smartphone permet normalement.'),
    _Qa('Où retrouver l\'historique de mes tests ?',
        'Chaque test réalisé est enregistré sur votre téléphone : ouvrez le '
        'menu latéral puis **Historique** pour revoir vos mesures passées '
        'avec leur date, leur position et leur score. Vos tests alimentent '
        'aussi le tableau de bord public : ils y apparaissent de façon '
        '**anonyme**, agrégés avec ceux de toute la communauté, quelques '
        "minutes après l'envoi."),
    _Qa('À quoi sert la collecte automatique en arrière-plan ?',
        "Sans que vous ayez rien à faire, l'application enregistre "
        'discrètement la technologie réseau disponible (2G, 3G, 4G, 5G) et le '
        'niveau de signal à l\'endroit où vous passez. Chaque relève ne '
        'consomme que **4 Ko**. C\'est cette collecte qui permet de dessiner '
        'une carte de couverture **complète et continue**, y compris sur les '
        'routes et dans les zones où personne ne lance de test. Vous pouvez '
        'la désactiver dans **Réglages → Paramètres techniques**.'),
    _Qa('Comment tester correctement la 5G ?',
        'Vérifiez d\'abord que votre téléphone est **compatible 5G** et que '
        'votre forfait l\'autorise. Désactivez ensuite le Wi-Fi, placez-vous '
        "en extérieur proche d'une antenne 5G, puis vérifiez dans la barre "
        "d'état que l'icône « 5G » apparaît avant de lancer le test. "
        "L'application enregistre automatiquement la technologie utilisée : "
        'votre mesure alimentera la vue 5G de la carte si elle est disponible '
        'dans votre zone.'),
    _Qa('Peut-on faire un test en 2G ou 3G ?',
        '**Oui**, et c\'est même précieux : les zones couvertes seulement en '
        '2G/3G sont les moins documentées. Le test s\'adapte automatiquement '
        '— volumes de données réduits, vidéos de qualité plus basse — pour '
        'rester réalisable sur un réseau lent. Dans ces conditions, le débit '
        'mesuré sera faible et le test peut durer un peu plus longtemps : '
        "c'est normal, et la mesure contribue à montrer les zones à "
        'améliorer.'),
    _Qa('Mes données personnelles sont-elles protégées ?',
        'Aucune inscription, aucun nom, aucun numéro de téléphone : les '
        'mesures sont **anonymes**. L\'adresse IP est masquée dans les '
        'statistiques publiques et la position GPS n\'est utilisée que pour '
        'placer la mesure sur la carte, jamais pour vous identifier. Vous '
        'pouvez demander la suppression des mesures liées à votre appareil à '
        'tout moment via **Réglages → Contactez-nous**.'),
    _Qa('Comment partager mes résultats ?',
        "Après chaque test, l'écran de score propose un bouton **Partager** : "
        'il génère une image récapitulative (débit, ping, score) que vous '
        'pouvez envoyer sur WhatsApp, Facebook ou par e-mail. Partager vos '
        'résultats encourage votre entourage à tester son propre réseau — '
        'plus il y a de mesures, plus la carte est fiable pour tous.'),
    _Qa('Que faire si le test affiche « aucune connexion » ?',
        'Vérifiez dans l\'ordre : **1)** les données mobiles sont activées '
        '(pas seulement le Wi-Fi appel) · **2)** vous avez du crédit ou un '
        'forfait valide · **3)** le mode avion est bien désactivé · **4)** le '
        "signal n'est pas complètement absent (0 barre). Si tout est bon mais "
        'que le test échoue plusieurs fois, c\'est justement une information '
        'utile : relancez le test quand le réseau revient, ou faites-le à un '
        'autre endroit — les échecs répétés signalent des zones réellement '
        'mal desservies.'),
    _Qa('Comment signaler une zone mal couverte ?',
        'Le meilleur signalement, c\'est une **mesure** : faites un test à '
        "l'endroit concerné, même si le résultat est mauvais — surtout si le "
        'résultat est mauvais. Votre mesure apparaîtra sur la carte publique '
        "et fera ressortir la zone en difficulté dans les statistiques de "
        "l'opérateur. Pour un problème précis (antenne endommagée, panne "
        'prolongée), utilisez **Réglages → Contactez-nous** en précisant la '
        'localité.'),
  ]),
];

// ── Carte accordéon ─────────────────────────────────────────────────────────

class _FaqCard extends StatefulWidget {
  final String question;
  final String answer;
  final bool initiallyExpanded;

  const _FaqCard({
    required this.question,
    required this.answer,
    this.initiallyExpanded = false,
  });

  @override
  State<_FaqCard> createState() => _FaqCardState();
}

class _FaqCardState extends State<_FaqCard> {
  late bool _open = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE3E6EE)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: _open,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          backgroundColor: YeleColors.primary.withValues(alpha: .05),
          collapsedBackgroundColor: Colors.transparent,
          collapsedShape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(12))),
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(12))),
          onExpansionChanged: (v) => setState(() => _open = v),
          title: Text(
            widget.question,
            style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w600, color: YeleColors.ink),
          ),
          trailing: Icon(_open ? Icons.remove : Icons.add,
              color: YeleColors.primary),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: _RichAnswer(text: widget.answer),
            ),
          ],
        ),
      ),
    );
  }
}

/// Rend le texte de réponse avec les segments **…** en gras.
class _RichAnswer extends StatelessWidget {
  final String text;
  const _RichAnswer({required this.text});

  @override
  Widget build(BuildContext context) {
    const base =
        TextStyle(fontSize: 14, height: 1.55, color: YeleColors.muted);
    const bold = TextStyle(
        fontSize: 14,
        height: 1.55,
        color: YeleColors.ink,
        fontWeight: FontWeight.w700);

    final spans = <TextSpan>[];
    final parts = text.split('**');
    for (var i = 0; i < parts.length; i++) {
      if (parts[i].isEmpty) continue;
      spans.add(TextSpan(text: parts[i], style: i.isOdd ? bold : base));
    }
    return Text.rich(
      TextSpan(children: spans),
    );
  }
}
