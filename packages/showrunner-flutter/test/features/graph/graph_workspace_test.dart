import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sai_nodes/sai_nodes.dart';
import 'package:showrunner_flutter/app/startup_health.dart';
import 'package:showrunner_flutter/app/automation_document_manager.dart';
import 'package:showrunner_flutter/editor/showrunner_graph_editor.dart';
import 'package:showrunner_flutter/features/graph/graph_workspace.dart';
import 'package:showrunner_flutter/features/graph/graph_canvas_controls.dart';
import 'package:showrunner_flutter/features/graph/graph_canvas_search.dart';
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
    editor = ShowRunnerGraphEditor()..loadDeveloperFixtureGraph();
  });

  tearDown(() async {
    editor.dispose();
    await userDirectory.delete(recursive: true);
  });

  Future<void> pumpWorkspace(
    WidgetTester tester, {
    DartPluginRegistry? registry,
    AutomationDocumentManager? automationDocuments,
    ValueChanged<String>? onAutomationSelected,
    Size size = const Size(1200, 800),
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        home: Scaffold(
          backgroundColor: const Color(0xff101010),
          body: SizedBox(
            width: size.width,
            height: size.height,
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
              automationDocuments: automationDocuments,
              onAutomationSelected: onAutomationSelected,
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

  test('builds action ports from the manifest schemas', () {
    final nodeId = editor.addNodeType('ShowRunner.addToQueue');
    final node = editor.controller.nodes[nodeId];

    expect(node, isNotNull);
    expect(
      node!.ports.values
          .where((port) => port.prototype.direction == PortDirection.input)
          .map((port) => port.prototype.idName),
      containsAll(<String>['exec', 'queue', 'automation', 'payload']),
    );
    expect(node.ports['queue']!.prototype.dataType, equals(String));
    expect(
      node.ports['payload']!.prototype.dataType,
      equals(Map<String, dynamic>),
    );
    expect(node.ports['queued']!.prototype.dataType, equals(bool));
    expect(node.ports['queueId']!.prototype.dataType, equals(String));
  });

  test('rejects data wires with incompatible schema types', () {
    final numberVariable = editor.addVariableNode('number');
    final actionId = editor.addNodeType('ShowRunner.addToQueue');

    expect(numberVariable, isNotNull);
    expect(actionId, isNotNull);
    final link = editor.controller.addLink(
      numberVariable!,
      'value',
      actionId!,
      'queue',
    );

    expect(link, isNull);
    expect(
      editor.controller.linksAsList.where(
        (candidate) =>
            candidate.endpoints.sourceNodeId == numberVariable &&
            candidate.endpoints.sourcePortId == 'value',
      ),
      isEmpty,
    );
  });

  test('preview playhead follows graph order and can be reset', () {
    expect(editor.previewTotal, const Duration(milliseconds: 1800));
    editor.togglePreview();
    expect(editor.previewPlaying.value, isTrue);
    expect(editor.previewNodeId.value, isNotNull);
    expect(editor.previewProgress, greaterThanOrEqualTo(0));
    editor.resetPreview();
    expect(editor.previewPlaying.value, isFalse);
    expect(editor.previewNodeId.value, isNull);
    expect(editor.previewElapsed.value, Duration.zero);
  });

  testWidgets('canvas controls zoom without selecting or moving nodes', (
    tester,
  ) async {
    await pumpWorkspace(tester);
    final offsets = {
      for (final node in editor.controller.nodes.values) node.id: node.offset,
    };
    final zoomButton = find.byWidgetPredicate(
      (widget) => widget is IconButton && widget.tooltip == 'Zoom out',
    );
    expect(zoomButton, findsOneWidget);
    await tester.tap(zoomButton);
    await tester.pump();
    expect(editor.controller.viewportZoom, closeTo(0.9, 0.001));
    expect(find.text('90%'), findsOneWidget);
    expect(editor.controller.selectedNodeIds, isEmpty);
    expect({
      for (final node in editor.controller.nodes.values) node.id: node.offset,
    }, offsets);
  });

  testWidgets('opens graph search and cycles matching nodes', (tester) async {
    await pumpWorkspace(tester);

    // The generic sai_nodes shortcut owns focus and delegates Ctrl+F to the
    // ShowRunner-specific find overlay.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(editor.canvasSearchOpen.value, isTrue);
    expect(find.byType(GraphCanvasSearch), findsOneWidget);

    final searchField = find.descendant(
      of: find.byType(GraphCanvasSearch),
      matching: find.byType(TextField),
    );
    await tester.enterText(searchField, 'Chat');
    await tester.pump();
    expect(editor.searchResultCount(), greaterThan(0));
    expect(find.textContaining('/'), findsWidgets);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(editor.canvasSearchOpen.value, isFalse);
  });

  testWidgets('editor desktop visual regression', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpWorkspace(tester, size: const Size(1440, 900));
    await tester.pump(const Duration(milliseconds: 350));
    editor.controller.focusAllNodes(animate: false);
    // The fixture is loaded before the widget exists; explicitly publish the
    // final graph snapshot so projection layers such as the minimap repaint
    // from the same link list as the canvas.
    editor.controller.notifyListeners();
    // The editor keeps a live ticker for its viewport projections, so settle
    // is intentionally not used here. A short bounded frame window lets
    // layout, link events, and the minimap repaint complete deterministically.
    for (var frame = 0; frame < 8; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await expectLater(
      find.byType(GraphWorkspace),
      matchesGoldenFile('goldens/editor_workspace.png'),
    );
  });

  testWidgets('renders independent automation tabs and selects a document', (
    tester,
  ) async {
    final documents = AutomationDocumentManager()
      ..open(
        const AutomationData(extra: {'name': 'First automation'}),
        'first.yaml',
      )
      ..open(
        const AutomationData(extra: {'name': 'Second automation'}),
        'second.yaml',
      );
    documents.activate('second.yaml');
    String? selected;

    await pumpWorkspace(
      tester,
      automationDocuments: documents,
      onAutomationSelected: (fileName) {
        selected = fileName;
        documents.activate(fileName);
      },
    );

    expect(find.text('First automation'), findsOneWidget);
    expect(find.text('Second automation'), findsOneWidget);
    await tester.tap(find.text('First automation'));
    expect(selected, 'first.yaml');
  });

  testWidgets('renders the compact editor used by inline automations', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShowRunnerInlineGraphEditor(
            editor: editor,
            registryFuture: Future.value(DartPluginRegistry()),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(GraphCanvasControls), findsOneWidget);
    expect(find.text('Chat message'), findsNWidgets(2));
    expect(find.text('Add to queue'), findsNothing);
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

  testWidgets('resolves flow links in global screen coordinates', (
    tester,
  ) async {
    await pumpWorkspace(tester);
    await tester.pump(const Duration(milliseconds: 100));

    final link = editor.controller.linksAsList.first;
    final source = editor.controller.nodes[link.endpoints.sourceNodeId]!;
    final target = editor.controller.nodes[link.endpoints.targetNodeId]!;
    final sourcePort = source.ports[link.endpoints.sourcePortId]!;
    final targetPort = target.ports[link.endpoints.targetPortId]!;
    final start = source.offset + sourcePort.offset;
    final end = target.offset + targetPort.offset;
    final control = math.min((end.dx - start.dx).abs() / 2, 400.0);
    const inverse = 0.5;
    final firstControl = Offset(start.dx + control, start.dy);
    final secondControl = Offset(end.dx - control, end.dy);
    final midpoint =
        start * (inverse * inverse * inverse) +
        firstControl * (3 * inverse * inverse * 0.5) +
        secondControl * (3 * inverse * 0.5 * 0.5) +
        end * (0.5 * 0.5 * 0.5);
    final editorBox =
        editor.controller.editorKey.currentContext!.findRenderObject()!
            as RenderBox;
    final globalPoint = editorBox.localToGlobal(
      editor.controller.worldToScreen(midpoint, editorBox.size),
    );

    expect(editor.flowLinkIdAtScreenPosition(globalPoint), link.id);
  });

  testWidgets('publishes alignment guides while moving a selected node', (
    tester,
  ) async {
    await pumpWorkspace(tester);
    final node = editor.controller.nodes.values.first;
    editor.controller.selectNodesById({node.id});
    editor.controller.dragSelection(const Offset(24, 0), isWorldDelta: true);
    await tester.pump();
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1)),
    );
    await tester.pump();

    expect(editor.alignmentGuides.value, isNotEmpty);
    expect(
      editor.alignmentGuides.value
          .map((guide) => guide.axis)
          .contains(GraphAlignmentAxis.horizontal),
      isTrue,
    );
  });

  testWidgets('selects and drags a node from the rendered graph canvas', (
    tester,
  ) async {
    await pumpWorkspace(tester);

    final node = editor.controller.nodes.values.first;
    final editorRenderObject = editor.controller.editorKey.currentContext
        ?.findRenderObject();
    expect(editorRenderObject, isA<RenderBox>());
    final editorBox = editorRenderObject! as RenderBox;
    final nodeRenderObject = node.key.currentContext?.findRenderObject();
    expect(nodeRenderObject, isA<RenderBox>());
    final nodeBox = nodeRenderObject! as RenderBox;
    final nodeTopLeft = editor.controller.worldToScreen(
      node.offset,
      editorBox.size,
    );
    final nodeCenter = editorBox.localToGlobal(
      nodeTopLeft + nodeBox.size.center(Offset.zero),
    );

    await tester.tapAt(nodeCenter);
    await tester.pump();
    expect(editor.controller.selectedNodeIds, contains(node.id));

    final initialOffset = node.offset;
    await tester.dragFrom(
      nodeCenter,
      const Offset(56, 28),
      buttons: kPrimaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    // The app-level double-click hook is layered above the generic node
    // gesture recognizer. Let its single-tap disambiguation timer settle
    // before the widget tree is disposed.
    await tester.pump(const Duration(milliseconds: 500));

    expect(node.offset, isNot(initialOffset));
  });

  testWidgets('keeps area selection and node context menus aligned', (
    tester,
  ) async {
    await pumpWorkspace(tester);
    final node = editor.controller.nodes.values.first;
    final editorRenderObject = editor.controller.editorKey.currentContext
        ?.findRenderObject();
    expect(editorRenderObject, isA<RenderBox>());
    final editorBox = editorRenderObject! as RenderBox;
    final nodeRenderObject = node.key.currentContext?.findRenderObject();
    expect(nodeRenderObject, isA<RenderBox>());
    final nodeBox = nodeRenderObject! as RenderBox;
    final nodeTopLeft = editor.controller.worldToScreen(
      node.offset,
      editorBox.size,
    );
    final nodeRect =
        nodeTopLeft & (nodeBox.size * editor.controller.viewportZoom);
    final selectionStart = editorBox.localToGlobal(
      Offset(4, nodeRect.top - 24),
    );
    final selectionEnd = editorBox.localToGlobal(
      nodeRect.bottomRight + const Offset(24, 24),
    );

    editor.controller.clearSelection();
    await tester.dragFrom(
      selectionStart,
      selectionEnd - selectionStart,
      buttons: kPrimaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();

    expect(editor.controller.selectedNodeIds, contains(node.id));

    final contextNode = editor.controller.nodes.values.elementAt(1);
    final contextNodeBox = contextNode.key.currentContext?.findRenderObject();
    expect(contextNodeBox, isA<RenderBox>());
    final contextNodeTopLeft = editor.controller.worldToScreen(
      contextNode.offset,
      editorBox.size,
    );
    final nodeCenter = editorBox.localToGlobal(
      contextNodeTopLeft +
          (contextNodeBox! as RenderBox).size.center(Offset.zero) *
              editor.controller.viewportZoom,
    );
    await tester.tapAt(nodeCenter, buttons: kSecondaryMouseButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Focus node'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
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

  testWidgets('selects and cleans stale links from the canvas health banner', (
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

    expect(find.text('1 invalid sequence edge'), findsOneWidget);
    await tester.tap(find.text('Select').first);
    await tester.pump();

    expect(editor.selectedInvalidFlowEdgeId.value, 'stale');
    expect(find.text('Invalid sequence edge'), findsOneWidget);
    await tester.tap(find.text('Clean up').last);
    await tester.pump();

    expect(editor.invalidFlowEdges, isEmpty);
    expect(find.text('1 invalid sequence edge'), findsNothing);
  });

  testWidgets('renders branch labels from persisted control-flow metadata', (
    tester,
  ) async {
    editor.loadAutomation(
      const AutomationData(
        graph: AutomationGraph(
          nodes: [
            GraphNode(
              id: 'switch',
              type: 'switch',
              x: -180,
              y: 0,
              data: {
                'cases': [
                  {'value': 'subscriber', 'port': 'case:0'},
                ],
              },
            ),
            GraphNode(id: 'target', type: 'queue.addItem', x: 180, y: 0),
          ],
          edges: [
            GraphEdge(
              id: 'branch',
              from: 'switch',
              to: 'target',
              port: 'case:0',
            ),
          ],
          entryNodeId: 'switch',
        ),
      ),
    );
    await pumpWorkspace(tester);

    expect(editor.controller.linksAsList.single.label, 'case: subscriber');
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

  testWidgets(
    'keeps disabled plugin nodes out of creation menus while preserving data',
    (tester) async {
      final registry = DartPluginRegistry()
        ..register(
          DartPluginManifest(
            id: 'sample',
            name: 'Sample',
            actions: [
              DartActionDefinition(
                pluginId: 'sample',
                actionId: 'emit',
                displayName: 'Emit value',
                invoke: (config, context) async => config['value'],
              ),
            ],
          ),
        );
      registry.setPluginEnabled('sample', false);
      const automation = AutomationData(
        graph: AutomationGraph(
          nodes: [
            GraphNode(
              id: 'disabled-action',
              type: 'action',
              x: 0,
              y: 0,
              data: {
                'plugin': 'sample',
                'action': 'emit',
                'config': {'value': 'kept'},
              },
            ),
          ],
          entryNodeId: 'disabled-action',
        ),
      );
      editor.loadAutomation(automation);

      await pumpWorkspace(tester, registry: registry);

      final saved = editor.toAutomation(const AutomationData());
      expect(saved.graph.nodes.single.data['plugin'], 'sample');
      expect(saved.graph.nodes.single.data['action'], 'emit');
      expect(saved.graph.nodes.single.data['config'], {'value': 'kept'});

      await tester.tapAt(
        const Offset(1050, 650),
        buttons: kSecondaryMouseButton,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Disabled plugins'), findsNothing);
      expect(find.text('Emit value'), findsNothing);
    },
  );
}
