/// Stable string keys for the species. Persisting strings (rather than enum
/// indices) keeps DB readable and avoids breakage when we add new species.
class Species {
  const Species._();
  static const String dog = 'dog';
  static const String cat = 'cat';
  static const String horse = 'horse';
  static const String bird = 'bird';
  static const String rodent = 'rodent';
  static const String reptile = 'reptile';
  static const String other = 'other';

  static const List<String> all = [
    dog,
    cat,
    horse,
    bird,
    rodent,
    reptile,
    other,
  ];
}

class AnimalSex {
  const AnimalSex._();
  static const String male = 'male';
  static const String female = 'female';
  static const String maleNeutered = 'male_neutered';
  static const String femaleSpayed = 'female_spayed';
  static const String unknown = 'unknown';
}

/// Identifiers bag — kept extensible via JSON. Empty fields are not persisted.
class AnimalIdentifiers {
  const AnimalIdentifiers({
    this.chipNumber = '',
    this.tattooNumber = '',
    this.pedigreeNumber = '',
    this.lastVaccinationAt,
    this.vetName = '',
    this.vetPhone = '',
    this.vetEmail = '',
  });

  final String chipNumber;
  final String tattooNumber;
  final String pedigreeNumber;
  final DateTime? lastVaccinationAt;
  final String vetName;
  final String vetPhone;
  final String vetEmail;

  bool get isEmpty =>
      chipNumber.isEmpty &&
      tattooNumber.isEmpty &&
      pedigreeNumber.isEmpty &&
      lastVaccinationAt == null &&
      vetName.isEmpty &&
      vetPhone.isEmpty &&
      vetEmail.isEmpty;

  AnimalIdentifiers copyWith({
    String? chipNumber,
    String? tattooNumber,
    String? pedigreeNumber,
    DateTime? lastVaccinationAt,
    String? vetName,
    String? vetPhone,
    String? vetEmail,
  }) => AnimalIdentifiers(
    chipNumber: chipNumber ?? this.chipNumber,
    tattooNumber: tattooNumber ?? this.tattooNumber,
    pedigreeNumber: pedigreeNumber ?? this.pedigreeNumber,
    lastVaccinationAt: lastVaccinationAt ?? this.lastVaccinationAt,
    vetName: vetName ?? this.vetName,
    vetPhone: vetPhone ?? this.vetPhone,
    vetEmail: vetEmail ?? this.vetEmail,
  );

  Map<String, dynamic> toJson() => {
    if (chipNumber.isNotEmpty) 'chip': chipNumber,
    if (tattooNumber.isNotEmpty) 'tattoo': tattooNumber,
    if (pedigreeNumber.isNotEmpty) 'pedigree': pedigreeNumber,
    if (lastVaccinationAt != null)
      'last_vaccin_ms': lastVaccinationAt!.millisecondsSinceEpoch,
    if (vetName.isNotEmpty) 'vet_name': vetName,
    if (vetPhone.isNotEmpty) 'vet_phone': vetPhone,
    if (vetEmail.isNotEmpty) 'vet_email': vetEmail,
  };

  static AnimalIdentifiers fromJson(Map<String, dynamic> json) {
    final ms = json['last_vaccin_ms'] as int?;
    return AnimalIdentifiers(
      chipNumber: json['chip'] as String? ?? '',
      tattooNumber: json['tattoo'] as String? ?? '',
      pedigreeNumber: json['pedigree'] as String? ?? '',
      lastVaccinationAt: ms == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(ms),
      vetName: json['vet_name'] as String? ?? '',
      vetPhone: json['vet_phone'] as String? ?? '',
      vetEmail: json['vet_email'] as String? ?? '',
    );
  }
}

class Animal {
  const Animal({
    required this.id,
    required this.clientId,
    required this.name,
    required this.species,
    this.breed,
    this.sex,
    this.birthDate,
    this.weightGrams,
    this.color,
    this.identifiers = const AnimalIdentifiers(),
    this.healthNotes = '',
    this.behaviorNotes = '',
    this.profile = const <String, dynamic>{},
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String clientId;
  final String name;
  final String species;
  final String? breed;
  final String? sex;
  final DateTime? birthDate;
  final int? weightGrams;
  final String? color;
  final AnimalIdentifiers identifiers;
  final String healthNotes;
  final String behaviorNotes;
  final Map<String, dynamic> profile;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  double? get weightKg => weightGrams == null ? null : weightGrams! / 1000.0;

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

  Animal copyWith({
    String? id,
    String? clientId,
    String? name,
    String? species,
    String? breed,
    String? sex,
    DateTime? birthDate,
    int? weightGrams,
    String? color,
    AnimalIdentifiers? identifiers,
    String? healthNotes,
    String? behaviorNotes,
    Map<String, dynamic>? profile,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Animal(
    id: id ?? this.id,
    clientId: clientId ?? this.clientId,
    name: name ?? this.name,
    species: species ?? this.species,
    breed: breed ?? this.breed,
    sex: sex ?? this.sex,
    birthDate: birthDate ?? this.birthDate,
    weightGrams: weightGrams ?? this.weightGrams,
    color: color ?? this.color,
    identifiers: identifiers ?? this.identifiers,
    healthNotes: healthNotes ?? this.healthNotes,
    behaviorNotes: behaviorNotes ?? this.behaviorNotes,
    profile: profile ?? this.profile,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}
