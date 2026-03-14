import 'package:flutter_test/flutter_test.dart';
import 'package:ai_calendar/app.dart';

void main() {
  testWidgets('App loads', (WidgetTester tester) async {
    await tester.pumpWidget(const AiCalendarApp());
    await tester.pump();
  });
}
