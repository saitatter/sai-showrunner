import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:showrunner_flutter/features/resources/resource_editor_registry.dart';
import 'package:showrunner_flutter/features/resources/resources_workspace.dart';
import 'package:showrunner_flutter/persistence/resource_repository.dart';
import 'package:showrunner_flutter/schema/resource.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';

import '../support/showrunner_test_app.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('creates, opens, and deletes an overlay from Resources', (
    tester,
  ) async {
    final root = await Directory.systemTemp.createTemp(
      'showrunner-resource-workspace-',
    );
    addTearDown(() => root.delete(recursive: true));
    final dataService = ShowRunnerDataService(root);
    ResourceData? opened;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ResourcesWorkspace(
            dataService: dataService,
            editorRegistry: createDefaultResourceEditorRegistry(),
            resourceType: 'Overlay',
            onOpenResource: (resource, _) async => opened = resource,
          ),
        ),
      ),
    );
    await _pumpApplication(tester);

    await tester.tap(find.text('New resource'));
    await _pumpApplication(tester);
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == 'Name',
      ),
      'Integration overlay',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await _pumpApplication(tester);
    final overlayTitle = find.widgetWithText(ListTile, 'Integration overlay');
    expect(overlayTitle, findsOneWidget);

    await tester.tap(overlayTitle);
    await _pumpApplication(tester);
    expect(opened?.name, 'Integration overlay');

    await tester.tap(find.byTooltip('Delete resource'));
    await _pumpApplication(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await _pumpApplication(tester);
    expect(find.text('No overlays defined'), findsOneWidget);

    final repository = ResourceRepository(
      Directory('${root.path}/overlays'),
      resourceType: 'Overlay',
    );
    expect(await repository.list(), isEmpty);
  });

  testWidgets('restores an open Stream Plan document after app restart', (
    tester,
  ) async {
    final root = await createShowRunnerFixtureDirectory();
    addTearDown(() => root.delete(recursive: true));
    final dataService = ShowRunnerDataService(root);
    await ResourceRepository(
      Directory('${root.path}/stream-plans'),
      resourceType: 'StreamPlan',
    ).save(
      const ResourceData(
        id: 'session-plan',
        config: {'name': 'Session Plan', 'segments': []},
      ),
    );

    await tester.pumpWidget(
      buildShowRunnerTestApp(dataService: dataService, showGraphEditor: false),
    );
    await _pumpApplication(tester);
    await _openStreamPlan(tester);
    expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget);

    final savedSettings = await dataService.loadPluginSettings(
      'showrunner-flutter',
    );
    expect(
      savedSettings['openWorkspaceTabs'],
      contains('workspace.streamPlan.session-plan'),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 250));
    await Future<void>.delayed(const Duration(milliseconds: 750));
    await tester.pumpWidget(
      buildShowRunnerTestApp(dataService: dataService, showGraphEditor: false),
    );
    await _pumpApplication(tester);

    expect(find.text('Session Plan'), findsAtLeastNWidgets(1));
    expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
  });
}

Future<void> _openStreamPlan(WidgetTester tester) async {
  const title = 'Session Plan';
  final panel = find.byKey(const ValueKey('showrunner-project-panel-scroll'));
  var item = find.descendant(of: panel, matching: find.text(title));
  if (!tester.any(item)) {
    await tester.tap(
      find.descendant(of: panel, matching: find.text('Stream Plans')),
    );
    await _pumpApplication(tester);
    item = find.descendant(of: panel, matching: find.text(title));
  }
  await tester.ensureVisible(item.first);
  await tester.tap(item.last);
  await _pumpApplication(tester);
}

Future<void> _pumpApplication(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump(const Duration(milliseconds: 250));
}
