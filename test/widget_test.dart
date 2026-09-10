import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petfr/screens/home_screen.dart';
import 'package:petfr/services/locale_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('App renders home screen', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => LocaleService(),
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    expect(find.text('PET Recycler'), findsOneWidget);
  });
}
