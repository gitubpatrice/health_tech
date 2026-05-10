import 'package:drift/drift.dart';

import 'converters.dart';

/// Common columns mixin for soft-delete + audit timestamps.
mixin _AuditCols on Table {
  IntColumn get createdAt =>
      integer().withDefault(currentDateAndTime.unixepoch)();
  IntColumn get updatedAt =>
      integer().withDefault(currentDateAndTime.unixepoch)();
  IntColumn get deletedAt => integer().nullable()();
}

@DataClassName('ClientRow')
class Clients extends Table with _AuditCols {
  TextColumn get id => text().clientDefault(genId)();
  /// `'individual'` (a person) or `'business'` (company / surveyed site).
  /// Drives which form sections render and what `business_json` carries.
  TextColumn get kind =>
      text().withDefault(const Constant('individual'))();
  TextColumn get civility => text().nullable()();
  TextColumn get lastName => text()();
  TextColumn get firstName => text()();
  IntColumn get birthDateMs => integer().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get profession => text().nullable()();

  /// Address as JSON (street, complement, zip, city, region, country).
  /// Stored as JSON to allow new fields without migrations.
  TextColumn get addressJson =>
      text().map(const JsonMapConverter()).withDefault(const Constant(''))();

  /// Business profile (siret, siren, company). Optional.
  TextColumn get businessJson =>
      text().map(const JsonMapConverter()).withDefault(const Constant(''))();

  /// Health notes — encrypted at field level (in addition to SQLCipher).
  /// `null` when no health data has been entered yet.
  TextColumn get healthNotesEncrypted => text().nullable()();

  /// Free notes (also encrypted at field level).
  TextColumn get notesEncrypted => text().nullable()();

  /// Source of contact, lifestyle flags, motives — JSON of cases checked.
  TextColumn get profileJson =>
      text().map(const JsonMapConverter()).withDefault(const Constant(''))();

  IntColumn get consentRgpdAt => integer().nullable()();
  IntColumn get consentDisclaimerAt => integer().nullable()();
  IntColumn get consentReminderAt => integer().nullable()();
  IntColumn get consentNewsletterAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('AnimalRow')
class Animals extends Table with _AuditCols {
  TextColumn get id => text().clientDefault(genId)();
  TextColumn get clientId =>
      text().references(Clients, #id, onDelete: KeyAction.cascade)();
  TextColumn get name => text()();
  TextColumn get species => text()();
  TextColumn get breed => text().nullable()();
  TextColumn get sex => text().nullable()();
  IntColumn get birthDateMs => integer().nullable()();
  IntColumn get weightGrams => integer().nullable()();
  TextColumn get color => text().nullable()();

  /// Identifiers (chip, tattoo, pedigree, vaccinations, vet contact). JSON.
  TextColumn get identifiersJson =>
      text().map(const JsonMapConverter()).withDefault(const Constant(''))();

  TextColumn get healthNotesEncrypted => text().nullable()();
  TextColumn get behaviorNotesEncrypted => text().nullable()();

  TextColumn get profileJson =>
      text().map(const JsonMapConverter()).withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('SessionRow')
class Sessions extends Table with _AuditCols {
  TextColumn get id => text().clientDefault(genId)();
  TextColumn get clientId =>
      text().references(Clients, #id, onDelete: KeyAction.restrict)();
  TextColumn get animalId =>
      text().nullable().references(Animals, #id, onDelete: KeyAction.setNull)();

  IntColumn get startAt => integer()();
  IntColumn get endAt => integer()();

  /// 'human' | 'animal' | 'duo' | 'distance' | 'onsite' | 'home' | 'other'
  TextColumn get kind => text()();
  TextColumn get location => text().nullable()();

  /// 'planned' | 'confirmed' | 'done' | 'cancelled' | 'no_show'
  TextColumn get status => text().withDefault(const Constant('planned'))();

  /// Motives checked (free list of stable keys: 'reiki', 'energetic', ...).
  TextColumn get motivesJson =>
      text().map(const JsonListConverter()).withDefault(const Constant(''))();

  IntColumn get priceCents => integer().nullable()();
  TextColumn get paymentStatus => text().nullable()();
  TextColumn get paymentMethod => text().nullable()();

  /// Structured report as JSON: {before, perceived, observations, during,
  /// zones, energetic, after, advice, next_recommendation}.
  /// Encrypted at field level.
  TextColumn get reportEncrypted => text().nullable()();

  /// Practitioner-only private note (encrypted, never exported).
  TextColumn get privateNoteEncrypted => text().nullable()();

  IntColumn get improvementLevel => integer().nullable()();
  IntColumn get nextSuggestedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('AppointmentRow')
class Appointments extends Table with _AuditCols {
  TextColumn get id => text().clientDefault(genId)();
  TextColumn get clientId =>
      text().nullable().references(Clients, #id, onDelete: KeyAction.setNull)();
  TextColumn get animalId =>
      text().nullable().references(Animals, #id, onDelete: KeyAction.setNull)();
  TextColumn get sessionId => text().nullable().references(
    Sessions,
    #id,
    onDelete: KeyAction.setNull,
  )();

  IntColumn get startAt => integer()();
  IntColumn get endAt => integer()();
  TextColumn get title => text().nullable()();
  TextColumn get location => text().nullable()();
  TextColumn get kind => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('planned'))();
  IntColumn get reminderMinutesBefore => integer().nullable()();

  /// Bridge to the device calendar (device_calendar plugin event id).
  /// Allows two-way sync without losing the link.
  TextColumn get externalCalendarEventId => text().nullable()();
  TextColumn get externalCalendarId => text().nullable()();

  TextColumn get notesEncrypted => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('AttachmentRow')
class Attachments extends Table with _AuditCols {
  TextColumn get id => text().clientDefault(genId)();

  /// 'client' | 'animal' | 'session'
  TextColumn get ownerType => text()();
  TextColumn get ownerId => text()();

  /// 'photo' | 'document' | 'vaccination' | 'prescription' | 'consent' | 'other'
  TextColumn get kind => text()();
  TextColumn get filename => text()();
  TextColumn get mimeType => text()();
  IntColumn get sizeBytes => integer()();

  /// Path under `appSupport/attachments/{uuid}.enc`.
  TextColumn get storagePath => text()();

  /// Per-file random nonce used for AES-GCM (base64).
  TextColumn get nonceB64 => text()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('TagRow')
class Tags extends Table {
  TextColumn get id => text().clientDefault(genId)();
  TextColumn get label => text()();
  IntColumn get colorArgb => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('TagLinkRow')
class TagLinks extends Table {
  TextColumn get tagId =>
      text().references(Tags, #id, onDelete: KeyAction.cascade)();

  /// 'client' | 'animal' | 'session'
  TextColumn get ownerType => text()();
  TextColumn get ownerId => text()();

  @override
  Set<Column> get primaryKey => {tagId, ownerType, ownerId};
}

/// Default ID generator used when callers omit an explicit id at insert time.
/// Repositories should provide their own UUID v4; this is a safety fallback.
String genId() => 'fb-${DateTime.now().microsecondsSinceEpoch}';
