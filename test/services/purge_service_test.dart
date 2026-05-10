import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:health_tech/data/db/database.dart';
import 'package:health_tech/data/repositories/animal_repository.dart';
import 'package:health_tech/data/repositories/appointment_repository.dart';
import 'package:health_tech/data/repositories/attachment_repository.dart';
import 'package:health_tech/data/repositories/client_repository.dart';
import 'package:health_tech/data/repositories/session_repository.dart';
import 'package:health_tech/data/services/notification_service.dart';
import 'package:health_tech/data/services/purge_service.dart';
import 'package:health_tech/data/services/system_calendar_bridge.dart';
import 'package:health_tech/data/vault/field_crypto.dart';
import 'package:health_tech/domain/animal.dart';
import 'package:health_tech/domain/appointment.dart';
import 'package:health_tech/domain/client.dart';
import 'package:health_tech/domain/consent.dart';
import 'package:health_tech/domain/session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HealthDb db;
  late FieldCrypto crypto;
  late ClientRepository clients;
  late AnimalRepository animals;
  late SessionRepository sessions;
  late AppointmentRepository appointments;
  late PurgeService purge;

  setUp(() {
    db = HealthDb.forTesting();
    crypto = FieldCrypto(Uint8List.fromList(List.generate(32, (i) => i)));
    clients = ClientRepository(db, crypto);
    animals = AnimalRepository(db, crypto);
    sessions = SessionRepository(db, crypto);
    appointments = AppointmentRepository(db, crypto);
    purge = PurgeService(
      clients: clients,
      animals: animals,
      sessions: sessions,
      appointments: appointments,
      attachments: AttachmentRepository(db, crypto),
      // Le NotificationService et le SystemCalendarBridge tapent dans
      // des plugins natifs qui ne sont pas montés en test. Ils sont déjà
      // robustes : tout l'appel est swallowed au niveau PurgeService.
      // On passe donc des instances réelles, et on vérifie que les delete
      // DB se font malgré l'absence du plugin.
      notifications: NotificationService(),
      calendar: SystemCalendarBridge(),
    );
  });

  tearDown(() async {
    await db.close();
  });

  Future<Client> mkClient(String name) async {
    final now = DateTime.now();
    return clients.create(
      Client(
        id: '',
        kind: ClientKind.individual,
        lastName: name,
        firstName: name,
        consents: ConsentSet(rgpdAt: now, disclaimerAt: now),
      ),
    );
  }

  Future<Animal> mkAnimal(String clientId, String name) async {
    return animals.create(
      Animal(id: '', clientId: clientId, name: name, species: 'dog'),
    );
  }

  Future<Session> mkSession({
    required String clientId,
    String? animalId,
    DateTime? when,
  }) async {
    final start = when ?? DateTime.now();
    return sessions.create(
      Session(
        id: '',
        clientId: clientId,
        animalId: animalId,
        startAt: start,
        endAt: start.add(const Duration(hours: 1)),
        kind: 'reiki',
      ),
    );
  }

  Future<Appointment> mkAppt(String clientId, {String? animalId}) async {
    final start = DateTime.now().add(const Duration(days: 1));
    return appointments.create(
      Appointment(
        id: '',
        clientId: clientId,
        animalId: animalId,
        startAt: start,
        endAt: start.add(const Duration(hours: 1)),
        title: 'consultation',
      ),
    );
  }

  group('softDeleteClient', () {
    test('cascade animaux + sessions + appointments', () async {
      final c = await mkClient('Dupont');
      final a = await mkAnimal(c.id, 'Rex');
      final s = await mkSession(clientId: c.id, animalId: a.id);
      final apt = await mkAppt(c.id, animalId: a.id);

      await purge.softDeleteClient(c.id);

      expect(await clients.getById(c.id), isNull);
      expect(await animals.getById(a.id), isNull);
      expect(await sessions.getById(s.id), isNull);
      expect(await appointments.getById(apt.id), isNull);
    });

    test('appointments standalone (sans animal) sont aussi cascadés', () async {
      final c = await mkClient('Martin');
      final apt = await mkAppt(c.id);

      await purge.softDeleteClient(c.id);

      expect(await appointments.getById(apt.id), isNull);
    });
  });

  group('softDeleteAnimal', () {
    test('cascade sessions de cet animal mais pas du client', () async {
      final c = await mkClient('Dupont');
      final a = await mkAnimal(c.id, 'Rex');
      final humanSession = await mkSession(clientId: c.id);
      final animalSession = await mkSession(clientId: c.id, animalId: a.id);

      await purge.softDeleteAnimal(a.id);

      expect(await animals.getById(a.id), isNull);
      expect(
        await sessions.getById(animalSession.id),
        isNull,
        reason: 'session animal cascadée',
      );
      expect(
        await sessions.getById(humanSession.id),
        isNotNull,
        reason: 'session human laissée intacte',
      );
      expect(
        await clients.getById(c.id),
        isNotNull,
        reason: 'le client parent reste',
      );
    });

    test('cascade appointments de cet animal seulement', () async {
      final c = await mkClient('Martin');
      final a = await mkAnimal(c.id, 'Whiskers');
      final humanAppt = await mkAppt(c.id);
      final animalAppt = await mkAppt(c.id, animalId: a.id);

      await purge.softDeleteAnimal(a.id);

      expect(await appointments.getById(animalAppt.id), isNull);
      expect(
        await appointments.getById(humanAppt.id),
        isNotNull,
        reason: 'appt human reste',
      );
    });
  });

  group('purgeClient (hard delete)', () {
    test('purge complète DB + cascade animaux/sessions/appointments', () async {
      final c = await mkClient('Bernard');
      final a = await mkAnimal(c.id, 'Felix');
      final s = await mkSession(clientId: c.id, animalId: a.id);
      final apt = await mkAppt(c.id);

      await purge.purgeClient(c.id);

      // Hard-delete : pas seulement getById qui filtre deletedAt — les
      // rows sont vraiment parties. On vérifie via une requête directe.
      final clientRows = await db.select(db.clients).get();
      final animalRows = await db.select(db.animals).get();
      final sessionRows = await db.select(db.sessions).get();
      final apptRows = await db.select(db.appointments).get();
      expect(clientRows.where((r) => r.id == c.id), isEmpty);
      expect(animalRows.where((r) => r.id == a.id), isEmpty);
      expect(sessionRows.where((r) => r.id == s.id), isEmpty);
      expect(apptRows.where((r) => r.id == apt.id), isEmpty);
    });
  });
}
