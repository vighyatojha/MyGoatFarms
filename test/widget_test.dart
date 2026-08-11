import 'package:flutter_test/flutter_test.dart';
import 'package:mygoatfarms/main.dart';

void main() {
  testWidgets('MyGoatFarms app starts successfully', (WidgetTester tester) async {
    await tester.pumpWidget(const MyGoatFarmsApp());

    // Allow the initial widgets/animations to build.
    await tester.pump();

    // Verify that the application starts.
    expect(find.byType(MyGoatFarmsApp), findsOneWidget);
  });
}