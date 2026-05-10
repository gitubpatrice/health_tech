import 'package:flutter/material.dart';

/// Champ texte pour les données sensibles (notes santé, observations,
/// rapport de séance, notes RDV).
///
/// **Audit M8** : un `TextField` standard envoie le contenu en cours de
/// saisie aux services cloud du clavier (Gboard cloud completion, Samsung
/// Keyboard predictive engine, SwiftKey cloud) pour proposer des
/// suggestions et corrections automatiques. Les notes santé d'un client
/// peuvent ainsi finir dans des serveurs Google / Microsoft / Samsung
/// SANS jamais quitter la base chiffrée localement.
///
/// Ce widget force :
///   - `enableSuggestions: false` (pas de prediction cloud)
///   - `autocorrect: false` (pas de correction cloud)
///   - `keyboardType: visiblePassword` (verrouille certains claviers tiers
///     en mode "passe-texte" qui désactivent leur cloud par convention)
///   - `enableIMEPersonalizedLearning: false` (Android 13+ : empêche le
///     clavier d'apprendre les mots saisis pour son dictionnaire user)
///
/// Le rendu reste un `TextField` classique sinon. Le user peut toujours
/// copier le texte (mais l'audit M8 a noté que c'est un risque mineur
/// vs la fuite cloud, qui est silencieuse).
class SensitiveTextField extends StatelessWidget {
  const SensitiveTextField({
    super.key,
    required this.controller,
    this.decoration,
    this.maxLines = 1,
    this.minLines,
    this.onChanged,
    this.textInputAction,
    this.onFieldSubmitted,
    this.validator,
  });

  final TextEditingController controller;
  final InputDecoration? decoration;
  final int? maxLines;
  final int? minLines;
  final ValueChanged<String>? onChanged;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onFieldSubmitted;
  final FormFieldValidator<String>? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      decoration: decoration,
      maxLines: maxLines,
      minLines: minLines,
      onChanged: onChanged,
      textInputAction: textInputAction,
      onFieldSubmitted: onFieldSubmitted,
      validator: validator,
      enableSuggestions: false,
      autocorrect: false,
      enableIMEPersonalizedLearning: false,
      keyboardType: maxLines == null || maxLines! > 1
          ? TextInputType.multiline
          : TextInputType.visiblePassword,
    );
  }
}
