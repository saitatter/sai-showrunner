import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:showrunner_flutter/features/graph/graph_workspace.dart';
import 'package:showrunner_flutter/editor/showrunner_graph_editor.dart';
import 'package:showrunner_flutter/persistence/automation_repository.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';

import '../support/integration_fixtures.dart';
import '../support/showrunner_test_app.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('edits, saves, closes, and reopens a graph document', (
    tester,
  ) async {
    final directory = await createShowRunnerFixtureDirectory();
    addTearDown(() => directory.delete(recursive: true));
    final dataService = ShowRunnerDataService(directory);
    const fileName = 'graph-edit.yaml';
    await saveAutomation(directory, fileName, namedAutomation('Graph edit'));

    await tester.pumpWidget(
      buildShowRunnerTestApp(dataService: dataService, loadSampleGraph: false),
    );
    await _pumpApplication(tester);
    await _openAutomation(tester, 'Graph edit');

    final graph = tester.widget<GraphWorkspace>(find.byType(GraphWorkspace));
    final editor = graph.editor;
    expect(editor.documentDirty.value, isFalse);
    expect(
      editor.addNodeType(
        'ShowRunner.convertNumberToString',
        title: 'Saved conversion',
      ),
      isNotNull,
    );
    await tester.pump();
    expect(editor.documentDirty.value, isTrue);

    await _runFileCommand(tester, 'Save automation');
    expect(editor.documentDirty.value, isFalse);
    final saved = await AutomationRepository(
      File('${directory.path}/automations/$fileName'),
    ).load();
    expect(saved?.graph.nodes, hasLength(1));
    expect(saved?.graph.nodes.single.data['title'], 'Saved conversion');

    await tester.tap(find.byTooltip('Close $fileName'));
    await _pumpApplication(tester);
    expect(find.byTooltip('Close $fileName'), findsNothing);

    await _openAutomation(tester, 'Graph edit');
    final reopenedGraph = tester.widget<GraphWorkspace>(
      find.byType(GraphWorkspace),
    );
    expect(reopenedGraph.editor.controller.nodes, hasLength(1));
    expect(reopenedGraph.editor.documentDirty.value, isFalse);
  });

  testWidgets('supports Cancel, Discard, Save, and Save All close flows', (
    tester,
  ) async {
    final directory = await createShowRunnerFixtureDirectory();
    addTearDown(() => directory.delete(recursive: true));
    final dataService = ShowRunnerDataService(directory);
    await saveAutomation(
      directory,
      'close-flow.yaml',
      namedAutomation('Close flow'),
    );
    await tester.pumpWidget(
      buildShowRunnerTestApp(dataService: dataService, loadSampleGraph: false),
    );
    await _pumpApplication(tester);
    await _openAutomation(tester, 'Close flow');

    var graph = tester.widget<GraphWorkspace>(find.byType(GraphWorkspace));
    graph.editor.addNodeType('ShowRunner.convertNumberToString');
    await tester.pump();
    await tester.tap(find.byTooltip('Close close-flow.yaml'));
    await _pumpApplication(tester);
    expect(find.text('Unsaved changes'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await _pumpApplication(tester);
    expect(find.byTooltip('Close close-flow.yaml'), findsOneWidget);

    await tester.tap(find.byTooltip('Close close-flow.yaml'));
    await _pumpApplication(tester);
    await tester.tap(find.widgetWithText(TextButton, "Don't Save"));
    await _pumpApplication(tester);
    expect(find.byTooltip('Close close-flow.yaml'), findsNothing);
    expect(
      (await AutomationRepository(
        File('${directory.path}/automations/close-flow.yaml'),
      ).load())!.graph.nodes,
      isEmpty,
    );

    await _openAutomation(tester, 'Close flow');
    graph = tester.widget<GraphWorkspace>(find.byType(GraphWorkspace));
    graph.editor.addNodeType('ShowRunner.convertNumberToString');
    await tester.pump();
    await tester.tap(find.byTooltip('Close close-flow.yaml'));
    await _pumpApplication(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await _pumpApplication(tester);
    expect(find.byTooltip('Close close-flow.yaml'), findsNothing);
    expect(
      (await AutomationRepository(
        File('${directory.path}/automations/close-flow.yaml'),
      ).load())!.graph.nodes,
      hasLength(1),
    );

    await _openAutomation(tester, 'Close flow');
    graph = tester.widget<GraphWorkspace>(find.byType(GraphWorkspace));
    graph.editor.addNodeType('ShowRunner.convertNumberToString');
    await tester.pump();
    await tester.tap(find.byTooltip('Create Automations'));
    await _pumpApplication(tester);
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Automation name',
      ),
      'Second',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await _pumpApplication(tester);
    graph = tester.widget<GraphWorkspace>(find.byType(GraphWorkspace));
    graph.editor.addNodeType('ShowRunner.convertNumberToString');
    await tester.pump();
    await _runFileCommand(tester, 'Save all');
    final secondEntry = (await AutomationRepository.loadDirectory(
      Directory('${directory.path}/automations'),
    )).singleWhere((entry) => entry.automation?.extra['name'] == 'Second');
    expect(
      (await AutomationRepository(
        File('${directory.path}/automations/${secondEntry.fileName}'),
      ).load())!.graph.nodes,
      hasLength(1),
    );
  });
}

Future<void> _openAutomation(WidgetTester tester, String title) async {
  if (find.text(title).evaluate().isEmpty) {
    await tester.tap(find.text('Automations').first);
  }
  await _pumpUntilVisible(tester, find.text(title));
  await tester.tap(find.text(title).last);
  await _pumpApplication(tester);
}

Future<void> _runFileCommand(WidgetTester tester, String command) async {
  await tester.tap(find.text('File').first);
  await _pumpApplication(tester);
  await tester.tap(find.text(command));
  await _pumpApplication(tester);
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
