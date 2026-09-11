import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Active BLE session returned after a successful connect + service discovery.
class BleDeviceConnection {
  const BleDeviceConnection({
    required this.device,
    required this.deviceLabel,
    required this.writeControl,
    required this.connectionState,
    required this.statusNotifications,
    required this.logNotifications,
  });

  final BluetoothDevice device;
  final String deviceLabel;
  final Future<void> Function(List<int> bytes) writeControl;
  final Stream<BluetoothConnectionState> connectionState;
  final Stream<List<int>> statusNotifications;
  final Stream<List<int>> logNotifications;
}

/// Platform abstraction for BLE operations (enables unit tests).
abstract class BleAdapter {
  Future<bool> isBluetoothEnabled();

  Future<void> ensureDisconnected();

  Future<void> startScan({
    required Duration timeout,
    List<Guid>? withServices,
  });

  Future<void> stopScan();

  bool get isScanningNow;

  Stream<List<ScanResult>> get scanResults;

  Stream<bool> get isScanning;

  Future<BleDeviceConnection> connectDevice(
    BluetoothDevice device, {
    required Duration timeout,
    required Guid serviceUuid,
    required Guid controlUuid,
    required Guid statusUuid,
    required Guid logUuid,
  });

  Future<void> disconnectDevice(BluetoothDevice device);
}

/// Production implementation backed by flutter_blue_plus.
class FlutterBlueBleAdapter implements BleAdapter {
  const FlutterBlueBleAdapter();

  @override
  Future<bool> isBluetoothEnabled() async {
    var state = FlutterBluePlus.adapterStateNow;
    if (state == BluetoothAdapterState.unknown) {
      state = await FlutterBluePlus.adapterState.first;
    }
    return state == BluetoothAdapterState.on;
  }

  @override
  Future<void> ensureDisconnected() async {
    try {
      if (FlutterBluePlus.isScanningNow) {
        await FlutterBluePlus.stopScan();
      }
    } catch (_) {}

    for (final device
        in List<BluetoothDevice>.from(FlutterBluePlus.connectedDevices)) {
      try {
        await device.disconnect();
      } catch (_) {}
    }
  }

  @override
  Future<void> startScan({
    required Duration timeout,
    List<Guid>? withServices,
  }) {
    return FlutterBluePlus.startScan(
      timeout: timeout,
      withServices: withServices ?? const [],
    );
  }

  @override
  Future<void> stopScan() => FlutterBluePlus.stopScan();

  @override
  bool get isScanningNow => FlutterBluePlus.isScanningNow;

  @override
  Stream<List<ScanResult>> get scanResults => FlutterBluePlus.scanResults;

  @override
  Stream<bool> get isScanning => FlutterBluePlus.isScanning;

  @override
  Future<BleDeviceConnection> connectDevice(
    BluetoothDevice device, {
    required Duration timeout,
    required Guid serviceUuid,
    required Guid controlUuid,
    required Guid statusUuid,
    required Guid logUuid,
  }) async {
    await device.connect(timeout: timeout);

    final deviceLabel = device.platformName.isNotEmpty
        ? device.platformName
        : device.remoteId.str;

    final services = await device.discoverServices();
    BluetoothCharacteristic? controlChar;
    Stream<List<int>>? statusStream;
    Stream<List<int>>? logStream;

    for (final service in services) {
      if (service.uuid != serviceUuid) continue;

      for (final char in service.characteristics) {
        if (char.uuid == controlUuid) {
          controlChar = char;
        } else if (char.uuid == statusUuid) {
          statusStream = await _enableNotify(char);
        } else if (char.uuid == logUuid) {
          logStream = await _enableNotify(char);
        }
      }
      break;
    }

    if (controlChar == null) {
      throw Exception('Control characteristic not found');
    }

    return BleDeviceConnection(
      device: device,
      deviceLabel: deviceLabel,
      writeControl: controlChar.write,
      connectionState: device.connectionState,
      statusNotifications: statusStream ?? const Stream.empty(),
      logNotifications: logStream ?? const Stream.empty(),
    );
  }

  Future<Stream<List<int>>> _enableNotify(BluetoothCharacteristic char) async {
    await char.setNotifyValue(true);
    return char.lastValueStream;
  }

  @override
  Future<void> disconnectDevice(BluetoothDevice device) => device.disconnect();
}