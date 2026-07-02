import 'package:permission_handler/permission_handler.dart';
import 'package:petfr/services/permission_gateway.dart';

class FakePermissionGateway implements PermissionGateway {
  Map<Permission, PermissionStatus> statuses = {};
  List<Permission>? lastRequested;
  bool openSettingsCalled = false;
  bool openSettingsResult = true;

  @override
  Future<Map<Permission, PermissionStatus>> request(
    List<Permission> permissions,
  ) async {
    lastRequested = List<Permission>.from(permissions);
    return {
      for (final permission in permissions)
        permission: statuses[permission] ?? PermissionStatus.denied,
    };
  }

  @override
  Future<PermissionStatus> status(Permission permission) async {
    return statuses[permission] ?? PermissionStatus.denied;
  }

  @override
  Future<bool> openAppSettings() async {
    openSettingsCalled = true;
    return openSettingsResult;
  }
}