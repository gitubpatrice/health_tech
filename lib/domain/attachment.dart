/// Owner-type discriminator for polymorphic ownership.
class AttachmentOwner {
  const AttachmentOwner._();
  static const String client = 'client';
  static const String animal = 'animal';
  static const String session = 'session';
}

/// Stable kind keys so we can later filter attachments per category.
class AttachmentKind {
  const AttachmentKind._();
  static const String photo = 'photo';
  static const String document = 'document';
  static const String vaccination = 'vaccination';
  static const String prescription = 'prescription';
  static const String consent = 'consent';
  static const String other = 'other';

  /// Photo-avatar attachée à un client ou un animal (au plus une à la fois
  /// par couple `(ownerType, ownerId)` — invariant tenu par
  /// `AttachmentRepository.setAvatar`). Volontairement HORS de [all] : ce
  /// `kind` est piloté par un flow dédié (`AvatarPicker`) et ne doit pas
  /// apparaître dans la liste générique des pièces jointes — voir
  /// `AttachmentRepository.watchByOwner(excludeKinds:)`.
  static const String avatar = 'avatar';

  static const List<String> all = [
    photo,
    document,
    vaccination,
    prescription,
    consent,
    other,
  ];
}

class Attachment {
  const Attachment({
    required this.id,
    required this.ownerType,
    required this.ownerId,
    required this.kind,
    required this.filename,
    required this.mimeType,
    required this.sizeBytes,
    required this.storagePath,
    this.createdAt,
  });

  final String id;
  final String ownerType;
  final String ownerId;
  final String kind;
  final String filename;
  final String mimeType;
  final int sizeBytes;
  final String storagePath;
  final DateTime? createdAt;

  bool get isImage => mimeType.startsWith('image/');
}
