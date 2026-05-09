/// Pure domain value object. Stable serialisation so we can extend it without
/// migrating the DB (the row stores it as JSON).
class Address {
  const Address({
    this.street = '',
    this.complement = '',
    this.zipCode = '',
    this.city = '',
    this.region = '',
    this.country = 'FR',
  });

  final String street;
  final String complement;
  final String zipCode;
  final String city;
  final String region;
  final String country;

  bool get isEmpty =>
      street.isEmpty &&
      complement.isEmpty &&
      zipCode.isEmpty &&
      city.isEmpty &&
      region.isEmpty;

  Address copyWith({
    String? street,
    String? complement,
    String? zipCode,
    String? city,
    String? region,
    String? country,
  }) => Address(
    street: street ?? this.street,
    complement: complement ?? this.complement,
    zipCode: zipCode ?? this.zipCode,
    city: city ?? this.city,
    region: region ?? this.region,
    country: country ?? this.country,
  );

  Map<String, dynamic> toJson() => {
    if (street.isNotEmpty) 'street': street,
    if (complement.isNotEmpty) 'complement': complement,
    if (zipCode.isNotEmpty) 'zip': zipCode,
    if (city.isNotEmpty) 'city': city,
    if (region.isNotEmpty) 'region': region,
    if (country.isNotEmpty) 'country': country,
  };

  static Address fromJson(Map<String, dynamic> json) => Address(
    street: json['street'] as String? ?? '',
    complement: json['complement'] as String? ?? '',
    zipCode: json['zip'] as String? ?? '',
    city: json['city'] as String? ?? '',
    region: json['region'] as String? ?? '',
    country: json['country'] as String? ?? 'FR',
  );
}
