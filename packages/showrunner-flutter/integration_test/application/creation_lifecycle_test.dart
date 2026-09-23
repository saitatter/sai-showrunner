import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:showrunner_flutter/features/profile/profile_trigger_editor_card.dart';
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
    expect(find.text('Triggers'), findsOneWidget);
    expect(find.text('Activation'), findsOneWidget);
    expect(find.text('No Conditions (Always On)'), findsOneWidget);
    expect(find.text('Activation condition (JSON)'), findsNothing);
    await tester.tap(find.widgetWithText(TextButton, 'Group').first);
    await _pumpApplication(tester);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Add Trigger'));
    await _pumpApplication(tester);
    expect(find.text('Add profile trigger'), findsOneWidget);
    final picker = find.byType(Dialog).last;
    final availableTriggers = find.descendant(
      of: picker,
      matching: find.byType(ListTile),
    );
    expect(availableTriggers, findsAtLeastNWidgets(1));
    await tester.ensureVisible(availableTriggers.first);
    await tester.tap(availableTriggers.first);
    await _pumpApplication(tester);
    expect(find.text('Add profile trigger'), findsNothing);
    expect(find.text('Automation'), findsOneWidget);
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Description',
      ),
      'First event',
    );
    await _pumpApplication(tester);

    await tester.tap(find.byTooltip('Collapse trigger').first);
    await _pumpApplication(tester);
    final addTriggerButtons = find.widgetWithText(
      OutlinedButton,
      'Add Trigger',
    );
    await tester.ensureVisible(addTriggerButtons.last);
    await tester.tap(addTriggerButtons.last);
    await _pumpApplication(tester);
    final secondPicker = find.byType(Dialog).last;
    final secondAvailableTriggers = find.descendant(
      of: secondPicker,
      matching: find.byType(ListTile),
    );
    expect(secondAvailableTriggers, findsAtLeastNWidgets(2));
    await tester.ensureVisible(secondAvailableTriggers.at(1));
    await tester.tap(secondAvailableTriggers.at(1));
    await _pumpApplication(tester);
    await tester.enterText(
      find
          .byWidgetPredicate(
            (widget) =>
                widget is TextField &&
                widget.decoration?.labelText == 'Description',
          )
          .last,
      'Second event',
    );
    await _pumpApplication(tester);
    await tester.tap(find.byTooltip('Collapse trigger').last);
    await _pumpApplication(tester);

    final dragHandles = find.descendant(
      of: find.byType(ProfileTriggerEditorCard),
      matching: find.byType(ReorderableDragStartListener),
    );
    expect(dragHandles, findsNWidgets(2));
    final profileScrollables = find.ancestor(
      of: find.byType(ProfileTriggerEditorCard).first,
      matching: find.byType(Scrollable),
    );
    expect(profileScrollables, findsAtLeastNWidgets(2));
    final scrollableCount = profileScrollables.evaluate().length;
    for (var index = 0; index < scrollableCount; index++) {
      tester
          .state<ScrollableState>(profileScrollables.at(index))
          .position
          .jumpTo(0);
    }
    await _pumpApplication(tester);
    final firstHandle = tester.getCenter(dragHandles.first);
    final secondHandle = tester.getCenter(dragHandles.last);
    await tester.dragFrom(
      firstHandle,
      Offset(0, secondHandle.dy - firstHandle.dy + 100),
    );
    await _pumpApplication(tester);
    expect(find.byType(ProfileTriggerEditorCard), findsNWidgets(2));
    expect(find.text('Save Profile'), findsOneWidget);
    final saveProfile = find.text('Save Profile');
    await tester.ensureVisible(saveProfile);
    await tester.tap(saveProfile);
    await _pumpApplication(tester);

    final profileFiles = await Directory('${directory.path}/profiles')
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.yaml'))
        .toList();
    expect(profileFiles, hasLength(1));
    final profile = await ProfileRepository(
      File(profileFiles.single.path),
    ).load();
    expect(profile?.name, 'Named profile');
    expect(profile?.activationCondition['type'], 'group');
    expect(
      (profile?.activationCondition['operands'] as List).single['type'],
      'group',
    );
    expect(profile?.triggers, hasLength(2));
    expect(profile?.triggers.first['plugin'], isNotEmpty);
    expect(profile?.triggers.first['trigger'], isNotEmpty);
    expect(profile?.triggers.first['description'], 'Second event');
    expect(profile?.triggers.last['description'], 'First event');
  });
}

Future<void> _pumpApplication(WidgetTester tester) async {
  // Runtime workers keep timers alive, so pumpAndSettle would wait forever.
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump(const Duration(milliseconds: 250));
}
