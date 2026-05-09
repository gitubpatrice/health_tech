import 'package:flutter_test/flutter_test.dart';
import 'package:health_tech/widgets/breakpoints.dart';

void main() {
  group('Breakpoints', () {
    test('compact maps below 600 dp', () {
      expect(Breakpoints.compactMax, 600);
      expect(Breakpoints.mediumMax, 840);
      expect(Breakpoints.compactMax < Breakpoints.mediumMax, isTrue);
    });
  });
}
