# Fiche d'impact — IMP-02

## Constat
Les options de configuration étaient limitées. Il manquait un accès direct à la FAQ, aux informations de contact/support et aux informations de l'application depuis l'écran Réglages.

## Objectif
Enrichir le menu Réglages avec :
- Une page FAQ native (accordéons) listant les questions/réponses sans lien vers un site externe
- Un accès « Contactez-nous » (appel téléphonique vers le support)
- Un dialogue « À propos de Yélé » (version et description)
- Nettoyage de l'interface (simplification, espacement, icônes)

## Fichiers modifiés / ajoutés
- `lib/screens/faq_screen.dart` (ajouté) — Écran FAQ natif
- `lib/screens/settings_screen.dart` (modifié) — Enrichissement du menu Réglages
- `lib/main.dart` (modifié) — Enregistrement route `/faq`
- `lib/theme/yele_theme.dart` (modifié) — Ajustements thème
- `lib/services/location_service.dart` (modifié) — Ajustements mineurs
- `android/app/src/main/AndroidManifest.xml` (modifié)
- `android/gradle.properties` (modifié)
- `pubspec.yaml` / `pubspec.lock` (modifiés)

## Comportement attendu
- Depuis Réglages : FAQ, Contactez-nous (compose l'appel), À propos (dialogue) accessibles
- La FAQ fonctionne hors-ligne, sans redirection web
- Les actions de contact fonctionnent selon le contexte de l'appareil

## Tests
- Navigation Réglages → FAQ, dépliage/repliage des questions
- Réglages → Contactez-nous (vérification appel)
- Réglages → À propos (affichage dialogue)
- `flutter analyze` sans erreurs

## Impact
Amélioration UX. Aucun impact sur les mesures/scores. Ajout d'assets/code local uniquement.

## Références
- Issue : [yele-bf/mobilefront#8](https://github.com/yele-bf/mobilefront/issues/8)
- PR : [yele-bf/mobilefront#48](https://github.com/yele-bf/mobilefront/pull/48)
