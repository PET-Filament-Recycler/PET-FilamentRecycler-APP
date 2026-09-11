import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/ble_constants.dart';
import '../models/machine_state.dart';
import 'app_logger.dart';
import 'database_service.dart';

/// Callback interface for BLE events.
typedef BleDeviceFoundCallback = void Function(List<ScanResult> devices);
typedef BleConnectionCallback = void Function(bool connected);
typedef BleErrorCallback = void Function(String error);
typedef BleDataCallback = void Function(String uuid, String data);
typedef BleStatusCallback = void Function(MachineState state);

/// Manages all BLE operations: scanning, connecting, data transfer.
class BleService extends ChangeNotifier {
  /// Error keys emitted via [onError]; UI maps them to localized strings.
  static const String errBluetoothOff = 'BLUETOOTH_OFF';
  static const String errConnectionLost = 'CONNECTION_LOST';
  static const String errNotConnected = 'NOT_CONNECTED';
  static const String errPermissionDenied = 'PERMISSION_DENIED';

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
  bool _isConnecting = false;
  Timer? _statusPollTimer;

  StreamSubscription<List<ScanResult>>? _scanResultsSub;
  StreamSubscription<bool>? _isScanningSub;
  StreamSubscription<BluetoothConnectionState>? _connectionStateSub;
  final List<StreamSubscription<List<int>>> _notifySubs = [];

  // ---- Getters ----
  List<ScanResult> get scanResults => List.unmodifiable(_scanResults);
  bool get isScanning => _isScanning;
  bool get isConnected => _isConnected;
  bool get isConnecting => _isConnecting;
  BluetoothDevice? get connectedDevice => _connectedDevice;

  // ---- Scanning ----
  Future<void> startScan() async {
    if (_isScanning || _isConnected || _isConnecting) {
      AppLogger.info(
        'Scan skipped '
        '(scanning=$_isScanning connected=$_isConnected '
        'connecting=$_isConnecting)',
        category: 'BLE',
      );
      return;
    }

    await _cancelScanSubscriptions();

    if (Platform.isAndroid && !await _requestBlePermissions()) {
      _emitError(errPermissionDenied);
      return;
    }

    if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
      _emitError(errBluetoothOff);
      return;
    }

    _scanResults.clear();
    _isScanning = true;
    notifyListeners();

    try {
      _scanResultsSub = FlutterBluePlus.scanResults.listen((results) {
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

      _isScanningSub = FlutterBluePlus.isScanning.listen((scanning) {
        if (!scanning && _isScanning) {
          _isScanning = false;
          AppLogger.info(
            'Scan finished: ${_scanResults.length} device(s) found',
            category: 'BLE',
          );
          notifyListeners();
          _cancelScanSubscriptions();
        }
      });

      await FlutterBluePlus.startScan(
        timeout: Duration(milliseconds: BleConstants.scanTimeoutMs),
      );
    } catch (e) {
      _isScanning = false;
      await _cancelScanSubscriptions();
      notifyListeners();
      _emitError('Scan error: $e');
    }
  }

  /// Requests runtime BLE permissions on Android.
  /// iOS prompts automatically on first Bluetooth use.
  Future<bool> _requestBlePermissions() async {
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      // Required for scanning on Android 11 and below; on Android 12+ the
      // manifest opts out via neverForLocation, so a denial is acceptable.
      Permission.locationWhenInUse,
    ].request();

    final scan = statuses[Permission.bluetoothScan];
    final connect = statuses[Permission.bluetoothConnect];
    final location = statuses[Permission.locationWhenInUse];

    final modern = (scan?.isGranted ?? false) && (connect?.isGranted ?? false);
    final legacy = location?.isGranted ?? false;
    final granted = modern || legacy;
    AppLogger.info(
      'BLE permissions ${granted ? "granted" : "denied"} '
      '(scan=$scan connect=$connect location=$location)',
      category: 'BLE',
    );
    return granted;
  }

  Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (e) {
      AppLogger.warn('Stop scan failed: $e', category: 'BLE');
    }
    _isScanning = false;
    await _cancelScanSubscriptions();
    notifyListeners();
  }

  Future<void> _cancelScanSubscriptions() async {
    await _scanResultsSub?.cancel();
    _scanResultsSub = null;
    await _isScanningSub?.cancel();
    _isScanningSub = null;
  }

  // ---- Connection ----
  Future<void> connect(BluetoothDevice device) async {
    if (_isConnected || _isConnecting) {
      AppLogger.info(
        'Connect skipped: already connected/connecting',
        category: 'BLE',
      );
      return;
    }
    await stopScan();

    _isConnecting = true;
    notifyListeners();

    try {
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
              await _enableNotify(char, isStatus: true);
            } else if (uuid == BleConstants.logUuid) {
              await _enableNotify(char, isStatus: false);
            }
          }
          break;
        }
      }

      _isConnected = true;
      AppLogger.info(
        'Connected to ${device.platformName} (${device.remoteId})',
        category: 'BLE',
      );

      // Detect unexpected disconnects from the device side
      _connectionStateSub = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _handleRemoteDisconnect();
        }
      });

      notifyListeners();
      onConnectionChanged?.call(true);

      // Get initial status
      sendCommand(BleConstants.cmdGetStatus);
      _startStatusPolling();
    } catch (e) {
      _emitError('Connection failed: $e');
      await disconnect();
      onConnectionChanged?.call(false);
    } finally {
      _isConnecting = false;
      notifyListeners();
    }
  }

  void _handleRemoteDisconnect() {
    if (!_isConnected) return;
    _emitError(errConnectionLost);
    disconnect();
  }

  Future<void> disconnect() async {
    final wasConnected = _isConnected;
    _stopStatusPolling();
    _isConnected = false;

    await _connectionStateSub?.cancel();
    _connectionStateSub = null;
    for (final sub in _notifySubs) {
      await sub.cancel();
    }
    _notifySubs.clear();

    try {
      await _connectedDevice?.disconnect();
    } catch (e) {
      AppLogger.warn('Device disconnect failed: $e', category: 'BLE');
    }

    _connectedDevice = null;
    _controlChar = null;

    if (wasConnected) AppLogger.info('Disconnected', category: 'BLE');

    notifyListeners();
    if (wasConnected) onConnectionChanged?.call(false);
  }

  // ---- Notifications ----
  Future<void> _enableNotify(
    BluetoothCharacteristic char, {
    required bool isStatus,
  }) async {
    await char.setNotifyValue(true);
    _notifySubs.add(
      char.lastValueStream.listen((value) {
        if (value.isNotEmpty) {
          final data = utf8.decode(value);
          _db.insertLog(direction: 'IN', message: data);
          if (isStatus) {
            final state = StatusParser.parse(data);
            if (!state.hasTemperature && !state.hasSpeed && !state.hasStatus) {
              AppLogger.warn(
                'Unrecognized status payload: "$data"',
                category: 'BLE',
              );
            }
            onStatusUpdate?.call(state);
          }
        }
      }),
    );
  }

  // ---- Commands ----
  Future<void> sendCommand(String command) async {
    if (_controlChar == null || !_isConnected) {
      _emitError(errNotConnected);
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
    AppLogger.error(msg, category: 'BLE');
    onError?.call(msg);
  }

  @override
  void dispose() {
    _stopStatusPolling();
    _cancelScanSubscriptions();
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
