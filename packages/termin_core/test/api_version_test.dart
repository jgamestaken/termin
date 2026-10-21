import 'package:termin_core/termin_core.dart';
import 'package:test/test.dart';

void main() {
  test('apiVersion is positive', () {
    expect(apiVersion, greaterThan(0));
  });
}
