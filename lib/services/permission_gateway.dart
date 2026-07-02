import 'package:permission_handler/permission_handler.dart' as ph;

/// Platform abstraction for permission requests (enables unit tests).
abstract class PermissionGateway {
  Future<Map<ph.Permission, ph.PermissionStatus>> request(
    List<ph.Permission> permissions,
  );

  Future<ph.PermissionStatus> status(ph.Permission permission);

  Future<bool> openAppSettings();
}

/// Production implementation backed by permission_handler.
class PermissionHandlerGateway implements PermissionGateway {
  const PermissionHandlerGateway();

  @override
  Future<Map<ph.Permission, ph.PermissionStatus>> request(
    List<ph.Permission> permissions,
  ) {
    return permissions.request();
  }

  @override
  Future<ph.PermissionStatus> status(ph.Permission permission) {
    return permission.status;
  }

  @override
  Future<bool> openAppSettings() => ph.openAppSettings();
}