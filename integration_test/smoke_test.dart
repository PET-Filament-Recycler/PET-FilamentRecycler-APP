import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/integration_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('home screen opens control panel', (tester) async {
    await pumpPetFrApp(tester);

    expect(find.text('PET Recycler'), findsOneWidget);
    expect(find.text('PET Recycler Control'), findsOneWidget);

    await openControlPanel(tester);

    expect(find.text('Not Connected'), findsOneWidget);
    expect(find.text('Unknown'), findsOneWidget);

    await exitControlPanel(tester);
  });
}