import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../domain/animal.dart';
import '../../domain/appointment.dart';
import '../../domain/attachment.dart';
import '../../domain/client.dart';
import '../../domain/session.dart';
import '../repositories/animal_repository.dart';
import '../repositories/appointment_repository.dart';
import '../repositories/attachment_repository.dart';
import '../repositories/client_repository.dart';
import '../repositories/session_repository.dart';

/// Builds the GDPR Article 15 portability bundle for a single client:
/// a ZIP containing every record (decrypted, JSON) plus every attachment in
/// its original cleartext form. The caller is expected to share the ZIP via
/// `share_plus` so the user controls where it lands.
///
/// Note: the ZIP is produced in cleartext on purpose (the user is exporting
/// their OWN data and will hand it over outside the app). Health Tech never
/// writes this archive to a persistent location on its own — only to the
/// system share sheet.
class RgpdExportService {
  RgpdExportService({
    required this.clients,
    required this.animals,
    required this.sessions,
    required this.appointments,
    required this.attachments,
  });

  final ClientRepository clients;
  final AnimalRepository animals;
  final SessionRepository sessions;
  final AppointmentRepository appointments;
  final AttachmentRepository attachments;

  Future<Uint8List> exportClient(String clientId) async {
    final client = await clients.getById(clientId);
    if (client == null) {
      throw ArgumentError.value(clientId, 'clientId', 'Client not found');
    }

    final clientAnimals = await animals.watchByClient(clientId).first;
    final clientSessions = await sessions.watchByClient(clientId).first;
    // Re-fetch sessions in full so encrypted fields are decrypted.
    final fullSessions = <Session>[];
    for (final s in clientSessions) {
      final full = await sessions.getById(s.id);
      if (full != null) fullSessions.add(full);
    }

    final fullAnimals = <Animal>[];
    for (final a in clientAnimals) {
      final full = await animals.getById(a.id);
      if (full != null) fullAnimals.add(full);
    }

    final clientAttachments = await attachments
        .watchByOwner(
          ownerType: AttachmentOwner.client,
          ownerId: clientId,
        )
        .first;
    final allAttachments = <Attachment>[...clientAttachments];
    for (final a in fullAnimals) {
      final list = await attachments
          .watchByOwner(
            ownerType: AttachmentOwner.animal,
            ownerId: a.id,
          )
          .first;
      allAttachments.addAll(list);
    }
    for (final s in fullSessions) {
      final list = await attachments
          .watchByOwner(
            ownerType: AttachmentOwner.session,
            ownerId: s.id,
          )
          .first;
      allAttachments.addAll(list);
    }

    final archive = Archive();

    // Manifest first, useful for any RGPD recipient.
    final pkg = await _packageInfo();
    final manifest = <String, dynamic>{
      'health_tech_version': '${pkg.version}+${pkg.buildNumber}',
      'exported_at_utc': DateTime.now().toUtc().toIso8601String(),
      'gdpr_article': 15,
      'subject_client_id': clientId,
      'counts': {
        'animals': fullAnimals.length,
        'sessions': fullSessions.length,
        'attachments': allAttachments.length,
      },
      'note':
          'This archive is the practitioner-issued GDPR portability bundle. '
              'Sensitive fields (health notes, session reports, attachments) '
              'have been decrypted. Treat this archive as confidential.',
    };
    _addJson(archive, 'manifest.json', manifest);

    _addJson(archive, 'client.json', _clientToJson(client));
    if (fullAnimals.isNotEmpty) {
      _addJson(
        archive,
        'animals.json',
        fullAnimals.map(_animalToJson).toList(),
      );
    }
    if (fullSessions.isNotEmpty) {
      _addJson(
        archive,
        'sessions.json',
        fullSessions.map(_sessionToJson).toList(),
      );
    }

    final clientAppointments =
        await appointments.watchByClient(clientId).first;
    if (clientAppointments.isNotEmpty) {
      _addJson(
        archive,
        'appointments.json',
        clientAppointments.map(_appointmentToJson).toList(),
      );
    }

    // Attachments — write decrypted bytes under a stable folder per owner.
    // The recipient of this archive (client, DPO, regulator) extracts it on
    // their own machine, so we MUST sanitise filename to defeat zip-slip:
    // a malicious filename like `../../../Downloads/x.pdf` would otherwise
    // let an extracted entry escape the destination directory.
    for (final att in allAttachments) {
      final bytes = await attachments.readBytes(att.id);
      final folder = switch (att.ownerType) {
        AttachmentOwner.client => 'attachments/client',
        AttachmentOwner.animal => 'attachments/animal-${att.ownerId}',
        AttachmentOwner.session => 'attachments/session-${att.ownerId}',
        _ => 'attachments/other',
      };
      final safeName = att.filename
          .split(RegExp(r'[\\/]'))
          .last
          .replaceAll(RegExp(r'[^\w\s\-.]'), '_');
      archive.addFile(
        ArchiveFile('$folder/${att.id}-$safeName', bytes.length, bytes),
      );
    }

    final encoded = ZipEncoder().encode(archive);
    return Uint8List.fromList(encoded);
  }

  // -- domain → JSON --------------------------------------------------------

  Map<String, dynamic> _clientToJson(Client c) => {
        'id': c.id,
        'civility': c.civility,
        'last_name': c.lastName,
        'first_name': c.firstName,
        'birth_date': c.birthDate?.toIso8601String(),
        'phone': c.phone,
        'email': c.email,
        'profession': c.profession,
        'address': c.address.toJson(),
        'business': c.business,
        'profile': c.profile,
        'health_notes': c.healthNotes,
        'notes': c.notes,
        'consents': {
          'rgpd_at': c.consents.rgpdAt?.toIso8601String(),
          'disclaimer_at': c.consents.disclaimerAt?.toIso8601String(),
          'reminder_at': c.consents.reminderAt?.toIso8601String(),
          'newsletter_at': c.consents.newsletterAt?.toIso8601String(),
        },
        'created_at': c.createdAt?.toIso8601String(),
        'updated_at': c.updatedAt?.toIso8601String(),
      };

  Map<String, dynamic> _animalToJson(Animal a) => {
        'id': a.id,
        'client_id': a.clientId,
        'name': a.name,
        'species': a.species,
        'breed': a.breed,
        'sex': a.sex,
        'birth_date': a.birthDate?.toIso8601String(),
        'weight_grams': a.weightGrams,
        'color': a.color,
        'identifiers': a.identifiers.toJson(),
        'health_notes': a.healthNotes,
        'behavior_notes': a.behaviorNotes,
        'profile': a.profile,
        'created_at': a.createdAt?.toIso8601String(),
        'updated_at': a.updatedAt?.toIso8601String(),
      };

  /// Sessions export DOES NOT include the practitioner private note (it is
  /// internal and never shared, even under GDPR).
  Map<String, dynamic> _sessionToJson(Session s) => {
        'id': s.id,
        'client_id': s.clientId,
        'animal_id': s.animalId,
        'start_at': s.startAt.toIso8601String(),
        'end_at': s.endAt.toIso8601String(),
        'kind': s.kind,
        'location': s.location,
        'status': s.status,
        'motives': s.motives,
        'price_cents': s.priceCents,
        'payment_status': s.paymentStatus,
        'payment_method': s.paymentMethod,
        'report': s.report.toJson(),
        'improvement_level': s.improvementLevel,
        'next_suggested_at': s.nextSuggestedAt?.toIso8601String(),
        'created_at': s.createdAt?.toIso8601String(),
        'updated_at': s.updatedAt?.toIso8601String(),
      };

  Map<String, dynamic> _appointmentToJson(Appointment a) => {
        'id': a.id,
        'client_id': a.clientId,
        'animal_id': a.animalId,
        'session_id': a.sessionId,
        'start_at': a.startAt.toIso8601String(),
        'end_at': a.endAt.toIso8601String(),
        'title': a.title,
        'location': a.location,
        'status': a.status,
        'reminder_minutes_before': a.reminderMinutesBefore,
      };

  /// Tests can override this to avoid plugin init in unit tests.
  Future<PackageInfo> Function() _packageInfo = PackageInfo.fromPlatform;

  /// For tests: replace the PackageInfo loader with a deterministic stub.
  // ignore: use_setters_to_change_properties
  void overridePackageInfoLoader(Future<PackageInfo> Function() loader) {
    _packageInfo = loader;
  }

  void _addJson(Archive archive, String path, Object data) {
    final json = const JsonEncoder.withIndent('  ').convert(data);
    final bytes = utf8.encode(json);
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  }
}
