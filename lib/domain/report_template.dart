import 'session.dart';

/// Pour quel type de séance un template est-il pertinent ?
///
/// Sert au filtrage du `BottomSheet` "Insérer un modèle" du formulaire de
/// séance — on n'affiche que les templates dont le `kind` correspond au
/// `kind` courant de la séance, plus les templates polyvalents `other` /
/// `distance` toujours utiles.
class ReportTemplateKind {
  const ReportTemplateKind._();
  static const String human = 'human';
  static const String animal = 'animal';
  static const String duo = 'duo';
  static const String distance = 'distance';
  static const String other = 'other';

  static const List<String> all = [human, animal, duo, distance, other];
}

/// Canevas réutilisable de compte rendu de séance.
///
/// Les 9 sections sont stockées dans une `Map<String, String>` indexée sur
/// les mêmes clés stables que `SessionReport.toJson()` (`before`, `client`,
/// `observations`, `flow`, `zones`, `energetic`, `after`, `advice`, `next`)
/// — ce qui permet à `toSessionReport()` d'être trivial.
class ReportTemplate {
  const ReportTemplate({
    required this.id,
    required this.name,
    required this.kind,
    required this.sections,
    this.isSystem = false,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String kind;

  /// 9 clés possibles (toutes optionnelles côté template — un canevas peut
  /// ne remplir que 3 des 9 champs). Clés stables alignées sur
  /// [SessionReport.toJson] : `before`, `client`, `observations`, `flow`,
  /// `zones`, `energetic`, `after`, `advice`, `next`.
  final Map<String, String> sections;

  final bool isSystem;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Construit un `SessionReport` pré-rempli à partir de ce template. Les
  /// sections absentes du canevas tombent sur `''` (le défaut du modèle).
  SessionReport toSessionReport() => SessionReport(
    beforeState: sections['before'] ?? '',
    clientPerception: sections['client'] ?? '',
    observations: sections['observations'] ?? '',
    flow: sections['flow'] ?? '',
    zonesWorked: sections['zones'] ?? '',
    energetic: sections['energetic'] ?? '',
    afterState: sections['after'] ?? '',
    advice: sections['advice'] ?? '',
    nextRecommendation: sections['next'] ?? '',
  );

  ReportTemplate copyWith({
    String? id,
    String? name,
    String? kind,
    Map<String, String>? sections,
    bool? isSystem,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => ReportTemplate(
    id: id ?? this.id,
    name: name ?? this.name,
    kind: kind ?? this.kind,
    sections: sections ?? this.sections,
    isSystem: isSystem ?? this.isSystem,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}
