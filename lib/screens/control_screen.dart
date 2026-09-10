import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../services/ble_service.dart';
import '../services/locale_service.dart';
import '../models/ble_constants.dart';
import '../models/machine_state.dart';
import '../l10n/app_strings.dart';
import 'log_screen.dart';

class ControlScreen extends StatefulWidget {
  const ControlScreen({super.key});

  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen> {
  late BleService _ble;
  final TextEditingController _tempCtrl = TextEditingController();
  final TextEditingController _speedCtrl = TextEditingController();
  final MachineState _machineState = MachineState();
  String _errorMsg = '';
  ScanResult? _selectedDevice;

  @override
  void initState() {
    super.initState();
    _ble = BleService();
    _ble.onConnectionChanged = (connected) {
      if (!connected) {
        setState(() {
          _machineState.reset();
        });
      }
    };
    _ble.onError = (err) => setState(() => _errorMsg = err);
    _ble.onStatusUpdate = (state) => setState(() {
      // Status updates may be partial; keep previous values when absent.
      if (state.hasTemperature) _machineState.temperature = state.temperature;
      if (state.hasSpeed) _machineState.speed = state.speed;
      if (state.hasStatus) _machineState.status = state.status;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => _startScan());
  }

  void _startScan() {
    if (!_ble.isConnected) {
      setState(() => _errorMsg = '');
      _ble.startScan();
    }
  }

  Future<void> _connect() async {
    if (_selectedDevice == null) return;
    setState(() => _errorMsg = '');
    await _ble.connect(_selectedDevice!.device);
  }

  Future<void> _disconnect() async {
    await _ble.disconnect();
    setState(() {
      _machineState.reset();
      _errorMsg = '';
    });
  }

  void _sendSettings() {
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

    _ble.sendTemperature(temp);
    Future.delayed(const Duration(milliseconds: 250), () {
      _ble.sendSpeed(speed);
    });
    _showSnack(strings.settingsSent);
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  String _localizeError(String err, AppStrings strings) {
    switch (err) {
      case BleService.errBluetoothOff:
        return strings.enableBluetooth;
      case BleService.errConnectionLost:
        return strings.connectionLost;
      case BleService.errNotConnected:
        return strings.notConnected;
      case BleService.errPermissionDenied:
        return strings.permissionDenied;
    }
    if (err.toLowerCase().contains('permission')) {
      return strings.permissionDenied;
    }
    return err;
  }

  @override
  void dispose() {
    _ble.dispose();
    _tempCtrl.dispose();
    _speedCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locale = context.watch<LocaleService>();
    final strings = AppStrings(locale.isZh);

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.controlTitle),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        actions: [
          IconButton(
            icon: Icon(locale.isZh ? Icons.language : Icons.language_outlined),
            tooltip: locale.isZh ? 'Switch to English' : '切換至中文',
            onPressed: () => locale.toggle(),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _ble,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              // ---- Connection Status ----
              _buildConnectionBar(strings),
              const SizedBox(height: 12),

              // ---- Device Selector ----
              _buildDeviceSelector(strings),
              const Divider(height: 24),

              // ---- Status Display ----
              _buildStatusDisplay(strings),

              // ---- Controls ----
              if (_ble.isConnected) ...[
                const Divider(height: 24),
                _buildControls(strings),
                const SizedBox(height: 24),
                _buildActionButtons(strings),
              ],

              // ---- Error ----
              if (_errorMsg.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _localizeError(_errorMsg, strings),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          );
        },
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

  Widget _buildDeviceSelector(AppStrings strings) {
    final devices = _ble.scanResults;
    final scanning = _ble.isScanning;
    final connecting = _ble.isConnecting;
    final busy = _ble.isConnected || connecting;

    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<ScanResult>(
            initialValue: _selectedDevice,
            isExpanded: true,
            hint: Text(
              scanning
                  ? strings.scanning
                  : (devices.isEmpty ? strings.noDevices : strings.selectDevice),
            ),
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
            onChanged: busy
                ? null
                : (val) => setState(() => _selectedDevice = val),
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
          onPressed: busy ? null : _startScan,
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
          onPressed: (_selectedDevice != null && !busy) ? _connect : null,
          icon: connecting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.bluetooth),
          tooltip: connecting ? strings.connecting : strings.connect,
        ),
      ],
    );
  }

  Widget _buildStatusDisplay(AppStrings strings) {
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
                color: _machineState.isOn
                    ? Colors.green.shade100
                    : Colors.orange.shade100,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _machineState.isOn ? strings.statusOn : strings.statusOff,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: _machineState.isOn
                      ? Colors.green.shade800
                      : Colors.orange.shade800,
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
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
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
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
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
            onPressed: () => _ble.sendCommand(BleConstants.cmdStart),
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
            onPressed: () => _ble.sendCommand(BleConstants.cmdStop),
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
            onPressed: _sendSettings,
            icon: const Icon(Icons.save),
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
