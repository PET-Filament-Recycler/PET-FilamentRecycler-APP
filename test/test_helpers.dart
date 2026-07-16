import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:petfr/screens/control_screen.dart';
import 'package:petfr/services/ble_service.dart';
import 'package:petfr/services/locale_service.dart';
import 'package:petfr/services/permission_service.dart';
import 'fakes/fake_ble_service.dart';

/// Wraps [child] with the same providers used by the real app.
Widget wrapWithAppProviders(
  Widget child, {
  BleService? bleService,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => LocaleService()),
      ChangeNotifierProvider(create: (_) => bleService ?? BleService()),
    ],
    child: MaterialApp(home: child),
  );
}

/// Pumps [ControlScreen] and returns the injected [FakeBleService].
Future<FakeBleService> pumpControlScreen(
  WidgetTester tester, {
  PermissionService? permissionService,
}) async {
  final ble = FakeBleService();
  await tester.pumpWidget(
    wrapWithAppProviders(
      ControlScreen(permissionService: permissionService),
      bleService: ble,
    ),
  );
  await tester.pump();
  await tester.pump();
  return ble;
}

BoxDecoration statusBadgeDecoration(WidgetTester tester, Finder label) {
  final container = find.ancestor(
    of: label,
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is Container &&
          widget.decoration != null &&
          widget.decoration is BoxDecoration,
    ),
  );
  expect(container, findsOneWidget);
  return tester.widget<Container>(container).decoration! as BoxDecoration;
}