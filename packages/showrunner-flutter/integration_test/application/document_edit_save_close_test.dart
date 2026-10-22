import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:showrunner_flutter/graph/ui/automation_graph_workspace.dart';
import 'package:showrunner_flutter/app/showrunner_page.dart';
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

    final graph = tester.widget<AutomationGraphWorkspace>(
      find.byType(AutomationGraphWorkspace),
    );
    final editor = graph.editor;
    expect(editor.isDirty, isFalse);
    final nodeId = editor.addNode(
      actionNodeType('ShowRunner', 'convertNumberToString'),
      const GraphPoint(80, 80),
    );
    editor.graph.execute(
      SetNodeTitleCommand(mainAutomationSpace, nodeId, 'Saved conversion'),
    );
    await tester.pump();
    expect(editor.isDirty, isTrue);

    await _runFileCommand(tester, 'Save automation');
    expect(editor.isDirty, isFalse);
    final saved = await AutomationRepository(
      File('${directory.path}/automations/$fileName'),
    ).load();
    expect(saved?.graph.spaces[mainAutomationSpace]!.nodes, hasLength(1));
    expect(
      saved
          ?.graph
          .spaces[mainAutomationSpace]!
          .nodePresentations[nodeId]!
          .title,
      'Saved conversion',
    );

    await tester.tap(find.byTooltip('Close $fileName'));
    await _pumpApplication(tester);
    expect(find.byTooltip('Close $fileName'), findsNothing);

    await _openAutomation(tester, 'Graph edit');
    final reopenedGraph = tester.widget<AutomationGraphWorkspace>(
      find.byType(AutomationGraphWorkspace),
    );
    expect(reopenedGraph.editor.graph.activeSpace!.nodes, hasLength(1));
    expect(reopenedGraph.editor.isDirty, isFalse);
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

    var graph = tester.widget<AutomationGraphWorkspace>(
      find.byType(AutomationGraphWorkspace),
    );
    graph.editor.addNode(
      actionNodeType('ShowRunner', 'convertNumberToString'),
      const GraphPoint(80, 80),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Close close-flow.yaml'));
    await _pumpApplication(tester);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Unsaved changes'),
      ),
      findsOneWidget,
    );
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
      ).load())!.graph.spaces[mainAutomationSpace]!.nodes,
      isEmpty,
    );

    await _openAutomation(tester, 'Close flow');
    graph = tester.widget<AutomationGraphWorkspace>(
      find.byType(AutomationGraphWorkspace),
    );
    graph.editor.addNode(
      actionNodeType('ShowRunner', 'convertNumberToString'),
      const GraphPoint(80, 80),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Close close-flow.yaml'));
    await _pumpApplication(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await _pumpApplication(tester);
    expect(find.byTooltip('Close close-flow.yaml'), findsNothing);
    expect(
      (await AutomationRepository(
        File('${directory.path}/automations/close-flow.yaml'),
      ).load())!.graph.spaces[mainAutomationSpace]!.nodes,
      hasLength(1),
    );

    await _openAutomation(tester, 'Close flow');
    graph = tester.widget<AutomationGraphWorkspace>(
      find.byType(AutomationGraphWorkspace),
    );
    graph.editor.addNode(
      actionNodeType('ShowRunner', 'convertNumberToString'),
      const GraphPoint(80, 80),
    );
    await tester.pump();
    final firstEditor = graph.editor;
    expect(firstEditor.isDirty, isTrue);
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
    await _waitForActiveAutomation(tester, 'Second');
    graph = tester.widget<AutomationGraphWorkspace>(
      find.byType(AutomationGraphWorkspace),
    );
    graph.editor.addNode(
      actionNodeType('ShowRunner', 'convertNumberToString'),
      const GraphPoint(80, 80),
    );
    await tester.pump();
    expect(
      graph.editor,
      isNot(same(firstEditor)),
      reason: 'Creation must activate a separate editor',
    );
    expect(firstEditor.graph.activeSpace!.nodes, hasLength(2));
    expect(graph.editor.graph.activeSpace!.nodes, hasLength(1));
    final application = tester
        .widget<ShowRunnerPage>(find.byType(ShowRunnerPage))
        .application!;
    expect(application.documents.automations.documents, hasLength(2));
    expect(application.documents.hasUnsavedChanges, isTrue);
    await _runFileCommand(tester, 'Save all');
    // A rendered frame is not a filesystem completion signal. Await the
    // command's owned writes before checking either tab or persisted document.
    await _waitForApplication(tester, () async {
      await flushShowRunnerTestApp(tester);
      return !application.documents.hasUnsavedChanges;
    }, 'Save All completion');
    await tester.pump();
    expect(
      firstEditor.isDirty,
      isFalse,
      reason: 'Save All must save the first tab',
    );
    expect(graph.editor.isDirty, isFalse, reason: 'Save All must complete');
    expect(
      (await AutomationRepository(
        File('${directory.path}/automations/close-flow.yaml'),
      ).load())!.graph.spaces[mainAutomationSpace]!.nodes,
      hasLength(2),
    );
    final secondEntry = (await AutomationRepository.loadDirectory(
      Directory('${directory.path}/automations'),
    )).singleWhere((entry) => entry.automation?.metadata['name'] == 'Second');
    expect(
      (await AutomationRepository(
        File('${directory.path}/automations/${secondEntry.fileName}'),
      ).load())!.graph.spaces[mainAutomationSpace]!.nodes,
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
  await _waitForActiveAutomation(tester, title);
}

Future<void> _waitForActiveAutomation(WidgetTester tester, String name) =>
    _waitForApplication(tester, () async {
      final graphs = tester.widgetList<AutomationGraphWorkspace>(
        find.byType(AutomationGraphWorkspace),
      );
      if (graphs.length != 1) return false;
      final application = tester
          .widget<ShowRunnerPage>(find.byType(ShowRunnerPage))
          .application!;
      final active = application.documents.automations.active;
      return active?.data.metadata['name'] == name &&
          identical(active?.editor, graphs.single.editor);
    }, 'active automation $name');

Future<void> _waitForApplication(
  WidgetTester tester,
  Future<bool> Function() ready,
  String operation,
) async {
  final elapsed = Stopwatch()..start();
  while (elapsed.elapsed < const Duration(seconds: 5)) {
    await tester.pump(const Duration(milliseconds: 50));
    if (await ready()) return;
    // Native pump durations advance frames; yield actual wall time for I/O.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }
  final application = tester
      .widget<ShowRunnerPage>(find.byType(ShowRunnerPage))
      .application!;
  final sessions = application.documents.automations.documents
      .map(
        (session) =>
            '${session.fileName}: ${session.data.metadata['name']}, dirty=${session.dirty}, nodes=${session.editor.graph.activeSpace!.nodes.length}',
      )
      .join('; ');
  final failures = tester
      .widgetList<Text>(find.byType(Text))
      .map((text) => text.data ?? '')
      .where((text) => text.startsWith('Unable to save document'))
      .join('; ');
  throw TestFailure(
    'Timed out waiting for $operation. Sessions: $sessions. $failures',
  );
}

Future<void> _runFileCommand(WidgetTester tester, String command) async {
  await tester.tap(find.text('File').first);
  await _pumpApplication(tester);
  final item = find.ancestor(
    of: find.text(command),
    matching: find.byType(PopupMenuItem<String>),
  );
  expect(item, findsOneWidget);
  expect(
    tester.widget<PopupMenuItem<String>>(item).enabled,
    isTrue,
    reason: '$command must be available',
  );
  await tester.tap(item);
  await _pumpApplication(tester);
  expect(item, findsNothing, reason: '$command must dismiss the menu');
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
