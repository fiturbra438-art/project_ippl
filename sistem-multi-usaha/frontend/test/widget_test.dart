import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_multi_usaha/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const MultiUsahaApp());
    expect(find.text('MultiUsaha'), findsWidgets);
  });
}
