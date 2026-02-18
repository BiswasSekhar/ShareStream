import 'package:flutter_test/flutter_test.dart';
import 'package:sharestream/main.dart';

void main() {
  testWidgets('ShareStream app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ShareStreamApp());
    expect(find.text('ShareStream'), findsOneWidget);
  });
}
