import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:health_tech/data/db/database.dart';
import 'package:health_tech/data/repositories/appointment_repository.dart';
import 'package:health_tech/data/vault/field_crypto.dart';
import 'package:health_tech/domain/appointment.dart';

void main() {
  late HealthDb db;
  late FieldCrypto crypto;
  late AppointmentRepository repo;

  setUp(() {
    db = HealthDb.forTesting();
    crypto = FieldCrypto(Uint8List.fromList(List.generate(32, (i) => i)));
    repo = AppointmentRepository(db, crypto);
  });

  tearDown(() async {
    await db.close();
  });

  Appointment draft({Duration offset = Duration.zero}) {
    final start = DateTime(2026, 5, 12, 10, 0).add(offset);
    return Appointment(
      id: '',
      startAt: start,
      endAt: start.add(const Duration(minutes: 45)),
      title: 'Bilan énergétique',
      location: 'Cabinet',
      reminderMinutesBefore: 30,
      notes: 'Apporter dossier ostéo',
    );
  }

  test('rejects appointments where end <= start', () async {
    final start = DateTime.now();
    final invalid = Appointment(id: '', startAt: start, endAt: start);
    expect(() => repo.create(invalid), throwsArgumentError);
  });

  test('round-trip preserves encrypted notes', () async {
    final created = await repo.create(draft());
    final fetched = await repo.getById(created.id);
    expect(fetched, isNotNull);
    expect(fetched!.notes, 'Apporter dossier ostéo');
    expect(fetched.title, 'Bilan énergétique');
    expect(fetched.reminderMinutesBefore, 30);
  });

  test('watchUpcoming excludes past entries', () async {
    await repo.create(draft(offset: const Duration(days: -10)));
    final fut = await repo.create(draft(offset: const Duration(days: 30)));
    final list = await repo.watchUpcoming().first;
    expect(list.where((a) => a.id == fut.id), isNotEmpty);
    expect(
      list.every((a) => a.startAt.isAfter(
            DateTime.now().subtract(const Duration(minutes: 1)),
          )),
      isTrue,
    );
  });

  test('watchInRange filters correctly', () async {
    await repo.create(draft());
    await repo.create(draft(offset: const Duration(days: 100)));
    final list = await repo
        .watchInRange(DateTime(2026, 5, 1), DateTime(2026, 5, 31))
        .first;
    expect(list.length, 1);
  });
}
