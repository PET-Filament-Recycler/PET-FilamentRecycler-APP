import 'package:flutter_test/flutter_test.dart';
import 'package:petfr/models/machine_state.dart';
import 'package:petfr/services/ble_service.dart';

void main() {
  group('StatusParser.parse', () {
    test('parses full status line', () {
      final state = StatusParser.parse('TEMP:50,SPEED:1000,STATUS:ON');

      expect(state.temperature, 50.0);
      expect(state.speed, 1000);
      expect(state.status, MachineState.statusOn);
      expect(state.hasTemperature, isTrue);
      expect(state.hasSpeed, isTrue);
      expect(state.hasStatus, isTrue);
    });

    test('parses partial fields', () {
      final state = StatusParser.parse('STATUS:OFF');

      expect(state.hasTemperature, isFalse);
      expect(state.hasSpeed, isFalse);
      expect(state.status, MachineState.statusOff);
    });

    test('maps numeric status aliases', () {
      expect(StatusParser.parse('STATUS:1').status, MachineState.statusOn);
      expect(StatusParser.parse('STATUS:0').status, MachineState.statusOff);
    });

    test('preserves unknown status text', () {
      expect(StatusParser.parse('STATUS:PAUSED').status, 'PAUSED');
    });

    test('ignores TEMP:ERR', () {
      final state = StatusParser.parse('TEMP:ERR,SPEED:500,STATUS:ON');

      expect(state.hasTemperature, isFalse);
      expect(state.speed, 500);
      expect(state.status, MachineState.statusOn);
    });

    test('ignores invalid numeric values', () {
      final state = StatusParser.parse('TEMP:abc,SPEED:xyz,STATUS:ON');

      expect(state.hasTemperature, isFalse);
      expect(state.hasSpeed, isFalse);
      expect(state.status, MachineState.statusOn);
    });

    test('strips control characters and null bytes', () {
      final state = StatusParser.parse('TEMP:42\u0000,SPEED:100,STATUS:ON\n');

      expect(state.temperature, 42.0);
      expect(state.speed, 100);
      expect(state.status, MachineState.statusOn);
    });

    test('returns empty state for blank or unrecognized input', () {
      for (final raw in ['', '   ', 'hello', 'TEMP', 'NOPE:1']) {
        final state = StatusParser.parse(raw);

        expect(state.hasTemperature, isFalse);
        expect(state.hasSpeed, isFalse);
        expect(state.hasStatus, isFalse);
      }
    });
  });
}