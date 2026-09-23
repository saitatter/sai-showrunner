import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:showrunner_flutter/persistence/queue_config_repository.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';

import '../support/showrunner_test_app.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('creates a named queue and persists its configuration', (
    tester,
  ) async {
    final directory = await createShowRunnerFixtureDirectory();
    addTearDown(() => directory.delete(recursive: true));
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      buildShowRunnerTestApp(
        dataService: ShowRunnerDataService(directory),
        loadSampleGraph: false,
      ),
    );
    await _pumpApplication(tester);

    await tester.tap(find.text('Queues').first);
    await _pumpApplication(tester);
    expect(find.text('Current Item'), findsOneWidget);
    expect(find.text('Next Automation'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Create Queue'));
    await _pumpApplication(tester);
    expect(find.text('Create queue'), findsOneWidget);
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == 'Name',
      ),
      'Alerts and Events',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await _pumpUntilGone(tester, find.text('Create queue'));
    final queueRowName = find.descendant(
      of: find.byType(DataTable),
      matching: find.text('Alerts and Events'),
    );
    await _pumpUntilVisible(tester, queueRowName);

    final entries = await tester.runAsync(
      () => QueueConfigRepository(Directory('${directory.path}/queues')).list(),
    );
    if (entries == null) throw StateError('Could not load saved queues.');
    expect(entries, hasLength(1));
    expect(entries.single.config?.name, 'Alerts and Events');
    expect(entries.single.config?.paused, isFalse);

    await tester.tap(find.byTooltip('Edit queue'));
    await _pumpApplication(tester);
    expect(find.text('Edit queue'), findsOneWidget);
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == 'Name',
      ),
      'Alerts and Live',
    );
    await tester.tap(find.byType(SwitchListTile));
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Gap (seconds)',
      ),
      '4',
    );
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Timeout (seconds)',
      ),
      '45',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await _pumpUntilGone(tester, find.text('Edit queue'));
    await _pumpUntilVisible(
      tester,
      find.descendant(
        of: find.byType(DataTable),
        matching: find.text('Alerts and Live'),
      ),
    );

    final editedEntries = await tester.runAsync(
      () => QueueConfigRepository(Directory('${directory.path}/queues')).list(),
    );
    if (editedEntries == null) {
      throw StateError('Could not load edited queue configuration.');
    }
    expect(editedEntries, hasLength(1));
    expect(editedEntries.single.config?.name, 'Alerts and Live');
    expect(editedEntries.single.config?.paused, isTrue);
    expect(editedEntries.single.config?.gap, const Duration(seconds: 4));
    expect(editedEntries.single.config?.timeout, const Duration(seconds: 45));
  });
}

Future<void> _pumpApplication(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump(const Duration(milliseconds: 250));
}

Future<void> _pumpUntilVisible(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 20; attempt++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 150));
  }
  throw TestFailure('Timed out waiting for $finder.');
}

Future<void> _pumpUntilGone(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 20; attempt++) {
    if (finder.evaluate().isEmpty) return;
    await tester.pump(const Duration(milliseconds: 150));
  }
  throw TestFailure('Timed out waiting for $finder to disappear.');
}
