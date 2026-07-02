import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petfr/models/ble_constants.dart';
import 'package:petfr/models/ble_error.dart';
import 'package:petfr/models/machine_state.dart';
import 'package:petfr/services/ble_service.dart';
import 'fakes/fake_ble_adapter.dart';

void main() {
  group('BleService connect / disconnect / notify', () {
    late FakeBleAdapter adapter;
    late BleService service;
    final device = BluetoothDevice.fromId('00:11:22:33:44:55');

    BleService createService() {
      return BleService.createForTesting(
        adapter: adapter,
        logRecorder: ({
          required String direction,
          required String message,
          required String device,
        }) async {},
      );
    }

    setUp(() {
      adapter = FakeBleAdapter();
      service = createService();
    });

    tearDown(() async {
      await adapter.close();
    });

    test('connect succeeds and requests status', () async {
      bool? connected;
      service.onConnectionChanged = (value) => connected = value;

      await service.connect(device);
      await Future<void>.delayed(Duration.zero);

      expect(service.isConnected, isTrue);
      expect(connected, isTrue);
      expect(adapter.connectCalls, 1);
      expect(adapter.lastWritten, utf8.encode(BleConstants.cmdGetStatus));
    });

    test('connect failure emits connectionFailed', () async {
      adapter.failConnect = true;
      BleErrorCode? errorCode;
      service.onConnectionChanged = (_) {};
      service.onError = (code, {detail}) => errorCode = code;

      await service.connect(device);

      expect(service.isConnected, isFalse);
      expect(errorCode, BleErrorCode.connectionFailed);
    });

    test('connect with bluetooth off emits bluetoothOff', () async {
      adapter.bluetoothEnabled = false;
      BleErrorCode? errorCode;
      service.onError = (code, {detail}) => errorCode = code;

      await service.connect(device);

      expect(service.isConnected, isFalse);
      expect(adapter.connectCalls, 0);
      expect(errorCode, BleErrorCode.bluetoothOff);
    });

    test('disconnect clears connection and notifies listeners', () async {
      bool? connected;
      service.onConnectionChanged = (value) => connected = value;

      await service.connect(device);
      connected = null;

      await service.disconnect();

      expect(service.isConnected, isFalse);
      expect(connected, isFalse);
      expect(adapter.disconnectCalls, 1);
      expect(adapter.lastDisconnectedDevice, device);
    });

    test('status notification updates machine state', () async {
      MachineState? status;
      service.onStatusUpdate = (state) => status = state;

      await service.connect(device);
      adapter.emitStatus('TEMP:60,SPEED:1200,STATUS:ON');
      await Future<void>.delayed(Duration.zero);

      final parsed = status;
      expect(parsed, isNotNull);
      expect(parsed!.temperature, 60);
      expect(parsed.speed, 1200);
      expect(parsed.status, MachineState.statusOn);
    });

    test('unexpected disconnect emits connectionLost', () async {
      BleErrorCode? errorCode;
      bool? connected;
      service.onConnectionChanged = (value) => connected = value;
      service.onError = (code, {detail}) => errorCode = code;

      await service.connect(device);
      adapter.emitDisconnected();
      await Future<void>.delayed(Duration.zero);

      expect(service.isConnected, isFalse);
      expect(connected, isFalse);
      expect(errorCode, BleErrorCode.connectionLost);
    });

    test('sendCommand when not connected emits notConnected', () async {
      BleErrorCode? errorCode;
      service.onError = (code, {detail}) => errorCode = code;

      final sent = await service.sendCommand(BleConstants.cmdStart);

      expect(sent, isFalse);
      expect(errorCode, BleErrorCode.notConnected);
    });
  });
}