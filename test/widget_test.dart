import 'package:flutter_test/flutter_test.dart';
import 'package:secure_chat/main.dart';

void main() {
  testWidgets('App initializes successfully smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const SecureChatApp());

    // Verify that the splash screen is built and contains 'Secret Chat'
    expect(find.text('Secret Chat'), findsOneWidget);
  });
}
