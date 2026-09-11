// Hardware test. Recommended runner (pre-grants permissions while installing):
//   .\tool\run_integration_tests.ps1 -BleFlow -DeviceId <device-id>

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/integration_helpers.dart';

const _runBleIntegration = bool.fromEnvironment(
  'RUN_BLE_INTEGRATION',
  defaultValue: false,
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('BLE connect and receive status when hardware is available', (
    tester,
  ) async {
    if (!_runBleIntegration) {
      return;
    }

    await pumpPetFrApp(tester);
    await openControlPanel(tester);

    final scanFinished = await waitForScanToFinish(tester);
    expect(scanFinished, isTrue, reason: 'Scan did not finish in time');

    if (!await hasScannedDevice(tester)) {
      fail(
        'No BLE device found after scan. '
        'Power on the PET-Recycle machine and run again.',
      );
    }

    await selectFirstScannedDevice(tester);
    await tapConnect(tester);

    final connected = await waitForConnected(tester);
    expect(connected, isTrue, reason: 'Device did not connect in time');

    final statusVisible = await waitForMachineStatus(tester);
    expect(statusVisible, isTrue, reason: 'Machine status was not displayed');

    expect(find.text('Connected'), findsOneWidget);

    await exitControlPanel(tester);
  });
}