import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import 'permission_gateway.dart';

class PermissionService {
  PermissionService({
    PermissionGateway? gateway,
    bool Function()? isAndroid,
  })  : _gateway = gateway ?? const PermissionHandlerGateway(),
        _isAndroid = isAndroid ?? _defaultIsAndroid;

  static bool _defaultIsAndroid() => Platform.isAndroid;

  static final PermissionService shared = PermissionService();

  final PermissionGateway _gateway;
  final bool Function() _isAndroid;

  static const List<Permission> blePermissions = [
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
    Permission.location,
  ];

  /// Returns true when every BLE permission is already granted.
  Future<bool> hasBlePermissions() async {
    if (!_isAndroid()) return true;

    for (final permission in blePermissions) {
      final status = await _gateway.status(permission);
      if (!status.isGranted) return false;
    }
    return true;
  }

  /// 申請 BLE 所需權限，全部通過回傳 true
  Future<bool> requestBlePermissions() async {
    if (!_isAndroid()) {
      return true; // iOS 另外處理
    }

    final statuses = await _gateway.request(blePermissions);

    final allGranted = statuses.values.every((s) => s.isGranted);
    if (allGranted) return true;

    final permanentlyDenied = statuses.values.any((s) => s.isPermanentlyDenied);
    if (permanentlyDenied) {
      await _gateway.openAppSettings();
    }

    return false;
  }

  @visibleForTesting
  static PermissionService createForTesting({
    required PermissionGateway gateway,
    required bool Function() isAndroid,
  }) {
    return PermissionService(gateway: gateway, isAndroid: isAndroid);
  }
}