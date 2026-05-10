import 'package:flutter_test/flutter_test.dart';
import 'package:health_tech/data/services/notification_service.dart';
import 'package:uuid/uuid.dart';

void main() {
  group('NotificationService.idForTesting', () {
    test('FNV-1a est déterministe et stable', () {
      const sample = 'a3f4c8d1-2e5b-4f9a-8c7d-1234567890ab';
      final a = NotificationService.idForTesting(sample);
      final b = NotificationService.idForTesting(sample);
      expect(a, b);
    });

    test('reste positif (NotificationManager rejette les ids négatifs)', () {
      const uuid = Uuid();
      for (var i = 0; i < 1000; i++) {
        final id = NotificationService.idForTesting(uuid.v4());
        expect(id, greaterThanOrEqualTo(0));
        expect(id, lessThan(1 << 31));
      }
    });

    test('aucune collision sur 5 000 UUIDs (cible métier réaliste)', () {
      // Paradoxe des anniversaires sur 31 bits :
      //   P(collision | N=50000) ≈ 44%  → flaky test
      //   P(collision | N=10000) ≈ 2.3%
      //   P(collision | N=5000)  ≈ 0.6%
      // Un praticien typique a < 1000 RDV vivants à un instant T.
      // 5000 valide largement la cible métier sans flake. Si la
      // distribution FNV se dégrade (un hash bidon collisionnerait
      // bien plus tôt), ce test détectera la régression.
      const uuid = Uuid();
      final seen = <int>{};
      for (var i = 0; i < 5000; i++) {
        final id = NotificationService.idForTesting(uuid.v4());
        expect(seen.add(id), isTrue, reason: 'collision détectée');
      }
    });

    test('UUIDs proches en string -> ids très différents (avalanche)', () {
      // FNV-1a doit avoir un effet d'avalanche : changer 1 caractère
      // dans le UUID doit produire un id complètement différent (mesuré
      // par la distance de Hamming sur les 31 bits).
      final a = NotificationService.idForTesting(
        'a3f4c8d1-2e5b-4f9a-8c7d-1234567890ab',
      );
      final b = NotificationService.idForTesting(
        'a3f4c8d1-2e5b-4f9a-8c7d-1234567890ac',
      );
      // Distance de Hamming entre a et b : on attend > 5 bits flippés.
      var diff = 0;
      var xor = a ^ b;
      while (xor != 0) {
        diff += xor & 1;
        xor >>= 1;
      }
      expect(diff, greaterThan(5));
    });
  });
}
