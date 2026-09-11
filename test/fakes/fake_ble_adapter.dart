import 'dart:async';
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:petfr/services/ble_adapter.dart';

class FakeBleAdapter implements BleAdapter {
  bool bluetoothEnabled = true;
  bool failConnect = false;
  Object? connectError;

  int startScanCalls = 0;
  int stopScanCalls = 0;
  int connectCalls = 0;
  int disconnectCalls = 0;

  List<int>? lastWritten;
  BluetoothDevice? lastConnectedDevice;
  BluetoothDevice? lastDisconnectedDevice;

  final StreamController<List<ScanResult>> _scanResultsController =
      StreamController<List<ScanResult>>.broadcast();
  final StreamController<bool> _isScanningController =
      StreamController<bool>.broadcast();
  final StreamController<BluetoothConnectionState> connectionStates =
      StreamController<BluetoothConnectionState>.broadcast();
  final StreamController<List<int>> statusValues =
      StreamController<List<int>>.broadcast();

  @override
  Future<bool> isBluetoothEnabled() async => bluetoothEnabled;

  @override
  Future<void> ensureDisconnected() async {}

  @override
  Future<void> startScan({
    required Duration timeout,
    List<Guid>? withServices,
  }) async {
    startScanCalls++;
  }

  @override
  Future<void> stopScan() async {
    stopScanCalls++;
  }

  @override
  bool get isScanningNow => false;

  @override
  Stream<List<ScanResult>> get scanResults => _scanResultsController.stream;

  @override
  Stream<bool> get isScanning => _isScanningController.stream;

  @override
  Future<BleDeviceConnection> connectDevice(
    BluetoothDevice device, {
    required Duration timeout,
    required Guid serviceUuid,
    required Guid controlUuid,
    required Guid statusUuid,
    required Guid logUuid,
  }) async {
    connectCalls++;
    lastConnectedDevice = device;

    if (failConnect) {
      throw connectError ?? Exception('connect failed');
    }

    return BleDeviceConnection(
      device: device,
      deviceLabel: 'PET-Test',
      writeControl: (bytes) async {
        lastWritten = bytes;
      },
      connectionState: connectionStates.stream,
      statusNotifications: statusValues.stream,
      logNotifications: const Stream.empty(),
    );
  }

  @override
  Future<void> disconnectDevice(BluetoothDevice device) async {
    disconnectCalls++;
    lastDisconnectedDevice = device;
  }

  void emitStatus(String raw) {
    statusValues.add(utf8.encode(raw));
  }

  void emitDisconnected() {
    connectionStates.add(BluetoothConnectionState.disconnected);
  }

  Future<void> close() async {
    await _scanResultsController.close();
    await _isScanningController.close();
    await connectionStates.close();
    await statusValues.close();
  }
}