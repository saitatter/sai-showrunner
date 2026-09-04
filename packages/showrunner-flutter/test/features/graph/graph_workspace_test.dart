import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/app/startup_health.dart';
import 'package:showrunner_flutter/editor/showrunner_graph_editor.dart';
import 'package:showrunner_flutter/features/graph/graph_workspace.dart';
import 'package:showrunner_flutter/runtime/expression.dart';
import 'package:showrunner_flutter/schema/automation.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory userDirectory;
  late ShowRunnerDataService dataService;
  late ShowRunnerGraphEditor editor;

  setUp(() async {
    userDirectory = await Directory.systemTemp.createTemp('graph-workspace-');
    dataService = ShowRunnerDataService(userDirectory);
    editor = ShowRunnerGraphEditor()..loadSampleGraph();
  });

  tearDown(() async {
    editor.dispose();
    await userDirectory.delete(recursive: true);
  });

  Future<void> pumpWorkspace(
    WidgetTester tester, {
    DartPluginRegistry? registry,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1200,
            height: 800,
            child: GraphWorkspace(
              editor: editor,
              healthFuture: dataService.health().then(
                (health) => StartupHealthSnapshot(
                  state: health.isReady
                      ? StartupHealthState.ready
                      : StartupHealthState.offline,
                  health: health,
                ),
              ),
              dataService: dataService,
              registryFuture: Future.value(registry ?? DartPluginRegistry()),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('renders graph palette and healthy status', (tester) async {
    await pumpWorkspace(tester);

    expect(find.text('Add node'), findsOneWidget);
    expect(find.text('Graph healthy'), findsOneWidget);
    expect(find.textContaining('3 nodes'), findsOneWidget);
  });

  testWidgets('renders rejected-link feedback and allows dismissing it', (
    tester,
  ) async {
    editor.graphFeedback.value = 'Cannot connect a data port to a control port';
    await pumpWorkspace(tester);

    expect(
      find.text('Cannot connect a data port to a control port'),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Dismiss graph feedback'));
    await tester.pump();

    expect(
      find.text('Cannot connect a data port to a control port'),
      findsNothing,
    );
  });

  testWidgets('places canvas insertion using the viewport coordinate', (
    tester,
  ) async {
    await pumpWorkspace(tester);

    final insertedId = editor.addNodeTypeAtScreenPosition(
      'obs.scene',
      const Offset(520, 360),
    );

    expect(insertedId, isNotNull);
    expect(
      editor.controller.nodes[insertedId]!.offset,
      isNot(const Offset(80, 80)),
    );
  });

  testWidgets('exposes structural graph issues through graph health', (
    tester,
  ) async {
    editor.loadAutomation(
      const AutomationData(
        graph: AutomationGraph(
          nodes: [GraphNode(id: 'start', type: 'queue.addItem', x: 0, y: 0)],
          edges: [GraphEdge(id: 'stale', from: 'start', to: 'missing')],
          entryNodeId: 'start',
        ),
      ),
    );
    await pumpWorkspace(tester);

    expect(find.text('1 graph issue'), findsOneWidget);
    await tester.tap(find.text('1 graph issue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Graph health'), findsOneWidget);
    expect(find.textContaining('missing node'), findsOneWidget);
  });

  testWidgets('shows recent dynamic nodes with their display labels', (
    tester,
  ) async {
    final registry = DartPluginRegistry()
      ..register(
        DartPluginManifest(
          id: 'twitch',
          name: 'Twitch',
          triggers: [
            DartTriggerDefinition(
              pluginId: 'twitch',
              triggerId: 'chat',
              displayName: 'Chat message received',
              listen: () => const Stream<RuntimeMap>.empty(),
            ),
          ],
        ),
      );
    editor.addNodeType('trigger.twitch.chat');
    await pumpWorkspace(tester, registry: registry);

    await tester.tap(find.byTooltip('Search node types'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Recently used'), findsOneWidget);
    expect(find.text('Chat message received'), findsNWidgets(2));
  });

  testWidgets('filters conversion actions under the Data category', (
    tester,
  ) async {
    final registry = DartPluginRegistry()
      ..register(
        DartPluginManifest(
          id: 'showrunner',
          name: 'ShowRunner',
          actions: [
            DartActionDefinition(
              pluginId: 'showrunner',
              actionId: 'convertNumberToString',
              displayName: 'Number to text',
              invoke: (config, context) async => null,
            ),
          ],
        ),
      );
    await pumpWorkspace(tester, registry: registry);

    await tester.tap(find.byTooltip('Search node types'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pump();
    await tester.tap(find.text('Data').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Number to text'), findsOneWidget);
    expect(find.text('ShowRunner'), findsOneWidget);
  });

  testWidgets('selects the highlighted picker result with Enter', (
    tester,
  ) async {
    await pumpWorkspace(tester);

    await tester.tap(find.byTooltip('Search node types'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byType(TextField).last, 'If');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Configure If'), findsOneWidget);
    await tester.tap(find.text('Cancel').last);
  });
}
