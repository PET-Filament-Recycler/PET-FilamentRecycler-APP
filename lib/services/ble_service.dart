import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../models/ble_constants.dart';
import '../models/machine_state.dart';
import 'database_service.dart';

/// Callback interface for BLE events.
typedef BleDeviceFoundCallback = void Function(List<ScanResult> devices);
typedef BleConnectionCallback = void Function(bool connected);
typedef BleErrorCallback = void Function(String error);
typedef BleDataCallback = void Function(String uuid, String data);
typedef BleStatusCallback = void Function(MachineState state);

/// Manages all BLE operations: scanning, connecting, data transfer.
class BleService extends ChangeNotifier {
  final DatabaseService _db = DatabaseService();

  BleDeviceFoundCallback? onDeviceFound;
  BleConnectionCallback? onConnectionChanged;
  BleErrorCallback? onError;
  BleStatusCallback? onStatusUpdate;

  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _controlChar;

  final List<ScanResult> _scanResults = [];
  bool _isScanning = false;
  bool _isConnected = false;
  Timer? _statusPollTimer;

  // ---- Getters ----
  List<ScanResult> get scanResults => List.unmodifiable(_scanResults);
  bool get isScanning => _isScanning;
  bool get isConnected => _isConnected;
  BluetoothDevice? get connectedDevice => _connectedDevice;

  // ---- Scanning ----
  Future<void> startScan() async {
    if (_isScanning) return;

    _scanResults.clear();
    notifyListeners();

    try {
      await FlutterBluePlus.adapterState
          .where((s) => s == BluetoothAdapterState.on)
          .first;

      _isScanning = true;
      notifyListeners();

      await FlutterBluePlus.startScan(
        timeout: Duration(milliseconds: BleConstants.scanTimeoutMs),
      );

      FlutterBluePlus.scanResults.listen((results) {
        // Filter for PET-Recycle devices
        _scanResults
          ..clear()
          ..addAll(
            results.where((r) {
              final name = r.device.platformName;
              return name.isNotEmpty &&
                  name.startsWith(BleConstants.deviceNamePrefix);
            }),
          );
        notifyListeners();
        onDeviceFound?.call(_scanResults);
      });

      // Stop scanning when done
      FlutterBluePlus.isScanning.listen((scanning) {
        if (!scanning && _isScanning) {
          _isScanning = false;
          notifyListeners();
        }
      });
    } catch (e) {
      _isScanning = false;
      notifyListeners();
      _emitError('Scan error: $e');
    }
  }

  Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    _isScanning = false;
    notifyListeners();
  }

  // ---- Connection ----
  Future<void> connect(BluetoothDevice device) async {
    await stopScan();

    try {
      _emitError('Connecting...');
      await device.connect(
        timeout: Duration(milliseconds: BleConstants.connectTimeoutMs),
      );
      _connectedDevice = device;

      // Discover services
      final services = await device.discoverServices();

      for (final service in services) {
        if (service.uuid.toString() == BleConstants.serviceUuid) {
          for (final char in service.characteristics) {
            final uuid = char.uuid.toString();
            if (uuid == BleConstants.controlUuid) {
              _controlChar = char;
            } else if (uuid == BleConstants.statusUuid) {
              await _enableNotify(char);
            } else if (uuid == BleConstants.logUuid) {
              await _enableNotify(char);
            }
          }
          break;
        }
      }

      _isConnected = true;
      notifyListeners();
      onConnectionChanged?.call(true);

      // Get initial status
      sendCommand(BleConstants.cmdGetStatus);
      _startStatusPolling();
    } catch (e) {
      _isConnected = false;
      notifyListeners();
      onConnectionChanged?.call(false);
      _emitError('Connection failed: $e');
      await disconnect();
    }
  }

  Future<void> disconnect() async {
    _stopStatusPolling();
    _isConnected = false;

    try {
      await _connectedDevice?.disconnect();
    } catch (_) {}

    _connectedDevice = null;
    _controlChar = null;

    notifyListeners();
    onConnectionChanged?.call(false);
  }

  // ---- Notifications ----
  Future<void> _enableNotify(BluetoothCharacteristic char) async {
    await char.setNotifyValue(true);
    char.lastValueStream.listen((value) {
      if (value.isNotEmpty) {
        final data = utf8.decode(value);
        _db.insertLog(direction: 'IN', message: data);
        onStatusUpdate?.call(StatusParser.parse(data));
      }
    });
  }

  // ---- Commands ----
  Future<void> sendCommand(String command) async {
    if (_controlChar == null || !_isConnected) {
      _emitError('Not connected');
      return;
    }

    try {
      final bytes = utf8.encode('$command\n');
      await _controlChar!.write(bytes);
      _db.insertLog(direction: 'OUT', message: command);
    } catch (e) {
      _emitError('Send failed: $e');
    }
  }

  Future<void> sendTemperature(int temp) async {
    await sendCommand('${BleConstants.cmdSetTempPrefix}$temp');
  }

  Future<void> sendSpeed(int speed) async {
    await sendCommand('${BleConstants.cmdSetSpeedPrefix}$speed');
  }

  // ---- Status Polling ----
  void _startStatusPolling() {
    _stopStatusPolling();
    _statusPollTimer = Timer.periodic(
      Duration(milliseconds: BleConstants.statusPollIntervalMs),
      (_) {
        if (_isConnected) {
          sendCommand(BleConstants.cmdGetStatus);
        }
      },
    );
  }

  void _stopStatusPolling() {
    _statusPollTimer?.cancel();
    _statusPollTimer = null;
  }

  void _emitError(String msg) {
    onError?.call(msg);
  }

  @override
  void dispose() {
    _stopStatusPolling();
    disconnect();
    super.dispose();
  }
}

/// Parses status strings like "TEMP:50,SPEED:1000,STATUS:ON".
class StatusParser {
  StatusParser._();

  static MachineState parse(String raw) {
    final state = MachineState();
    if (raw.isEmpty) return state;

    // Sanitize: remove null chars and control characters
    final sanitized = raw
        .replaceAll('\u0000', '')
        .replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '')
        .trim();

    if (sanitized.isEmpty) return state;
    if (!sanitized.contains('TEMP:') &&
        !sanitized.contains('SPEED:') &&
        !sanitized.contains('STATUS:')) {
      return state;
    }

    for (final part in sanitized.split(',')) {
      final item = part.trim();
      if (item.startsWith('TEMP:')) {
        _parseTemp(item, state);
      } else if (item.startsWith('SPEED:')) {
        _parseSpeed(item, state);
      } else if (item.startsWith('STATUS:')) {
        _parseStatus(item, state);
      }
    }

    return state;
  }

  static void _parseTemp(String item, MachineState state) {
    final value = item.substring(5).trim();
    if (value.toUpperCase() == 'ERR') return;
    final parsed = double.tryParse(value);
    if (parsed != null) state.temperature = parsed;
  }

  static void _parseSpeed(String item, MachineState state) {
    final value = item.substring(6).trim();
    final parsed = int.tryParse(value);
    if (parsed != null) state.speed = parsed;
  }

  static void _parseStatus(String item, MachineState state) {
    final value = item.substring(7).trim();
    if (value.isEmpty) return;
    final upper = value.toUpperCase();
    if (upper == MachineState.statusOn || upper == '1') {
      state.status = MachineState.statusOn;
    } else if (upper == MachineState.statusOff || upper == '0') {
      state.status = MachineState.statusOff;
    } else {
      state.status = upper;
    }
  }
}
