/// Set of consents bound to a client. Each entry is the timestamp at which
/// the user collected that consent (or null if not given).
class ConsentSet {
  const ConsentSet({
    this.rgpdAt,
    this.disclaimerAt,
    this.reminderAt,
    this.newsletterAt,
  });

  /// GDPR data processing consent (mandatory in France for client records).
  final DateTime? rgpdAt;

  /// Acknowledgement that energetic / Reiki sessions are not medical advice.
  final DateTime? disclaimerAt;

  /// Opt-in to receive appointment reminders.
  final DateTime? reminderAt;

  /// Opt-in to receive newsletter (always optional).
  final DateTime? newsletterAt;

  bool get hasMandatory => rgpdAt != null && disclaimerAt != null;

  ConsentSet copyWith({
    DateTime? rgpdAt,
    DateTime? disclaimerAt,
    DateTime? reminderAt,
    DateTime? newsletterAt,
  }) => ConsentSet(
    rgpdAt: rgpdAt ?? this.rgpdAt,
    disclaimerAt: disclaimerAt ?? this.disclaimerAt,
    reminderAt: reminderAt ?? this.reminderAt,
    newsletterAt: newsletterAt ?? this.newsletterAt,
  );
}
