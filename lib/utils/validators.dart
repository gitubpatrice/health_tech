/// Validations partagées entre formulaires.
///
/// Centralisées ici pour éviter la duplication de regex (audit v1.6.0 C6 —
/// `_emailRe` était redéfinie en private dans `client_form_screen.dart`
/// puis aurait été dupliquée pour le formulaire animal vétérinaire).
///
/// Toutes les fonctions sont **tolérantes au vide** : un champ optionnel
/// retourne `null` (valide) si l'input est vide. C'est au caller d'imposer
/// un `required` via une autre branche du `validator`.
class HealthValidators {
  const HealthValidators._();

  /// Regex email pragmatique — pas RFC-complète mais couvre 99,9 % des
  /// adresses légitimes. Volontairement permissive : on bloque les évidences
  /// (`foo`, `foo@`, `@bar`) sans rejeter des adresses internationalisées
  /// valides (les CCTLD à plus de 3 lettres sont OK).
  static final RegExp _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  /// Valide un email optionnel. Retourne `null` si valide (ou vide),
  /// `errorMessage` sinon. Trim avant comparaison.
  static String? optionalEmail(String? value, {required String errorMessage}) {
    final s = (value ?? '').trim();
    if (s.isEmpty) return null;
    if (s.length > 254) return errorMessage; // RFC 5321 SMTP cap.
    return _emailRe.hasMatch(s) ? null : errorMessage;
  }

  /// Cap longueur d'un champ texte court. `null` retourné si OK.
  /// Utile pour les noms de templates, cliniques vétérinaires, etc. qui
  /// n'ont jamais à dépasser ~120 caractères en pratique mais qu'un
  /// `.htbk` forgé pourrait gonfler à plusieurs Mo.
  static String? maxLength(
    String? value, {
    required int max,
    required String errorMessage,
  }) {
    final s = (value ?? '').trim();
    if (s.length > max) return errorMessage;
    return null;
  }

  /// Plages de codepoints à filtrer (RTL/bidi/zero-width).
  ///
  /// - U+200B-U+200F : zero-width space/joiner/non-joiner, LRM, RLM
  /// - U+202A-U+202E : LRE, RLE, PDF, LRO, RLO
  /// - U+2066-U+2069 : LRI, RLI, FSI, PDI
  /// - U+FEFF       : BOM / zero-width no-break space
  ///
  /// Ces caractères peuvent inverser le rendu visuel d'un nom de template
  /// ou d'une adresse email exportés en PDF — vecteur de phishing connu
  /// (audit v1.6.0 F10). On les retire au save, pas seulement à
  /// l'affichage : un `.htbk` forgé pourrait les injecter directement.
  static bool _isBidiOverride(int cp) =>
      (cp >= 0x200B && cp <= 0x200F) ||
      (cp >= 0x202A && cp <= 0x202E) ||
      (cp >= 0x2066 && cp <= 0x2069) ||
      cp == 0xFEFF;

  /// Renvoie une copie de [input] sans les caractères de contrôle
  /// bidirectionnel. Idempotent. Préserve les accents, les apostrophes
  /// courbes (U+2019), les points de suspension (U+2026), bref toute la
  /// ponctuation typographique légitime.
  static String stripBidiOverrides(String input) {
    if (input.isEmpty) return input;
    final filtered = input.runes.where((cp) => !_isBidiOverride(cp));
    return String.fromCharCodes(filtered);
  }

  /// Combine [stripBidiOverrides] + cap longueur. Pratique côté write des
  /// libellés saisis : on normalise au save, pas seulement au validate.
  /// `null` retourné si l'input est vide après strip+trim.
  static String? cleanShortLabel(String? input, {int max = 80}) {
    final stripped = stripBidiOverrides((input ?? '').trim());
    if (stripped.isEmpty) return null;
    return stripped.length > max ? stripped.substring(0, max) : stripped;
  }
}
