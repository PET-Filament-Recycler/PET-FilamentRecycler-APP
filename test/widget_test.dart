import 'package:flutter_test/flutter_test.dart';
import 'package:petfr/screens/home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'test_helpers.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('App renders home screen', (WidgetTester tester) async {
    await tester.pumpWidget(wrapWithAppProviders(const HomeScreen()));
    await tester.pump();

    expect(find.text('PET Recycler'), findsOneWidget);
    expect(find.text('PET Recycler Control'), findsOneWidget);
  });
}