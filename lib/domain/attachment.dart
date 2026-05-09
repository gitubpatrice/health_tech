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
