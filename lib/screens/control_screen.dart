import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../services/ble_service.dart';
import '../services/locale_service.dart';
import '../models/ble_constants.dart';
import '../models/ble_error.dart';
import '../models/machine_state.dart';
import '../l10n/app_strings.dart';
import '../services/permission_service.dart';
import 'log_screen.dart';

class ControlScreen extends StatefulWidget {
  const ControlScreen({
    super.key,
    @visibleForTesting this.permissionService,
  });

  @visibleForTesting
  final PermissionService? permissionService;

  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen>
    with WidgetsBindingObserver {
  late BleService _ble;
  bool _sessionReady = false;
  final TextEditingController _tempCtrl = TextEditingController();
  final TextEditingController _speedCtrl = TextEditingController();
  final MachineState _machineState = MachineState();
  BleErrorCode? _bleErrorCode;
  String? _bleErrorDetail;
  bool _permissionDenied = false;
  bool _isConnecting = false;
  bool _isDisconnecting = false;
  bool _isLeaving = false;
  bool _scanRequested = false;
  bool _suppressAutoScan = false;
  bool _isSaving = false;
  bool _exitCleanupScheduled = false;
  ScanResult? _selectedDevice;

  PermissionService get _permissions =>
      widget.permissionService ?? PermissionService.shared;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_sessionReady) return;

    _ble = context.read<BleService>();
    _ble.beginSession();
    _bindBleCallbacks(_ble);
    _ble.addListener(_onBleUpdated);
    _sessionReady = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialize());
  }

  void _bindBleCallbacks(BleService ble) {
    ble.onConnectionChanged = (connected) {
      if (!mounted) return;
      setState(() {
        if (connected) {
          _isConnecting = false;
        } else {
          _machineState.reset();
        }
      });
      if (!connected) {
        _maybeAutoScan();
      }
    };
    ble.onError = (code, {detail}) {
      if (!mounted) return;
      setState(() {
        _isConnecting = false;
        _permissionDenied = false;
        _bleErrorCode = code;
        _bleErrorDetail = detail;
      });
    };
    ble.onStatusUpdate = (state) {
      if (!mounted) return;
      setState(() => _machineState.applyFrom(state));
    };
  }

  void _onBleUpdated() {
    if (!mounted || !_sessionReady || _selectedDevice == null) return;
    final devices = _ble.scanResults;
    final stillPresent = devices.any(
      (r) => r.device.remoteId == _selectedDevice!.device.remoteId,
    );
    if (!stillPresent) {
      setState(() => _selectedDevice = null);
    }
  }

  Future<void> _initialize() async {
    await BleService.ensureDisconnected();
    if (!mounted) return;
    await _startScan();
  }

  Future<void> _handlePop() async {
    if (_isLeaving) return;
    setState(() {
      _isLeaving = true;
      _isDisconnecting = true;
    });
    await WidgetsBinding.instance.endOfFrame;

    await _ble.prepareForExit();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _maybeAutoScan() {
    if (_suppressAutoScan || _isLeaving || !_sessionReady || _ble.isConnected) {
      _suppressAutoScan = false;
      return;
    }
    unawaited(_startScan());
  }

  Future<void> _startScan() async {
    if (!_sessionReady || _ble.isConnected) return;

    await BleService.ensureDisconnected();
    if (!mounted) return;

    final granted = await _permissions.requestBlePermissions();
    if (!mounted) return;

    if (!granted) {
      setState(() {
        _clearErrors();
        _permissionDenied = true;
      });
      return;
    }

    setState(() {
      _clearErrors();
      _selectedDevice = null;
      _scanRequested = true;
    });
    _ble.startScan();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _permissionDenied &&
        !_isLeaving &&
        _sessionReady) {
      unawaited(_retryScanIfPermitted());
    }
  }

  Future<void> _retryScanIfPermitted() async {
    if (!await _permissions.hasBlePermissions()) return;
    if (!mounted || !_permissionDenied || _isLeaving) return;
    await _startScan();
  }

  Future<void> _connect() async {
    if (!_sessionReady || _selectedDevice == null) return;
    setState(() {
      _clearErrors();
      _isConnecting = true;
    });
    await _ble.connect(_selectedDevice!.device);
  }

  void _clearErrors() {
    _bleErrorCode = null;
    _bleErrorDetail = null;
    _permissionDenied = false;
  }

  ScanResult? _resolvedSelection(List<ScanResult> devices) {
    if (_selectedDevice == null) return null;
    final selectedId = _selectedDevice!.device.remoteId;
    for (final result in devices) {
      if (result.device.remoteId == selectedId) {
        return result;
      }
    }
    return null;
  }

  Future<void> _disconnect() async {
    if (!_sessionReady) return;
    _suppressAutoScan = true;
    await _ble.disconnect();
    setState(() {
      _machineState.reset();
    });
  }

  Future<void> _sendMachineCommand(String command) async {
    if (!_sessionReady) return;
    final sent = await _ble.sendCommand(command);
    if (!sent || !mounted) return;
    await _ble.sendCommand(BleConstants.cmdGetStatus);
  }

  Future<void> _sendSettings() async {
    final strings = AppStrings(context.read<LocaleService>().isZh);
    final tempText = _tempCtrl.text.trim();
    final speedText = _speedCtrl.text.trim();

    if (tempText.isEmpty || speedText.isEmpty) {
      _showSnack(strings.enterTempAndSpeed);
      return;
    }

    final temp = int.tryParse(tempText);
    final speed = int.tryParse(speedText);

    if (temp == null || speed == null) {
      _showSnack(strings.invalidNumber);
      return;
    }
    if (temp < BleConstants.tempMin || temp > BleConstants.tempMax) {
      _showSnack(
        strings.tempRangeError(BleConstants.tempMin, BleConstants.tempMax),
      );
      return;
    }
    if (speed < BleConstants.speedMin || speed > BleConstants.speedMax) {
      _showSnack(
        strings.speedRangeError(BleConstants.speedMin, BleConstants.speedMax),
      );
      return;
    }

    if (!_sessionReady || _isSaving) return;

    setState(() => _isSaving = true);

    final tempOk = await _ble.sendTemperature(temp);
    if (!tempOk || !mounted) {
      setState(() => _isSaving = false);
      return;
    }

    await Future.delayed(const Duration(milliseconds: 250));
    if (!mounted) {
      setState(() => _isSaving = false);
      return;
    }

    final speedOk = await _ble.sendSpeed(speed);
    if (!mounted) {
      setState(() => _isSaving = false);
      return;
    }
    if (!speedOk) {
      setState(() => _isSaving = false);
      return;
    }

    await _ble.sendCommand(BleConstants.cmdGetStatus, reportError: false);

    if (!mounted) return;
    setState(() => _isSaving = false);
    _showSnack(strings.settingsSent);
  }

  String _localizedBleError(
    AppStrings strings,
    BleErrorCode code, {
    String? detail,
  }) {
    switch (code) {
      case BleErrorCode.scanError:
        return strings.scanError(detail ?? '');
      case BleErrorCode.fallbackScanError:
        return strings.fallbackScanError(detail ?? '');
      case BleErrorCode.connectionFailed:
        return strings.connectionFailed(detail ?? '');
      case BleErrorCode.connectionLost:
        return strings.connectionLost;
      case BleErrorCode.notConnected:
        return strings.notConnected;
      case BleErrorCode.sendFailed:
        return strings.sendFailed(detail ?? '');
      case BleErrorCode.bluetoothOff:
        return strings.enableBluetooth;
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  void _scheduleExitCleanupIfNeeded() {
    if (_exitCleanupScheduled ||
        !_sessionReady ||
        _isLeaving ||
        _ble.isReleased) {
      return;
    }
    _exitCleanupScheduled = true;
    unawaited(_ble.prepareForExit());
  }

  @override
  void activate() {
    super.activate();
    if (!_sessionReady || _isLeaving || !_ble.isReleased) return;

    // Recover if a child route (e.g. logs) previously triggered teardown.
    _exitCleanupScheduled = false;
    _ble.beginSession();
    _bindBleCallbacks(_ble);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_sessionReady) {
      _ble.removeListener(_onBleUpdated);
      _ble.clearUiCallbacks();
      _scheduleExitCleanupIfNeeded();
    }
    _tempCtrl.dispose();
    _speedCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locale = context.watch<LocaleService>();
    final strings = AppStrings(locale.isZh);
    final statusText = _isConnecting ? strings.connecting : null;
    final errorText = _permissionDenied
        ? strings.permissionDenied
        : _bleErrorCode != null
        ? _localizedBleError(
            strings,
            _bleErrorCode!,
            detail: _bleErrorDetail,
          )
        : null;

    if (!_sessionReady) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handlePop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(strings.controlTitle),
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          actions: [
            IconButton(
              icon: Icon(
                locale.isZh ? Icons.language : Icons.language_outlined,
              ),
              tooltip: locale.isZh ? 'Switch to English' : '切換至中文',
              onPressed: _isLeaving ? null : () => locale.toggle(),
            ),
          ],
        ),
        body: Stack(
          children: [
            ListenableBuilder(
        listenable: _ble,
        builder: (context, _) {
          final showNoDevices = _scanRequested &&
              !_ble.isScanning &&
              !_ble.isConnected &&
              _ble.scanResults.isEmpty &&
              errorText == null &&
              !_permissionDenied;

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ---- Connection Status ----
                _buildConnectionBar(strings),
                const SizedBox(height: 12),

                // ---- Device Selector ----
                _buildDeviceSelector(strings, showNoDevices: showNoDevices),
                const Divider(height: 24),

                // ---- Status Display ----
                _buildStatusDisplay(strings),
                const Divider(height: 24),

                // ---- Controls ----
                if (_ble.isConnected) ...[
                  _buildControls(strings),
                  const Spacer(),
                  _buildActionButtons(strings),
                ] else
                  const Spacer(),

                // ---- Status / Error ----
                if (statusText != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      statusText,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (errorText != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      errorText,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
        ),
            if (_isDisconnecting)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black26,
                  child: Center(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 24,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: 16),
                            Text(
                              strings.disconnecting,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionBar(AppStrings strings) {
    final connected = _ble.isConnected;
    return Row(
      children: [
        Icon(
          connected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
          color: connected ? Colors.green : Colors.red,
        ),
        const SizedBox(width: 8),
        Text(
          connected ? strings.connected : strings.notConnected,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: connected ? Colors.green : Colors.red,
          ),
        ),
        const Spacer(),
        if (connected)
          OutlinedButton(
            onPressed: _disconnect,
            child: Text(strings.disconnect),
          ),
      ],
    );
  }

  Widget _buildDeviceSelector(
    AppStrings strings, {
    required bool showNoDevices,
  }) {
    final devices = _ble.scanResults;
    final scanning = _ble.isScanning;
    final selected = _resolvedSelection(devices);
    final controlsEnabled = !_ble.isConnected && !_isLeaving;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<ScanResult>(
            key: ValueKey(selected?.device.remoteId.str ?? 'none'),
            initialValue: selected,
            isExpanded: true,
            hint: Text(scanning ? strings.scanning : strings.selectDevice),
            items: devices.map((r) {
              final name = r.device.platformName;
              return DropdownMenuItem(
                value: r,
                child: Text(
                  '$name (RSSI:${r.rssi})',
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }).toList(),
            onChanged: controlsEnabled
                ? (val) => setState(() => _selectedDevice = val)
                : null,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: controlsEnabled ? _startScan : null,
          icon: scanning
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh),
          tooltip: strings.refresh,
        ),
        IconButton(
          onPressed: (selected != null && controlsEnabled) ? _connect : null,
          icon: const Icon(Icons.bluetooth),
          tooltip: strings.connect,
        ),
      ],
        ),
        if (showNoDevices)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              strings.noDevices,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildStatusDisplay(AppStrings strings) {
    final hasStatus = _machineState.hasStatus;
    final isOn = _machineState.isOn;
    final statusLabel = !hasStatus
        ? strings.statusUnknown
        : isOn
        ? strings.statusOn
        : strings.statusOff;
    final statusBgColor = !hasStatus
        ? Colors.grey.shade100
        : isOn
        ? Colors.green.shade100
        : Colors.orange.shade100;
    final statusTextColor = !hasStatus
        ? Colors.grey.shade800
        : isOn
        ? Colors.green.shade800
        : Colors.orange.shade800;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              strings.temperature,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              _machineState.hasTemperature
                  ? '${_machineState.temperature.toInt()} °C'
                  : '-- °C',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 12),
            Text(strings.speed, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              _machineState.hasSpeed ? '${_machineState.speed}' : '--',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: statusBgColor,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                statusLabel,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: statusTextColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControls(AppStrings strings) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _tempCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: strings.temperature,
              suffixText: strings.tempPlaceholder,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: _speedCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: strings.speed,
              suffixText: strings.speedPlaceholder,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons(AppStrings strings) {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: () => _sendMachineCommand(BleConstants.cmdStart),
            icon: const Icon(Icons.play_arrow),
            label: Text(strings.start),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton.icon(
            onPressed: () => _sendMachineCommand(BleConstants.cmdStop),
            icon: const Icon(Icons.stop),
            label: Text(strings.stop),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton.icon(
            onPressed: _isSaving ? null : _sendSettings,
            icon: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save),
            label: Text(strings.save),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LogScreen()),
            );
          },
          icon: const Icon(Icons.list_alt),
          tooltip: strings.logs,
          style: IconButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
          ),
        ),
      ],
    );
  }
}
