import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:showrunner_flutter/app/app_foundations.dart';
import 'package:showrunner_flutter/features/setup/setup_workspace.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('completes first-run setup from an empty data directory', (
    tester,
  ) async {
    final directory = await Directory.systemTemp.createTemp(
      'showrunner-first-run-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final dataService = ShowRunnerDataService(directory);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildShowRunnerTheme(),
        home: Scaffold(
          body: SetupWorkspace(dataService: dataService, onOpenPlugin: (_) {}),
        ),
      ),
    );
    await _pumpSetup(tester);

    expect(find.text('First-run setup'), findsOneWidget);
    expect(find.text('Twitch'), findsOneWidget);

    // A clean first run can be completed without credentials. Provider
    // authorization remains available from Plugins after the initial setup.
    for (var step = 0; step < 3; step++) {
      await tester.tap(find.widgetWithText(OutlinedButton, 'Skip'));
      await _pumpSetup(tester);
    }

    expect(find.text('Setup complete'), findsOneWidget);
    expect(
      (await dataService.loadPluginSettings(
        'showrunner-flutter',
      ))['setupCompleted'],
      isTrue,
    );
  });
}

Future<void> _pumpSetup(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump(const Duration(milliseconds: 250));
}
