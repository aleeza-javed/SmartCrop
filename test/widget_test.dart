import 'package:flutter_test/flutter_test.dart';
import 'package:smart_crop/main.dart';

void main() {
  testWidgets('App launches smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const SmartCropApp());
    expect(find.text('SmartCrop'), findsWidgets);
  });
}
