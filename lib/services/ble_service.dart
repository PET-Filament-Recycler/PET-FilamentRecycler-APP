import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../models/ble_constants.dart';
import '../models/ble_error.dart';
import '../models/machine_state.dart';
import 'ble_adapter.dart';
import 'database_service.dart';

/// Callback interface for BLE events.
typedef BleDeviceFoundCallback = void Function(List<ScanResult> devices);
typedef BleConnectionCallback = void Function(bool connected);
typedef BleErrorCallback = void Function(
  BleErrorCode code, {
  String? detail,
});
typedef BleDataCallback = void Function(String uuid, String data);
typedef BleStatusCallback = void Function(MachineState state);
typedef BleLogInsertedCallback = void Function();
typedef BleLogRecorder = Future<void> Function({
  required String direction,
  required String message,
  required String device,
});

/// Manages all BLE operations: scanning, connecting, data transfer.
class BleService extends ChangeNotifier {
  /// When false, skips platform BLE cleanup (widget tests).
  @visibleForTesting
  static bool platformCallsEnabled = true;

  BleService({
    BleAdapter? adapter,
    this._logRecorder,
  }) : _adapter = adapter ?? const FlutterBlueBleAdapter();

  final BleAdapter _adapter;
  final BleLogRecorder? _logRecorder;
  final DatabaseService _db = DatabaseService();

  BleDeviceFoundCallback? onDeviceFound;
  BleConnectionCallback? onConnectionChanged;
  BleErrorCallback? onError;
  BleStatusCallback? onStatusUpdate;
  BleLogInsertedCallback? onLogInserted;

  BluetoothDevice? _connectedDevice;
  Future<void> Function(List<int> bytes)? _writeControl;
  String _connectedDeviceLabel = '';

  final List<ScanResult> _scanResults = [];
  bool _isScanning = false;
  bool _isConnected = false;
  bool _released = false;
  bool _fallbackScanAttempted = false;

  StreamSubscription<List<ScanResult>>? _scanResultsSubscription;
  StreamSubscription<bool>? _isScanningSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  final List<StreamSubscription<List<int>>> _notifySubscriptions = [];

  // ---- Getters ----
  List<ScanResult> get scanResults => List.unmodifiable(_scanResults);
  bool get isScanning => _isScanning;
  bool get isConnected => _isConnected;
  bool get isReleased => _released;
  BluetoothDevice? get connectedDevice => _connectedDevice;

  /// Marks a new control-screen session. Call when entering the control panel.
  void beginSession() {
    _released = false;
  }

  /// Detaches UI callbacks so a disposed screen cannot receive events.
  void clearUiCallbacks() {
    onDeviceFound = null;
    onConnectionChanged = null;
    onError = null;
    onStatusUpdate = null;
  }

  // ---- Scanning ----
  Future<void> startScan() async {
    if (_isScanning) return;

    await _cancelScanSubscriptions();
    _fallbackScanAttempted = false;
    _scanResults.clear();
    _notifyListeners();

    if (!await _adapter.isBluetoothEnabled()) {
      _emitError(BleErrorCode.bluetoothOff);
      return;
    }

    try {
      _isScanning = true;
      _notifyListeners();

      await _adapter.startScan(
        timeout: Duration(milliseconds: BleConstants.scanTimeoutMs),
        withServices: [Guid(BleConstants.serviceUuid)],
      );

      _scanResultsSubscription = _adapter.scanResults.listen((results) {
        final filtered = results.where(_shouldKeepDevice).toList();
        _scanResults
          ..clear()
          ..addAll(filtered);
        _notifyListeners();
        onDeviceFound?.call(_scanResults);
      });

      _isScanningSubscription = _adapter.isScanning.listen((scanning) {
        if (!scanning && _isScanning) {
          _isScanning = false;
          _notifyListeners();

          if (_scanResults.isEmpty &&
              !_isConnected &&
              !_fallbackScanAttempted) {
            _fallbackScanAttempted = true;
            unawaited(_startFallbackScan());
          }
        }
      });
    } catch (e) {
      _isScanning = false;
      _notifyListeners();
      _emitError(BleErrorCode.scanError, detail: e.toString());
    }
  }

  Future<void> _startFallbackScan() async {
    if (!await _adapter.isBluetoothEnabled()) {
      _emitError(BleErrorCode.bluetoothOff);
      return;
    }

    try {
      _isScanning = true;
      _notifyListeners();

      await _adapter.startScan(
        timeout: Duration(milliseconds: BleConstants.scanTimeoutMs),
      );
    } catch (e) {
      _isScanning = false;
      _notifyListeners();
      _emitError(BleErrorCode.fallbackScanError, detail: e.toString());
    }
  }

  bool _shouldKeepDevice(ScanResult result) {
    final name = result.device.platformName;
    if (name.isNotEmpty && name.startsWith(BleConstants.deviceNamePrefix)) {
      return true;
    }

    final serviceUuids = result.advertisementData.serviceUuids;
    return serviceUuids.contains(Guid(BleConstants.serviceUuid));
  }

  Future<void> stopScan() async {
    await _cancelScanSubscriptions();
    try {
      await _adapter.stopScan();
    } catch (_) {}
    _isScanning = false;
    _notifyListeners();
  }

  Future<void> _cancelScanSubscriptions() async {
    await _scanResultsSubscription?.cancel();
    await _isScanningSubscription?.cancel();
    _scanResultsSubscription = null;
    _isScanningSubscription = null;
  }

  // ---- Connection ----
  Future<void> connect(BluetoothDevice device) async {
    await stopScan();

    if (!await _adapter.isBluetoothEnabled()) {
      _emitError(BleErrorCode.bluetoothOff);
      return;
    }

    try {
      final connection = await _adapter.connectDevice(
        device,
        timeout: Duration(milliseconds: BleConstants.connectTimeoutMs),
        serviceUuid: Guid(BleConstants.serviceUuid),
        controlUuid: Guid(BleConstants.controlUuid),
        statusUuid: Guid(BleConstants.statusUuid),
        logUuid: Guid(BleConstants.logUuid),
      );

      await _attachConnection(connection);

      _isConnected = true;
      _notifyListeners();
      onConnectionChanged?.call(true);

      sendCommand(BleConstants.cmdGetStatus, reportError: false);
    } catch (e) {
      _isConnected = false;
      _notifyListeners();
      onConnectionChanged?.call(false);
      _emitError(BleErrorCode.connectionFailed, detail: e.toString());
      await disconnect();
    }
  }

  Future<void> _attachConnection(BleDeviceConnection connection) async {
    _connectedDevice = connection.device;
    _connectedDeviceLabel = connection.deviceLabel;
    _writeControl = connection.writeControl;

    await _connectionSubscription?.cancel();
    _connectionSubscription = connection.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected) {
        _handleUnexpectedDisconnect();
      }
    });

    await _cancelNotifySubscriptions();
    _notifySubscriptions.add(
      connection.statusNotifications.listen((value) {
        if (value.isEmpty) return;
        final data = utf8.decode(value).trim();
        unawaited(_processNotifyValue(data: data, isStatus: true));
      }),
    );
    _notifySubscriptions.add(
      connection.logNotifications.listen((value) {
        if (value.isEmpty) return;
        final data = utf8.decode(value).trim();
        unawaited(_processNotifyValue(data: data, isStatus: false));
      }),
    );
  }

  Future<void> disconnect() async {
    _isConnected = false;

    await _connectionSubscription?.cancel();
    _connectionSubscription = null;
    await _cancelNotifySubscriptions();

    final device = _connectedDevice;
    try {
      if (device != null) {
        await _adapter.disconnectDevice(device);
      }
    } catch (_) {}

    _connectedDevice = null;
    _writeControl = null;
    _connectedDeviceLabel = '';

    _notifyListeners();
    onConnectionChanged?.call(false);
  }

  /// Stops scanning and disconnects before leaving the control screen.
  Future<void> prepareForExit() async {
    if (_released) return;
    _released = true;

    await stopScan();
    await disconnect();
    await ensureDisconnected();
  }

  /// Clears any lingering app-level BLE connections before scanning.
  static Future<void> ensureDisconnected() async {
    if (!platformCallsEnabled) return;
    await const FlutterBlueBleAdapter().ensureDisconnected();
  }

  void _handleUnexpectedDisconnect() {
    if (!_isConnected) return;

    _isConnected = false;
    _connectedDevice = null;
    _writeControl = null;
    _connectedDeviceLabel = '';

    unawaited(_connectionSubscription?.cancel());
    _connectionSubscription = null;
    unawaited(_cancelNotifySubscriptions());

    _notifyListeners();
    onConnectionChanged?.call(false);
    _emitError(BleErrorCode.connectionLost);
  }

  // ---- Notifications ----
  Future<void> _recordLog({
    required String direction,
    required String message,
  }) async {
    final recorder = _logRecorder;
    if (recorder != null) {
      await recorder(
        direction: direction,
        message: message,
        device: _connectedDeviceLabel,
      );
      onLogInserted?.call();
      return;
    }

    await _db.insertLog(
      direction: direction,
      message: message,
      device: _connectedDeviceLabel,
    );
    onLogInserted?.call();
  }

  Future<void> _processNotifyValue({
    required String data,
    required bool isStatus,
  }) async {
    if (data.isEmpty) return;

    try {
      await _recordLog(direction: 'IN', message: data);
    } catch (e) {
      debugPrint('Failed to record IN log: $e');
      return;
    }

    if (isStatus) {
      onStatusUpdate?.call(StatusParser.parse(data));
    }
  }

  Future<void> _cancelNotifySubscriptions() async {
    for (final subscription in _notifySubscriptions) {
      await subscription.cancel();
    }
    _notifySubscriptions.clear();
  }

  // ---- Commands ----
  Future<bool> sendCommand(
    String command, {
    bool reportError = true,
  }) async {
    if (_writeControl == null || !_isConnected) {
      if (reportError) {
        _emitError(BleErrorCode.notConnected);
      }
      return false;
    }

    try {
      final bytes = utf8.encode(command);
      await _writeControl!(bytes);
      try {
        await _recordLog(direction: 'OUT', message: command);
      } catch (e) {
        debugPrint('Failed to record OUT log: $e');
      }
      return true;
    } catch (e) {
      if (reportError) {
        _emitError(BleErrorCode.sendFailed, detail: e.toString());
      }
      return false;
    }
  }

  Future<bool> sendTemperature(int temp) async {
    return sendCommand('${BleConstants.cmdSetTempPrefix}$temp');
  }

  Future<bool> sendSpeed(int speed) async {
    return sendCommand('${BleConstants.cmdSetSpeedPrefix}$speed');
  }

  void _emitError(BleErrorCode code, {String? detail}) {
    onError?.call(code, detail: detail);
  }

  void _notifyListeners() {
    if (!hasListeners) return;
    notifyListeners();
  }

  @visibleForTesting
  static BleService createForTesting({
    required BleAdapter adapter,
    BleLogRecorder? logRecorder,
  }) {
    return BleService(adapter: adapter, logRecorder: logRecorder);
  }

  /// Synchronous teardown only. Call [prepareForExit] and await it before
  /// disposing when a BLE session may still be active.
  @override
  void dispose() {
    clearUiCallbacks();
    onLogInserted = null;
    super.dispose();
  }
}

/// Parses status strings like "TEMP:50,SPEED:1000,STATUS:ON".
class StatusParser {
  StatusParser._();

  static MachineState parse(String raw) {
    final state = MachineState();
    if (raw.isEmpty) return state;

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