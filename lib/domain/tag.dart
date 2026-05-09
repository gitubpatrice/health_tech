/// Stable owner-type discriminator (mirrors AttachmentOwner). Tags are
/// polymorphic — same tag can be linked to a client, an animal or a session.
class TagOwner {
  const TagOwner._();
  static const String client = 'client';
  static const String animal = 'animal';
  static const String session = 'session';
}

class Tag {
  const Tag({required this.id, required this.label, this.colorArgb});

  final String id;
  final String label;
  final int? colorArgb;

  Tag copyWith({String? label, int? colorArgb}) => Tag(
    id: id,
    label: label ?? this.label,
    colorArgb: colorArgb ?? this.colorArgb,
  );
}
