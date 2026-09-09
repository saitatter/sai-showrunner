import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:showrunner_flutter/persistence/automation_repository.dart';
import 'package:showrunner_flutter/persistence/profile_repository.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';

import '../support/showrunner_test_app.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('creates named automation and profile resources', (tester) async {
    final directory = await createShowRunnerFixtureDirectory();
    addTearDown(() => directory.delete(recursive: true));
    final dataService = ShowRunnerDataService(directory);

    await tester.pumpWidget(buildShowRunnerTestApp(dataService: dataService));
    await _pumpApplication(tester);

    await tester.tap(find.text('Automations').first);
    await _pumpApplication(tester);
    await tester.tap(find.byTooltip('Create Automations'));
    await _pumpApplication(tester);
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Automation name',
      ),
      'Named automation',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await _pumpApplication(tester);

    expect(find.text('Named automation'), findsAtLeastNWidgets(1));
    final automationFiles = await Directory('${directory.path}/automations')
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.yaml'))
        .toList();
    expect(automationFiles, hasLength(1));
    final automation = await AutomationRepository(
      File(automationFiles.single.path),
    ).load();
    expect(automation?.extra['name'], 'Named automation');

    await tester.tap(find.text('Profiles').first);
    await _pumpApplication(tester);
    await tester.tap(find.byTooltip('Create Profiles'));
    await _pumpApplication(tester);
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == 'Name',
      ),
      'Named profile',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await _pumpApplication(tester);

    expect(find.text('Named profile'), findsAtLeastNWidgets(1));
    final profileFiles = await Directory('${directory.path}/profiles')
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.yaml'))
        .toList();
    expect(profileFiles, hasLength(1));
    final profile = await ProfileRepository(
      File(profileFiles.single.path),
    ).load();
    expect(profile?.name, 'Named profile');
  });
}

Future<void> _pumpApplication(WidgetTester tester) async {
  // Runtime workers keep timers alive, so pumpAndSettle would wait forever.
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump(const Duration(milliseconds: 250));
}
