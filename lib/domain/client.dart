import 'address.dart';
import 'consent.dart';

/// Civility — kept as a stable string key (not an enum) so persisted values
/// remain readable if we ever rename the labels in the UI.
class Civility {
  const Civility._();
  static const String mr = 'mr';
  static const String mrs = 'mrs';
  static const String unspecified = 'unspecified';
}

/// Pure domain entity. No Drift, no Flutter — this is what the rest of the
/// app manipulates. Maps to / from `ClientRow` in the data layer.
class Client {
  const Client({
    required this.id,
    required this.lastName,
    required this.firstName,
    this.civility,
    this.birthDate,
    this.phone,
    this.email,
    this.profession,
    this.address = const Address(),
    this.consents = const ConsentSet(),
    this.profile = const <String, dynamic>{},
    this.business = const <String, dynamic>{},
    this.healthNotes = '',
    this.notes = '',
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String? civility;
  final String lastName;
  final String firstName;
  final DateTime? birthDate;
  final String? phone;
  final String? email;
  final String? profession;
  final Address address;
  final ConsentSet consents;

  /// Free-form profile bag (motives checked, lifestyle, source of contact).
  final Map<String, dynamic> profile;

  /// Optional business identity (siret/siren/company).
  final Map<String, dynamic> business;

  /// Decrypted health notes (only populated when caller asked for them).
  final String healthNotes;

  /// Decrypted free notes.
  final String notes;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get fullName => '$firstName $lastName'.trim();

  int? get ageYears {
    final birth = birthDate;
    if (birth == null) return null;
    final now = DateTime.now();
    var age = now.year - birth.year;
    if (now.month < birth.month ||
        (now.month == birth.month && now.day < birth.day)) {
      age -= 1;
    }
    return age < 0 ? null : age;
  }

  Client copyWith({
    String? id,
    String? civility,
    String? lastName,
    String? firstName,
    DateTime? birthDate,
    String? phone,
    String? email,
    String? profession,
    Address? address,
    ConsentSet? consents,
    Map<String, dynamic>? profile,
    Map<String, dynamic>? business,
    String? healthNotes,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Client(
    id: id ?? this.id,
    civility: civility ?? this.civility,
    lastName: lastName ?? this.lastName,
    firstName: firstName ?? this.firstName,
    birthDate: birthDate ?? this.birthDate,
    phone: phone ?? this.phone,
    email: email ?? this.email,
    profession: profession ?? this.profession,
    address: address ?? this.address,
    consents: consents ?? this.consents,
    profile: profile ?? this.profile,
    business: business ?? this.business,
    healthNotes: healthNotes ?? this.healthNotes,
    notes: notes ?? this.notes,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}
