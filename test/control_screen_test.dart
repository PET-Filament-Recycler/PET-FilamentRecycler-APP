import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:petfr/models/ble_error.dart';
import 'package:petfr/models/machine_state.dart';
import 'package:petfr/services/ble_service.dart';
import 'package:petfr/services/permission_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'fakes/fake_permission_gateway.dart';
import 'test_helpers.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    BleService.platformCallsEnabled = false;
  });

  tearDown(() {
    BleService.platformCallsEnabled = true;
  });

  group('ControlScreen status display', () {
    testWidgets('shows Unknown before status arrives', (tester) async {
      await pumpControlScreen(tester);

      final label = find.text('Unknown');
      expect(label, findsOneWidget);

      final decoration = statusBadgeDecoration(tester, label);
      expect(decoration.color, Colors.grey.shade100);
    });

    testWidgets('shows ON when machine reports running', (tester) async {
      final ble = await pumpControlScreen(tester);

      ble.emitStatus(MachineState(status: MachineState.statusOn));
      await tester.pump();

      final label = find.text('ON');
      expect(label, findsOneWidget);

      final decoration = statusBadgeDecoration(tester, label);
      expect(decoration.color, Colors.green.shade100);
    });

    testWidgets('shows OFF when machine reports stopped', (tester) async {
      final ble = await pumpControlScreen(tester);

      ble.emitStatus(MachineState(status: MachineState.statusOff));
      await tester.pump();

      final label = find.text('OFF');
      expect(label, findsOneWidget);

      final decoration = statusBadgeDecoration(tester, label);
      expect(decoration.color, Colors.orange.shade100);
    });

    testWidgets('merges partial status updates', (tester) async {
      final ble = await pumpControlScreen(tester);

      ble.emitStatus(
        MachineState(
          temperature: 55,
          speed: 900,
          status: MachineState.statusOn,
        ),
      );
      await tester.pump();

      expect(find.text('55 °C'), findsOneWidget);
      expect(find.text('900'), findsOneWidget);
      expect(find.text('ON'), findsOneWidget);
    });
  });

  group('ControlScreen BLE error localization', () {
    testWidgets('shows English bluetooth-off message', (tester) async {
      final ble = await pumpControlScreen(tester);

      ble.emitError(BleErrorCode.bluetoothOff);
      await tester.pump();

      expect(find.text('Please enable Bluetooth'), findsOneWidget);
    });

    testWidgets('updates error text when locale toggles to Chinese', (
      tester,
    ) async {
      final ble = await pumpControlScreen(tester);

      ble.emitError(BleErrorCode.bluetoothOff);
      await tester.pump();
      expect(find.text('Please enable Bluetooth'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.language_outlined));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('請啟用藍牙'), findsOneWidget);
      expect(find.text('Please enable Bluetooth'), findsNothing);
    });

    testWidgets('localizes scan error detail in both languages', (
      tester,
    ) async {
      final ble = await pumpControlScreen(tester);

      ble.emitError(BleErrorCode.scanError, detail: 'timeout');
      await tester.pump();
      expect(find.text('Scan error: timeout'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.language_outlined));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('掃描錯誤：timeout'), findsOneWidget);
    });
  });

  group('ControlScreen permission denied', () {
    PermissionService deniedPermissionService() {
      final gateway = FakePermissionGateway();
      gateway.statuses = {
        for (final permission in PermissionService.blePermissions)
          permission: PermissionStatus.denied,
      };
      return PermissionService.createForTesting(
        gateway: gateway,
        isAndroid: () => true,
      );
    }

    testWidgets('shows permission denied and skips scan', (tester) async {
      final ble = await pumpControlScreen(
        tester,
        permissionService: deniedPermissionService(),
      );

      expect(find.text('Permission denied'), findsOneWidget);
      expect(find.text('No devices found'), findsNothing);
      expect(ble.startScanCallCount, 0);
    });

    testWidgets('localizes permission denied when locale toggles', (
      tester,
    ) async {
      await pumpControlScreen(
        tester,
        permissionService: deniedPermissionService(),
      );

      expect(find.text('Permission denied'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.language_outlined));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('權限被拒，無法使用藍牙'), findsOneWidget);
      expect(find.text('Permission denied'), findsNothing);
    });
  });
}