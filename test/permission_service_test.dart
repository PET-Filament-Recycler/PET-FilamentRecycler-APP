import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:petfr/services/permission_service.dart';
import 'fakes/fake_permission_gateway.dart';

void main() {
  group('PermissionService.requestBlePermissions', () {
    late FakePermissionGateway gateway;

    PermissionService service({required bool isAndroid}) {
      return PermissionService.createForTesting(
        gateway: gateway,
        isAndroid: () => isAndroid,
      );
    }

    setUp(() {
      gateway = FakePermissionGateway();
    });

    test('hasBlePermissions mirrors gateway statuses', () async {
      gateway.statuses = {
        Permission.bluetoothScan: PermissionStatus.granted,
        Permission.bluetoothConnect: PermissionStatus.granted,
        Permission.location: PermissionStatus.denied,
      };

      final granted = await service(isAndroid: true).hasBlePermissions();

      expect(granted, isFalse);
    });

    test('returns true on non-Android without requesting permissions', () async {
      final granted = await service(isAndroid: false).requestBlePermissions();

      expect(granted, isTrue);
      expect(gateway.lastRequested, isNull);
      expect(gateway.openSettingsCalled, isFalse);
    });

    test('returns true when all BLE permissions are granted', () async {
      gateway.statuses = {
        for (final permission in PermissionService.blePermissions)
          permission: PermissionStatus.granted,
      };

      final granted = await service(isAndroid: true).requestBlePermissions();

      expect(granted, isTrue);
      expect(gateway.lastRequested, PermissionService.blePermissions);
      expect(gateway.openSettingsCalled, isFalse);
    });

    test('returns false when any permission is denied', () async {
      gateway.statuses = {
        Permission.bluetoothScan: PermissionStatus.granted,
        Permission.bluetoothConnect: PermissionStatus.granted,
        Permission.location: PermissionStatus.denied,
      };

      final granted = await service(isAndroid: true).requestBlePermissions();

      expect(granted, isFalse);
      expect(gateway.openSettingsCalled, isFalse);
    });

    test('opens app settings when any permission is permanently denied', () async {
      gateway.statuses = {
        Permission.bluetoothScan: PermissionStatus.granted,
        Permission.bluetoothConnect: PermissionStatus.permanentlyDenied,
        Permission.location: PermissionStatus.granted,
      };

      final granted = await service(isAndroid: true).requestBlePermissions();

      expect(granted, isFalse);
      expect(gateway.openSettingsCalled, isTrue);
    });

    test('does not open settings when denied but not permanent', () async {
      gateway.statuses = {
        Permission.bluetoothScan: PermissionStatus.denied,
        Permission.bluetoothConnect: PermissionStatus.granted,
        Permission.location: PermissionStatus.granted,
      };

      final granted = await service(isAndroid: true).requestBlePermissions();

      expect(granted, isFalse);
      expect(gateway.openSettingsCalled, isFalse);
    });
  });
}