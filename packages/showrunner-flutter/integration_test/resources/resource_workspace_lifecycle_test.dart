import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:showrunner_flutter/features/resources/resource_editor_registry.dart';
import 'package:showrunner_flutter/features/resources/resources_workspace.dart';
import 'package:showrunner_flutter/design_system/brand_icons.dart';
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

  testWidgets('overlay label edits and list order survive save and restart', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final root = await createShowRunnerFixtureDirectory();
    addTearDown(() => root.delete(recursive: true));
    final dataService = ShowRunnerDataService(root);
    final repository = ResourceRepository(
      Directory('${root.path}/overlays'),
      resourceType: 'Overlay',
    );
    await repository.save(
      const ResourceData(
        id: 'overlay-parity',
        config: {
          'name': 'Overlay parity',
          'size': {'width': 1920, 'height': 1080},
          'widgets': [
            {
              'id': 'label-title',
              'plugin': 'overlays',
              'widget': 'label',
              'name': 'Title',
              'position': {'x': 24, 'y': 24},
              'size': {'width': 500, 'height': 120},
              'config': {'message': 'Starting soon'},
              'visible': true,
              'locked': false,
            },
            {
              'id': 'chat-feed',
              'plugin': 'overlays',
              'widget': 'chatFeed',
              'name': 'Chat feed',
              'position': {'x': 24, 'y': 160},
              'size': {'width': 500, 'height': 300},
              'config': {},
              'visible': true,
              'locked': false,
            },
          ],
        },
      ),
    );

    await tester.pumpWidget(buildShowRunnerTestApp(dataService: dataService));
    await _pumpApplication(tester);
    await tester.tap(find.text('Overlays').first);
    await _pumpApplication(tester);
    final overlayEntry = find.text('Overlay parity').last;
    await tester.ensureVisible(overlayEntry);
    await tester.tap(overlayEntry);
    await _pumpApplication(tester);

    expect(find.byType(OverlayEditorPage), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('overlay-widget-row-label-title')),
    );
    await _pumpApplication(tester);
    await tester.enterText(
      find.byKey(const ValueKey('overlay-widget-name-label-title')),
      'Stream title',
    );
    final messageField = find.byWidgetPredicate(
      (candidate) =>
          candidate is TextField && candidate.decoration?.labelText == 'Text',
    );
    await tester.ensureVisible(messageField);
    await tester.enterText(messageField, 'We are live');
    await _pumpApplication(tester);

    final horizontalCenter = find.byIcon(mdiIcon(0xF0260));
    await tester.ensureVisible(horizontalCenter);
    await tester.tap(horizontalCenter);
    await _pumpApplication(tester);
    final moveDown = find.byKey(
      const ValueKey('overlay-widget-list-move-down-label-title'),
    );
    await tester.ensureVisible(moveDown);
    await tester.tap(moveDown);
    await _pumpApplication(tester);

    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await _pumpApplication(tester);

    final saved = await repository.load('overlay-parity');
    final savedWidgets = saved!.config['widgets'] as List;
    expect((savedWidgets.first as Map)['id'], 'chat-feed');
    final savedLabel = savedWidgets.last as Map;
    expect(savedLabel['name'], 'Stream title');
    expect((savedLabel['config'] as Map)['message'], 'We are live');
    expect(
      ((savedLabel['config'] as Map)['textAlign'] as Map)['textAlign'],
      'center',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 250));
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await tester.pumpWidget(buildShowRunnerTestApp(dataService: dataService));
    await _pumpApplication(tester);

    final reopened = tester.widget<OverlayEditorPage>(
      find.byType(OverlayEditorPage),
    );
    final reopenedWidgets = reopened.resource.config['widgets'] as List;
    expect((reopenedWidgets.first as Map)['id'], 'chat-feed');
    expect((reopenedWidgets.last as Map)['name'], 'Stream title');
    expect(
      ((reopenedWidgets.last as Map)['config'] as Map)['message'],
      'We are live',
    );
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
