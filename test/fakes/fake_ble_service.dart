import 'package:petfr/models/ble_error.dart';
import 'package:petfr/models/machine_state.dart';
import 'package:petfr/services/ble_service.dart';

/// Test double that avoids FlutterBluePlus while preserving UI callbacks.
class FakeBleService extends BleService {
  int startScanCallCount = 0;

  @override
  Future<void> startScan() async {
    startScanCallCount++;
  }

  @override
  Future<void> prepareForExit() async {}

  void emitStatus(MachineState state) => onStatusUpdate?.call(state);

  void emitError(BleErrorCode code, {String? detail}) =>
      onError?.call(code, detail: detail);
}