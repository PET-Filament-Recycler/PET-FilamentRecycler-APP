import 'package:flutter_test/flutter_test.dart';
import 'package:petfr/models/machine_state.dart';

void main() {
  group('MachineState', () {
    test('defaults to unknown / empty values', () {
      final state = MachineState();

      expect(state.temperature.isNaN, isTrue);
      expect(state.speed, -1);
      expect(state.status, MachineState.statusUnknown);
      expect(state.hasTemperature, isFalse);
      expect(state.hasSpeed, isFalse);
      expect(state.hasStatus, isFalse);
      expect(state.isOn, isFalse);
    });

    test('applyFrom merges only populated fields', () {
      final current = MachineState(
        temperature: 40,
        speed: 800,
        status: MachineState.statusOn,
      );
      final incoming = MachineState(
        temperature: double.nan,
        speed: 1200,
        status: MachineState.statusUnknown,
      );

      current.applyFrom(incoming);

      expect(current.temperature, 40);
      expect(current.speed, 1200);
      expect(current.status, MachineState.statusOn);
    });

    test('reset clears all fields', () {
      final state = MachineState(
        temperature: 55,
        speed: 900,
        status: MachineState.statusOff,
      );

      state.reset();

      expect(state.hasTemperature, isFalse);
      expect(state.hasSpeed, isFalse);
      expect(state.hasStatus, isFalse);
    });
  });
}