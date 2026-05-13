/// Hygiène de vie d'un client (cinq dropdowns optionnels). Toutes les
/// valeurs sont des **strings stables** persistées dans
/// `clients.profile_json` — les libellés (FR / EN) sont rendus côté UI via
/// `lifestyleLabel(l10n, value)`. Conserver l'inventaire ici garantit qu'on
/// ne casse pas la rétro-compat à chaque refonte de l'UI.
class Lifestyle {
  const Lifestyle._();

  // -- Fumeur ----------------------------------------------------------------
  static const String smokerYes = 'smoker_yes';
  static const String smokerNo = 'smoker_no';
  static const String smokerFormer = 'smoker_former';
  static const String smokerOccasional = 'smoker_occasional';
  static const List<String> smokerValues = [
    smokerYes,
    smokerNo,
    smokerFormer,
    smokerOccasional,
  ];

  // -- Sport -----------------------------------------------------------------
  static const String sportNone = 'sport_none';
  static const String sportOccasional = 'sport_occasional';
  static const String sportRegular = 'sport_regular';
  static const String sportIntense = 'sport_intense';
  static const List<String> sportValues = [
    sportNone,
    sportOccasional,
    sportRegular,
    sportIntense,
  ];

  // -- Sommeil ---------------------------------------------------------------
  static const String sleepGood = 'sleep_good';
  static const String sleepAverage = 'sleep_average';
  static const String sleepLight = 'sleep_light';
  static const String sleepDisturbed = 'sleep_disturbed';
  static const List<String> sleepValues = [
    sleepGood,
    sleepAverage,
    sleepLight,
    sleepDisturbed,
  ];

  // -- Stress ----------------------------------------------------------------
  static const String stressLow = 'stress_low';
  static const String stressModerate = 'stress_moderate';
  static const String stressHigh = 'stress_high';
  static const String stressBurnout = 'stress_burnout';
  static const List<String> stressValues = [
    stressLow,
    stressModerate,
    stressHigh,
    stressBurnout,
  ];

  // -- Alimentation ----------------------------------------------------------
  static const String dietOmnivore = 'diet_omnivore';
  static const String dietVegetarian = 'diet_vegetarian';
  static const String dietVegan = 'diet_vegan';
  static const String dietPescatarian = 'diet_pescatarian';
  static const String dietOther = 'diet_other';
  static const List<String> dietValues = [
    dietOmnivore,
    dietVegetarian,
    dietVegan,
    dietPescatarian,
    dietOther,
  ];

  // -- Clés JSON utilisées dans `clients.profile_json` ---------------------
  static const String keySmoker = 'smoker';
  static const String keySport = 'sport';
  static const String keySleep = 'sleep';
  static const String keyStress = 'stress';
  static const String keyDiet = 'diet';
}

/// Source de premier contact (dropdown facultatif sur le formulaire client).
/// Stockée dans `clients.profile_json['contact_source']`.
class ContactSource {
  const ContactSource._();
  static const String wordOfMouth = 'word_of_mouth';
  static const String website = 'website';
  static const String socialMedia = 'social_media';
  static const String recommendation = 'recommendation';
  static const String localPress = 'local_press';
  static const String fair = 'fair';
  static const String other = 'other';

  static const List<String> all = [
    wordOfMouth,
    website,
    socialMedia,
    recommendation,
    localPress,
    fair,
    other,
  ];

  /// Clé JSON utilisée dans `clients.profile_json`.
  static const String key = 'contact_source';
}

/// Helpers de lecture / écriture sur `profile_json` pour rester DRY entre
/// le formulaire client (`client_form_screen`) et le détail
/// (`client_detail_screen`). Les valeurs vides / `'none'` sont écrites
/// comme `null` puis retirées du map — la table v5 reste lisible à
/// l'œil nu si l'utilisateur restaure une vieille base.
class ClientProfileExt {
  const ClientProfileExt._();

  static String? readString(Map<String, dynamic> profile, String key) {
    final v = profile[key];
    return v is String && v.isNotEmpty ? v : null;
  }

  static Map<String, dynamic> writeString(
    Map<String, dynamic> profile,
    String key,
    String? value,
  ) {
    final next = Map<String, dynamic>.from(profile);
    if (value == null || value.isEmpty) {
      next.remove(key);
    } else {
      next[key] = value;
    }
    return next;
  }

  // -- Contact source -------------------------------------------------------
  /// Lit la source de contact en validant qu'elle appartient à
  /// [ContactSource.all]. Valeur inconnue → `null` (UI affichera « Non
  /// renseigné »). Défense contre injection via `.htbk` forgé
  /// (audit v1.6.0 F8).
  static String? contactSource(Map<String, dynamic> profile) {
    final raw = readString(profile, ContactSource.key);
    if (raw == null) return null;
    return ContactSource.all.contains(raw) ? raw : null;
  }

  // -- Contact d'urgence ---------------------------------------------------
  /// Bloc imbriqué `{name, phone}` dans `profile.emergency_contact`.
  static const String _emergencyKey = 'emergency_contact';

  static String? emergencyContactName(Map<String, dynamic> profile) {
    final v = profile[_emergencyKey];
    return v is Map ? (v['name'] as String?) : null;
  }

  static String? emergencyContactPhone(Map<String, dynamic> profile) {
    final v = profile[_emergencyKey];
    return v is Map ? (v['phone'] as String?) : null;
  }

  static Map<String, dynamic> writeEmergencyContact(
    Map<String, dynamic> profile, {
    required String? name,
    required String? phone,
  }) {
    final next = Map<String, dynamic>.from(profile);
    final n = (name ?? '').trim();
    final p = (phone ?? '').trim();
    if (n.isEmpty && p.isEmpty) {
      next.remove(_emergencyKey);
    } else {
      next[_emergencyKey] = {
        if (n.isNotEmpty) 'name': n,
        if (p.isNotEmpty) 'phone': p,
      };
    }
    return next;
  }

  // -- Hygiène de vie ------------------------------------------------------
  static const String _lifestyleKey = 'lifestyle';

  /// Valeurs autorisées pour chaque axe d'hygiène de vie. Sert de
  /// whitelist au read pour neutraliser une valeur arbitraire injectée
  /// dans `profile_json` via un `.htbk` forgé ou un import futur (audit
  /// v1.6.0 F8). On retourne `null` si la valeur lue n'appartient pas à
  /// la liste connue — le UI affichera alors « Non renseigné ».
  static const Map<String, List<String>> _lifestyleAllowed = {
    Lifestyle.keySmoker: Lifestyle.smokerValues,
    Lifestyle.keySport: Lifestyle.sportValues,
    Lifestyle.keySleep: Lifestyle.sleepValues,
    Lifestyle.keyStress: Lifestyle.stressValues,
    Lifestyle.keyDiet: Lifestyle.dietValues,
  };

  static String? lifestyle(Map<String, dynamic> profile, String key) {
    final v = profile[_lifestyleKey];
    if (v is! Map) return null;
    final raw = v[key];
    if (raw is! String || raw.isEmpty) return null;
    final allowed = _lifestyleAllowed[key];
    if (allowed == null) return null; // clé inconnue → strip
    return allowed.contains(raw) ? raw : null;
  }

  /// Au moins un dropdown lifestyle est renseigné.
  static bool hasLifestyle(Map<String, dynamic> profile) {
    final v = profile[_lifestyleKey];
    if (v is! Map) return false;
    return v.values.any((e) => e is String && e.isNotEmpty);
  }

  static Map<String, dynamic> writeLifestyle(
    Map<String, dynamic> profile, {
    String? smoker,
    String? sport,
    String? sleep,
    String? stress,
    String? diet,
  }) {
    final next = Map<String, dynamic>.from(profile);
    final block = <String, dynamic>{
      if (smoker != null && smoker.isNotEmpty) Lifestyle.keySmoker: smoker,
      if (sport != null && sport.isNotEmpty) Lifestyle.keySport: sport,
      if (sleep != null && sleep.isNotEmpty) Lifestyle.keySleep: sleep,
      if (stress != null && stress.isNotEmpty) Lifestyle.keyStress: stress,
      if (diet != null && diet.isNotEmpty) Lifestyle.keyDiet: diet,
    };
    if (block.isEmpty) {
      next.remove(_lifestyleKey);
    } else {
      next[_lifestyleKey] = block;
    }
    return next;
  }
}
