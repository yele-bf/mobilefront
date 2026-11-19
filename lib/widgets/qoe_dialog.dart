import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/qoe_answers.dart';
import '../theme/yele_theme.dart';

/// Questionnaire de Qualité d'Expérience (QoE), adapté au type de test.
///
/// Reprend strictement les questions du XLSForm terrain :
/// - profil (âge, genre, ancienneté) demandé à chaque test, pré-rempli ;
/// - questions propres au type de test ;
/// - améliorations (liste mobile ou fixe selon la connexion mesurée) ;
/// - commentaire libre facultatif.
///
/// Aucune réponse n'est obligatoire : « Passer » ferme sans rien enregistrer,
/// « Enregistrer » accepte un questionnaire partiel.
class QoeDialog extends StatefulWidget {
  /// `speedtest`, `navigation`, `streaming` ou `complet`.
  final String testType;

  /// Liste « mobile » (SIM) ou « fixe » (Wi-Fi).
  final bool isMobile;

  /// Réponses existantes : profil mémorisé ou évaluation à modifier.
  final QoeAnswers? initial;

  final void Function(QoeAnswers answers) onCompleted;

  const QoeDialog({
    super.key,
    required this.testType,
    required this.isMobile,
    required this.onCompleted,
    this.initial,
  });

  @override
  State<QoeDialog> createState() => _QoeDialogState();
}

class _QoeDialogState extends State<QoeDialog> {
  late QoeAnswers _answers;

  final _commentCtrl = TextEditingController();
  final _autreCtrl = TextEditingController();

  bool get _isMobile => widget.isMobile;

  String get _typeLabel {
    switch (widget.testType) {
      case 'navigation':
        return 'Navigation web';
      case 'streaming':
        return 'Streaming vidéo';
      case 'complet':
        return 'Test complet';
      default:
        return 'Speedtest';
    }
  }

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _answers = QoeAnswers(
      testType: widget.testType,
      reseau: _isMobile ? 'mobile' : 'fixe',
      trancheAge: i?.trancheAge,
      genre: i?.genre,
      dureeUtilisation: i?.dureeUtilisation,
      vitesseInternet: i?.vitesseInternet,
      difficultePagesWeb: i?.difficultePagesWeb,
      qualiteStreaming: i?.qualiteStreaming,
      buffering: i?.buffering,
      evaluationGlobaleReseau: i?.evaluationGlobaleReseau,
      ameliorationsAutre: i?.ameliorationsAutre,
      commentaire: i?.commentaire,
    );
    if (i != null) _answers.ameliorations.addAll(i.ameliorations);
    _commentCtrl.text = i?.commentaire ?? '';
    _autreCtrl.text = i?.ameliorationsAutre ?? '';
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    _autreCtrl.dispose();
    super.dispose();
  }

  bool get _showVitesse =>
      widget.testType == 'speedtest' || widget.testType == 'complet';
  bool get _showPages =>
      widget.testType == 'navigation' || widget.testType == 'complet';
  bool get _showStreaming =>
      widget.testType == 'streaming' || widget.testType == 'complet';

  void _submit() {
    if (_commentCtrl.text.trim().isNotEmpty) {
      _answers.commentaire = _commentCtrl.text.trim();
    }
    if (_answers.ameliorations.contains('autre') &&
        _autreCtrl.text.trim().isNotEmpty) {
      _answers.ameliorationsAutre = _autreCtrl.text.trim();
    }
    widget.onCompleted(_answers);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.88;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 520, maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(context),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _profilSection(),
                    const SizedBox(height: 4),
                    if (_showVitesse) _vitesseSection(),
                    if (_showPages) _pagesSection(),
                    if (_showStreaming) ...[
                      _videoSection(),
                      _coupuresSection(),
                    ],
                    _satisfactionSection(),
                    _ameliorationsSection(),
                    _commentaireSection(),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            _footer(context),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 14, 10, 12),
      decoration: const BoxDecoration(
        color: Color(0xFF1C2419),
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Évaluation de l\'expérience',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  '$_typeLabel · ${QoeAnswers.questionCount(widget.testType)} questions',
                  style: const TextStyle(color: Color(0xFFCFD8CC), fontSize: 11),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Passer',
                style: TextStyle(color: Colors.white, fontSize: 12.5)),
          ),
        ],
      ),
    );
  }

  Widget _footer(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(18)),
        border: Border(top: BorderSide(color: Color(0xFFE3E7E0))),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(
                foregroundColor: YeleColors.surface.muted,
                side: BorderSide(color: YeleColors.line),
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
              child: const Text('Passer'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF16557E),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
              child: const Text('Enregistrer'),
            ),
          ),
        ],
      ),
    );
  }

  // ── Sections ──

  Widget _questionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: YeleColors.surface.ink,
              height: 1.3),
        ),
      );

  Widget _section({required Widget child}) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: child,
      );

  Widget _profilSection() {
    return _section(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        decoration: BoxDecoration(
          color: const Color(0xFFF2F5F1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFC8D0C6)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('🙋 PROFIL',
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .4,
                        color: Color(0xFF6B7565))),
                const SizedBox(width: 6),
                if (widget.initial?.trancheAge != null ||
                    widget.initial?.genre != null ||
                    widget.initial?.dureeUtilisation != null)
                  const Text('· pré-rempli',
                      style: TextStyle(
                          fontSize: 9.5,
                          color: YeleColors.good,
                          fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 8),
            _profilLigne('Âge', QoeAnswers.ageOptions, _answers.trancheAge,
                (v) => setState(() => _answers.trancheAge = v)),
            _profilLigne(
                'Genre',
                QoeAnswers.genreOptions,
                _answers.genre,
                (v) => setState(() => _answers.genre = v)),
            _profilLigne(
                'Chez cet opérateur',
                QoeAnswers.ancienneteOptions,
                _answers.dureeUtilisation,
                (v) => setState(() => _answers.dureeUtilisation = v)),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  Widget _profilLigne(
    String label,
    Map<String, String> options,
    String? selected,
    ValueChanged<String?> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('$label :',
              style: const TextStyle(
                  fontSize: 10.5, fontWeight: FontWeight.w700)),
          ...options.entries.map(
            (e) => _chip(
              label: e.value,
              selected: selected == e.key,
              compact: true,
              onTap: () => onChanged(selected == e.key ? null : e.key),
            ),
          ),
        ],
      ),
    );
  }

  Widget _vitesseSection() {
    return _section(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _questionTitle(
              'Comment évaluez-vous la vitesse de votre connexion Internet ?'),
          Row(
            children: [
              ...List.generate(5, (i) {
                final star = i + 1;
                final on = star <= (_answers.vitesseInternet ?? 0);
                return IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  constraints:
                      const BoxConstraints(minWidth: 38, minHeight: 38),
                  icon: Icon(on ? Icons.star_rounded : Icons.star_border_rounded,
                      size: 32,
                      color: on ? const Color(0xFFE8A913) : YeleColors.line),
                  onPressed: () => setState(() => _answers.vitesseInternet =
                      _answers.vitesseInternet == star ? null : star),
                );
              }),
              const SizedBox(width: 6),
              if (_answers.vitesseInternet != null)
                Flexible(
                  child: Text(
                    QoeAnswers.etoilesLabels[_answers.vitesseInternet] ?? '',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF16557E)),
                  ),
                ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Text('1 étoile = très lente · 5 étoiles = très rapide',
                style: TextStyle(fontSize: 10, color: Color(0xFF6B7565))),
          ),
        ],
      ),
    );
  }

  Widget _pagesSection() {
    return _section(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _questionTitle(
              'Avez-vous des difficultés à charger des pages web ?'),
          _choixUnique(
            QoeAnswers.frequenceOptions,
            _answers.difficultePagesWeb,
            (v) => setState(() => _answers.difficultePagesWeb = v),
          ),
        ],
      ),
    );
  }

  Widget _videoSection() {
    return _section(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _questionTitle('Comment jugez-vous la qualité des vidéos en ligne ?'),
          _choixUnique(
            QoeAnswers.niveauOptions,
            _answers.qualiteStreaming,
            (v) => setState(() => _answers.qualiteStreaming = v),
          ),
        ],
      ),
    );
  }

  Widget _coupuresSection() {
    return _section(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _questionTitle(
              'Rencontrez-vous des coupures ou des blocages pendant les vidéos ?'),
          _choixUnique(
            QoeAnswers.frequenceOptions,
            _answers.buffering,
            (v) => setState(() => _answers.buffering = v),
          ),
        ],
      ),
    );
  }

  Widget _satisfactionSection() {
    return _section(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _questionTitle(
              'Globalement, comment évaluez-vous la qualité du réseau de votre opérateur ?'),
          _choixUnique(
            QoeAnswers.niveauOptions,
            _answers.evaluationGlobaleReseau,
            (v) => setState(() => _answers.evaluationGlobaleReseau = v),
          ),
        ],
      ),
    );
  }

  Widget _choixUnique(
    Map<String, String> options,
    String? selected,
    ValueChanged<String?> onChanged,
  ) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: options.entries
          .map((e) => _chip(
                label: e.value,
                selected: selected == e.key,
                onTap: () => onChanged(selected == e.key ? null : e.key),
              ))
          .toList(),
    );
  }

  Widget _ameliorationsSection() {
    final options = QoeAnswers.ameliorationsOptions(_isMobile);
    return _section(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _questionTitle(
              'Quelle est l\'amélioration la plus urgente ? (plusieurs réponses)'),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: options.entries.map((e) {
              final selected = _answers.ameliorations.contains(e.key);
              return _chip(
                label: e.value,
                selected: selected,
                onTap: () => _toggleAmelioration(e.key),
              );
            }).toList(),
          ),
          if (_answers.ameliorations.contains('autre'))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextField(
                controller: _autreCtrl,
                maxLength: 120,
                style: const TextStyle(fontSize: 12.5),
                decoration: InputDecoration(
                  hintText: 'Précisez l\'amélioration…',
                  hintStyle: const TextStyle(fontSize: 12),
                  isDense: true,
                  counterText: '',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(9)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _toggleAmelioration(String key) {
    setState(() {
      if (key == 'aucune_reponse') {
        // Règle du formulaire : « Aucune » est exclusive.
        if (_answers.ameliorations.contains(key)) {
          _answers.ameliorations.clear();
        } else {
          _answers.ameliorations
            ..clear()
            ..add(key);
        }
        return;
      }
      if (_answers.ameliorations.contains(key)) {
        _answers.ameliorations.remove(key);
      } else {
        _answers.ameliorations
          ..remove('aucune_reponse')
          ..add(key);
      }
    });
  }

  Widget _commentaireSection() {
    return _section(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _questionTitle('Un commentaire ?'),
              ),
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('facultatif',
                    style: TextStyle(fontSize: 10, color: Color(0xFF6B7565))),
              ),
            ],
          ),
          TextField(
            controller: _commentCtrl,
            maxLength: 200,
            maxLines: 3,
            inputFormatters: [LengthLimitingTextInputFormatter(200)],
            style: const TextStyle(fontSize: 12.5),
            decoration: InputDecoration(
              hintText: 'Votre remarque en quelques mots…',
              hintStyle: const TextStyle(fontSize: 12),
              isDense: true,
              counterStyle:
                  const TextStyle(fontSize: 9.5, color: Color(0xFF6B7565)),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(9)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    bool compact = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: EdgeInsets.symmetric(
            horizontal: compact ? 9 : 11, vertical: compact ? 4 : 7),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF16557E)
              : (compact ? Colors.white : const Color(0xFFFBFCFA)),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
              color: selected ? const Color(0xFF16557E) : YeleColors.line),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: compact ? 10 : 11.5,
            color: selected ? Colors.white : YeleColors.surface.ink,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
