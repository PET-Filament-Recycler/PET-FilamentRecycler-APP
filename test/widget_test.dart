import 'package:flutter_test/flutter_test.dart';
import 'package:petfr/screens/home_screen.dart';

void main() {
  testWidgets('App renders home screen', (WidgetTester tester) async {
    await tester.pumpWidget(const HomeScreen());
    expect(find.text('PET Recycler'), findsOneWidget);
  });
}
