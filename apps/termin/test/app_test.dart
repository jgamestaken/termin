import 'package:flutter_test/flutter_test.dart';
import 'package:termin/main.dart';

void main() {
  testWidgets('app boots', (tester) async {
    await tester.pumpWidget(const TerminApp());
    expect(find.text('Termin'), findsOneWidget);
  });
}
