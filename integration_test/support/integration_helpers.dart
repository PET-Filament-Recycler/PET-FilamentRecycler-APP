import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petfr/main.dart';

const Duration _settleTimeout = Duration(seconds: 3);
const Duration _permissionWaitTimeout = Duration(seconds: 90);

Future<void> pumpPetFrApp(WidgetTester tester) async {
  await tester.pumpWidget(buildPetFrApp());
  await tester.pumpAndSettle(_settleTimeout);
}

Future<void> openControlPanel(WidgetTester tester) async {
  await tester.tap(find.text('Enter Control Panel'));
  await tester.pump();
  expect(find.text('Control Panel'), findsOneWidget);
  await waitForControlPanelReady(tester);
}

/// Waits for the user to accept Android permission dialogs and for the
/// initial scan pass to finish. Integration tests reinstall the app each run,
/// so the system permission sheet often appears here.
Future<void> waitForControlPanelReady(WidgetTester tester) async {
  final ready = await waitUntil(
    tester,
    () => _isControlPanelReady(tester),
    timeout: _permissionWaitTimeout,
    step: const Duration(milliseconds: 500),
  );

  expect(
    ready,
    isTrue,
    reason:
        'Timed out waiting for BLE permissions/scan. '
        'If a permission dialog is visible, tap Allow. '
        'Or run tool/run_integration_tests.ps1 to pre-grant permissions.',
  );
}

bool _isControlPanelReady(WidgetTester tester) {
  if (find.text('Control Panel').evaluate().isEmpty) return false;
  if (find.text('Permission denied').evaluate().isNotEmpty) return false;
  if (find.text('Please enable Bluetooth').evaluate().isNotEmpty) return false;
  if (find.text('Scanning...').evaluate().isNotEmpty) return false;
  return true;
}

Future<void> exitControlPanel(WidgetTester tester) async {
  await tester.pageBack();
  await tester.pumpAndSettle(const Duration(seconds: 5));
  expect(find.text('PET Recycler Control'), findsOneWidget);
}

Future<bool> waitUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 20),
  Duration step = const Duration(milliseconds: 500),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(step);
    if (condition()) return true;
  }
  return false;
}

Future<bool> waitForScanToFinish(WidgetTester tester) {
  return waitUntil(
    tester,
    () => find.text('Scanning...').evaluate().isEmpty,
    timeout: const Duration(seconds: 25),
  );
}

Future<bool> hasScannedDevice(WidgetTester tester) async {
  await tester.tap(
    find.byWidgetPredicate((widget) => widget is DropdownButtonFormField),
  );
  await tester.pumpAndSettle(_settleTimeout);

  final hasDevice = find.byWidgetPredicate(
    (widget) => widget is DropdownMenuItem,
  ).evaluate().isNotEmpty;

  if (hasDevice) {
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle(_settleTimeout);
  }

  return hasDevice;
}

Future<void> selectFirstScannedDevice(WidgetTester tester) async {
  await tester.tap(
    find.byWidgetPredicate((widget) => widget is DropdownButtonFormField),
  );
  await tester.pumpAndSettle(_settleTimeout);

  final item = find.byWidgetPredicate((widget) => widget is DropdownMenuItem);
  expect(item, findsWidgets);
  await tester.tap(item.first);
  await tester.pumpAndSettle(_settleTimeout);
}

Future<void> tapConnect(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Connect'));
  await tester.pump();
  await waitUntil(
    tester,
    () => find.text('Connecting...').evaluate().isEmpty,
    timeout: const Duration(seconds: 20),
  );
  await tester.pumpAndSettle(_settleTimeout);
}

Future<bool> waitForConnected(WidgetTester tester) {
  return waitUntil(
    tester,
    () => find.text('Connected').evaluate().isNotEmpty,
    timeout: const Duration(seconds: 20),
  );
}

Future<bool> waitForMachineStatus(WidgetTester tester) {
  return waitUntil(
    tester,
    () {
      return find.text('ON').evaluate().isNotEmpty ||
          find.text('OFF').evaluate().isNotEmpty ||
          find.text('Unknown').evaluate().isNotEmpty;
    },
    timeout: const Duration(seconds: 15),
  );
}