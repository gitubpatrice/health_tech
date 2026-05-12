/// Status keys (string for stable persistence).
class SessionStatus {
  const SessionStatus._();
  static const String planned = 'planned';
  static const String confirmed = 'confirmed';
  static const String done = 'done';
  static const String cancelled = 'cancelled';
  static const String noShow = 'no_show';

  static const List<String> all = [planned, confirmed, done, cancelled, noShow];
}

class SessionKind {
  const SessionKind._();
  static const String human = 'human';
  static const String animal = 'animal';
  static const String duo = 'duo';
  static const String distance = 'distance';
  static const String onsite = 'onsite';
  static const String home = 'home';
  static const String other = 'other';

  static const List<String> all = [
    human,
    animal,
    duo,
    distance,
    onsite,
    home,
    other,
  ];
}

class PaymentStatus {
  const PaymentStatus._();
  static const String unpaid = 'unpaid';
  static const String paid = 'paid';
  static const String deposit = 'deposit';
  static const String free = 'free';
}

class PaymentMethod {
  const PaymentMethod._();
  static const String cash = 'cash';
  static const String card = 'card';
  static const String transfer = 'transfer';
  static const String check = 'check';
  static const String other = 'other';
}

/// Catalogue of stable session-motive keys. UI labels live in l10n.
class SessionMotives {
  const SessionMotives._();
  static const String reiki = 'reiki';
  static const String energetic = 'energetic';
  static const String harmonisation = 'harmonisation';
  static const String stress = 'stress';
  static const String fatigue = 'fatigue';
  static const String pain = 'pain';
  static const String emotional = 'emotional';
  static const String spiritual = 'spiritual';
  static const String grief = 'grief';
  static const String sleep = 'sleep';
  static const String followUp = 'follow_up';
  static const String endOfLife = 'end_of_life';
  static const String calming = 'calming';

  static const List<String> all = [
    reiki,
    energetic,
    harmonisation,
    stress,
    fatigue,
    pain,
    emotional,
    spiritual,
    grief,
    sleep,
    followUp,
    endOfLife,
    calming,
  ];
}

/// Structured report stored as JSON. Adding a section = no migration.
class SessionReport {
  const SessionReport({
    this.beforeState = '',
    this.clientPerception = '',
    this.observations = '',
    this.flow = '',
    this.zonesWorked = '',
    this.energetic = '',
    this.afterState = '',
    this.advice = '',
    this.nextRecommendation = '',
  });

  /// Client / animal state before the session.
  final String beforeState;

  /// What the client / owner reported.
  final String clientPerception;

  /// Practitioner observations.
  final String observations;

  /// How the session unfolded.
  final String flow;

  /// Zones / chakras worked.
  final String zonesWorked;

  /// Energetic perceptions.
  final String energetic;

  /// State after the session.
  final String afterState;

  /// Advice given to the client.
  final String advice;

  /// Recommended next step.
  final String nextRecommendation;

  bool get isEmpty =>
      beforeState.isEmpty &&
      clientPerception.isEmpty &&
      observations.isEmpty &&
      flow.isEmpty &&
      zonesWorked.isEmpty &&
      energetic.isEmpty &&
      afterState.isEmpty &&
      advice.isEmpty &&
      nextRecommendation.isEmpty;

  SessionReport copyWith({
    String? beforeState,
    String? clientPerception,
    String? observations,
    String? flow,
    String? zonesWorked,
    String? energetic,
    String? afterState,
    String? advice,
    String? nextRecommendation,
  }) => SessionReport(
    beforeState: beforeState ?? this.beforeState,
    clientPerception: clientPerception ?? this.clientPerception,
    observations: observations ?? this.observations,
    flow: flow ?? this.flow,
    zonesWorked: zonesWorked ?? this.zonesWorked,
    energetic: energetic ?? this.energetic,
    afterState: afterState ?? this.afterState,
    advice: advice ?? this.advice,
    nextRecommendation: nextRecommendation ?? this.nextRecommendation,
  );

  Map<String, dynamic> toJson() => {
    if (beforeState.isNotEmpty) 'before': beforeState,
    if (clientPerception.isNotEmpty) 'client': clientPerception,
    if (observations.isNotEmpty) 'observations': observations,
    if (flow.isNotEmpty) 'flow': flow,
    if (zonesWorked.isNotEmpty) 'zones': zonesWorked,
    if (energetic.isNotEmpty) 'energetic': energetic,
    if (afterState.isNotEmpty) 'after': afterState,
    if (advice.isNotEmpty) 'advice': advice,
    if (nextRecommendation.isNotEmpty) 'next': nextRecommendation,
  };

  static SessionReport fromJson(Map<String, dynamic> json) => SessionReport(
    beforeState: json['before'] as String? ?? '',
    clientPerception: json['client'] as String? ?? '',
    observations: json['observations'] as String? ?? '',
    flow: json['flow'] as String? ?? '',
    zonesWorked: json['zones'] as String? ?? '',
    energetic: json['energetic'] as String? ?? '',
    afterState: json['after'] as String? ?? '',
    advice: json['advice'] as String? ?? '',
    nextRecommendation: json['next'] as String? ?? '',
  );
}

class Session {
  const Session({
    required this.id,
    required this.clientId,
    required this.startAt,
    required this.endAt,
    required this.kind,
    this.animalId,
    this.location,
    this.status = SessionStatus.planned,
    this.motives = const <String>[],
    this.priceCents,
    this.paymentStatus,
    this.paymentMethod,
    this.report = const SessionReport(),
    this.privateNote = '',
    this.improvementLevel,
    this.nextSuggestedAt,
    this.externalCalendarId,
    this.externalCalendarEventId,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String clientId;
  final String? animalId;
  final DateTime startAt;
  final DateTime endAt;
  final String kind;
  final String? location;
  final String status;
  final List<String> motives;
  final int? priceCents;
  final String? paymentStatus;
  final String? paymentMethod;
  final SessionReport report;

  /// Practitioner-only note, never exported.
  final String privateNote;

  /// 0..4 (none, light, moderate, important, follow up).
  final int? improvementLevel;
  final DateTime? nextSuggestedAt;

  /// IDs du calendrier système (device_calendar). Null tant que la session
  /// n'a pas encore été synchronisée, puis renseignés automatiquement.
  final String? externalCalendarId;
  final String? externalCalendarEventId;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  Duration get duration => endAt.difference(startAt);

  Session copyWith({
    String? id,
    String? clientId,
    String? animalId,
    DateTime? startAt,
    DateTime? endAt,
    String? kind,
    String? location,
    String? status,
    List<String>? motives,
    int? priceCents,
    String? paymentStatus,
    String? paymentMethod,
    SessionReport? report,
    String? privateNote,
    int? improvementLevel,
    DateTime? nextSuggestedAt,
    String? externalCalendarId,
    String? externalCalendarEventId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Session(
    id: id ?? this.id,
    clientId: clientId ?? this.clientId,
    animalId: animalId ?? this.animalId,
    startAt: startAt ?? this.startAt,
    endAt: endAt ?? this.endAt,
    kind: kind ?? this.kind,
    location: location ?? this.location,
    status: status ?? this.status,
    motives: motives ?? this.motives,
    priceCents: priceCents ?? this.priceCents,
    paymentStatus: paymentStatus ?? this.paymentStatus,
    paymentMethod: paymentMethod ?? this.paymentMethod,
    report: report ?? this.report,
    privateNote: privateNote ?? this.privateNote,
    improvementLevel: improvementLevel ?? this.improvementLevel,
    nextSuggestedAt: nextSuggestedAt ?? this.nextSuggestedAt,
    externalCalendarId: externalCalendarId ?? this.externalCalendarId,
    externalCalendarEventId:
        externalCalendarEventId ?? this.externalCalendarEventId,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}
