import 'package:flutter_test/flutter_test.dart';

import 'package:naadchitra/main.dart';

void main() {
  testWidgets('Naadchitra app renders scan screen', (WidgetTester tester) async {
    await tester.pumpWidget(const NaadchitraApp());
    await tester.pump();

    // Scan screen chrome renders
    expect(find.text('Naadchitra'), findsWidgets);
    expect(find.text('Gallery'), findsOneWidget);
    expect(find.text('Scan'), findsOneWidget);
  });
}