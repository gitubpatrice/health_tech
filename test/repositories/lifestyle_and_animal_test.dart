import 'package:flutter_test/flutter_test.dart';
import 'package:health_tech/domain/animal.dart';
import 'package:health_tech/domain/lifestyle.dart';

void main() {
  group('ClientProfileExt — source / emergency / lifestyle', () {
    test('writeString écrit puis retire la clé sur null/empty', () {
      var p = <String, dynamic>{};
      p = ClientProfileExt.writeString(p, ContactSource.key, 'website');
      expect(ClientProfileExt.contactSource(p), 'website');
      p = ClientProfileExt.writeString(p, ContactSource.key, null);
      expect(ClientProfileExt.contactSource(p), isNull);
      expect(p.containsKey(ContactSource.key), false);
    });

    test('writeEmergencyContact retire le bloc si tout est vide', () {
      var p = <String, dynamic>{};
      p = ClientProfileExt.writeEmergencyContact(
        p,
        name: 'Marie',
        phone: '0600000000',
      );
      expect(ClientProfileExt.emergencyContactName(p), 'Marie');
      expect(ClientProfileExt.emergencyContactPhone(p), '0600000000');
      p = ClientProfileExt.writeEmergencyContact(p, name: '', phone: '');
      expect(ClientProfileExt.emergencyContactName(p), isNull);
      expect(ClientProfileExt.emergencyContactPhone(p), isNull);
    });

    test('writeLifestyle ne persiste que les axes renseignés', () {
      var p = <String, dynamic>{};
      p = ClientProfileExt.writeLifestyle(
        p,
        smoker: Lifestyle.smokerNo,
        sport: null,
        sleep: '',
        stress: Lifestyle.stressLow,
        diet: null,
      );
      expect(
        ClientProfileExt.lifestyle(p, Lifestyle.keySmoker),
        Lifestyle.smokerNo,
      );
      expect(ClientProfileExt.lifestyle(p, Lifestyle.keySport), isNull);
      expect(ClientProfileExt.lifestyle(p, Lifestyle.keySleep), isNull);
      expect(
        ClientProfileExt.lifestyle(p, Lifestyle.keyStress),
        Lifestyle.stressLow,
      );
      expect(ClientProfileExt.lifestyle(p, Lifestyle.keyDiet), isNull);
      expect(ClientProfileExt.hasLifestyle(p), true);
    });

    test('hasLifestyle false sur map vide / bloc vidé', () {
      expect(ClientProfileExt.hasLifestyle(const <String, dynamic>{}), false);
      final p = ClientProfileExt.writeLifestyle(
        <String, dynamic>{},
        smoker: '',
        sport: '',
        sleep: '',
        stress: '',
        diet: '',
      );
      expect(ClientProfileExt.hasLifestyle(p), false);
    });
  });

  group('AnimalIdentifiers — vet + vaccination étendus', () {
    test(
      'toJson / fromJson preserves vetClinic, nextVaccin, vaccinationNotes',
      () {
        final id = AnimalIdentifiers(
          chipNumber: '250268500000000',
          vetName: 'Dr Cohen',
          vetClinic: 'Clinique des Lilas',
          vetPhone: '0102030405',
          vetEmail: 'cohen@example.org',
          lastVaccinationAt: DateTime(2025, 6, 1),
          nextVaccinationAt: DateTime(2026, 6, 1),
          vaccinationNotes: 'Rappel CHPPiL recommandé.',
        );
        final round = AnimalIdentifiers.fromJson(id.toJson());
        expect(round.chipNumber, id.chipNumber);
        expect(round.vetName, id.vetName);
        expect(round.vetClinic, id.vetClinic);
        expect(round.vetPhone, id.vetPhone);
        expect(round.vetEmail, id.vetEmail);
        expect(round.lastVaccinationAt, id.lastVaccinationAt);
        expect(round.nextVaccinationAt, id.nextVaccinationAt);
        expect(round.vaccinationNotes, id.vaccinationNotes);
      },
    );

    test('hasVet / hasVaccination flags', () {
      const empty = AnimalIdentifiers();
      expect(empty.hasVet, false);
      expect(empty.hasVaccination, false);
      const vetOnly = AnimalIdentifiers(vetClinic: 'X');
      expect(vetOnly.hasVet, true);
      expect(vetOnly.hasVaccination, false);
      final vaccOnly = AnimalIdentifiers(nextVaccinationAt: DateTime(2030));
      expect(vaccOnly.hasVet, false);
      expect(vaccOnly.hasVaccination, true);
    });

    test('nextVaccinationOverdue reflète comparaison avec now', () {
      final past = AnimalIdentifiers(
        nextVaccinationAt: DateTime.now().subtract(const Duration(days: 5)),
      );
      final future = AnimalIdentifiers(
        nextVaccinationAt: DateTime.now().add(const Duration(days: 5)),
      );
      const none = AnimalIdentifiers();
      expect(past.nextVaccinationOverdue, true);
      expect(future.nextVaccinationOverdue, false);
      expect(none.nextVaccinationOverdue, false);
    });

    test('rétro-compat : ancien JSON sans clés v1.6.0 lit toujours', () {
      final id = AnimalIdentifiers.fromJson(const {
        'chip': '123',
        'vet_name': 'Dr Old',
        'vet_phone': '0102030405',
      });
      expect(id.chipNumber, '123');
      expect(id.vetName, 'Dr Old');
      expect(id.vetClinic, '');
      expect(id.nextVaccinationAt, isNull);
      expect(id.vaccinationNotes, '');
    });
  });
}
