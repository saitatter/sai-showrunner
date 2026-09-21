import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:showrunner_flutter/features/resources/resource_editor_registry.dart';
import 'package:showrunner_flutter/features/resources/resources_workspace.dart';
import 'package:showrunner_flutter/persistence/resource_repository.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('creates, edits, and deletes an overlay from Resources', (
    tester,
  ) async {
    final root = await Directory.systemTemp.createTemp(
      'showrunner-resource-workspace-',
    );
    addTearDown(() => root.delete(recursive: true));
    final dataService = ShowRunnerDataService(root);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ResourcesWorkspace(
            dataService: dataService,
            editorRegistry: createDefaultResourceEditorRegistry(),
            resourceType: 'Overlay',
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
    expect(find.text('Edit overlay'), findsOneWidget);
    final nameField = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == 'Name',
    );
    await tester.enterText(nameField, 'Renamed integration overlay');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await _pumpApplication(tester);
    expect(find.text('Renamed integration overlay'), findsOneWidget);

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
}

Future<void> _pumpApplication(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump(const Duration(milliseconds: 250));
}
