import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sai_nodes/sai_nodes.dart' show NodeEditor;
import 'package:sai_nodes_core/sai_nodes_core.dart';
import 'package:showrunner_flutter/graph/controller/automation_editor_controller.dart';
import 'package:showrunner_flutter/graph/domain/automation_document.dart';
import 'package:showrunner_flutter/graph/ui/automation_graph_workspace.dart';
import 'package:showrunner_flutter/graph/ui/graph_value_input.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';

void main() {
  late DartPluginRegistry registry;
  late AutomationEditorController editor;
  setUp(() {
    registry = DartPluginRegistry();
    editor = AutomationEditorController(
      document: AutomationDocument.empty(id: 'd'),
      registry: registry,
    );
  });
  tearDown(() async {
    editor.dispose();
    await registry.close();
  });

  testWidgets('find locates a subgraph node without editing the document', (
    tester,
  ) async {
    final space = editor.createSubgraph();
    final node = editor.addNode('showrunner.if', const GraphPoint(1800, 1200));
    editor.graph.execute(
      SetNodeTitleCommand(
        editor.document.subgraphs[space]!.spaceId,
        node,
        'Search target',
      ),
    );
    editor.graph.setActiveSpace(mainAutomationSpace);
    editor.graph.markSaved();
    final revision = editor.graph.revision;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AutomationGraphWorkspace(editor: editor)),
      ),
    );
    await tester.tap(find.byTooltip('Find in graph'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Search graph nodes'),
      'Search target',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(ListTile, 'Search target'));
    await tester.pumpAndSettle();
    expect(
      editor.graph.activeSpaceId,
      editor.document.subgraphs[space]!.spaceId,
    );
    expect(editor.graph.selection.nodes, {node});
    expect(editor.graph.revision, revision);
    expect(editor.isDirty, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('narrow workspace exposes a reactive inspector sheet', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(560, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final node = editor.addNode('showrunner.if', GraphPoint.zero);
    editor.graph.select(GraphSelection(nodes: {node}));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AutomationGraphWorkspace(editor: editor)),
      ),
    );
    await tester.tap(find.byTooltip('Inspector'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('Set as entry node'), findsOneWidget);
    editor.graph.execute(
      SetNodeTitleCommand(mainAutomationSpace, node, 'Sheet update'),
    );
    await tester.pump();
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.controller?.text == 'Sheet update',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'subgraph parameter editing preserves its ID and rejects malformed default drafts',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final id = editor.createSubgraph();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AutomationGraphWorkspace(editor: editor)),
        ),
      );
      await tester.tap(find.text('Add parameter'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Name'),
        'Input',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Default value (JSON)'),
        '{invalid',
      );
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
            .onPressed,
        isNull,
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Default value (JSON)'),
        '42',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      final original = editor.document.subgraphs[id]!.parameters.single;
      expect(original.defaultValue, 42);
      await tester.tap(find.widgetWithText(ListTile, 'Input'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Name'),
        'Renamed',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(editor.document.subgraphs[id]!.parameters.single.id, original.id);
      expect(editor.document.subgraphs[id]!.parameters.single.name, 'Renamed');
      editor.graph.undo();
      expect(editor.document.subgraphs[id]!.parameters.single.name, 'Input');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'palette creates a canonical node; inspector edits and toolbar undo share history',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AutomationGraphWorkspace(editor: editor)),
        ),
      );
      expect(find.byType(NodeEditor), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('graph-add-node')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Search nodes'),
        'If',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(ListTile, 'If'));
      await tester.pumpAndSettle();
      final node = editor.graph.activeSpace!.nodes.values.single;
      expect(node.type, 'showrunner.if');
      expect(editor.document.entryNodeId, node.id);
      expect(editor.graph.undoCount, 1);
      final title = find.descendant(
        of: find.byKey(ValueKey('${node.id}/title')),
        matching: find.byType(TextField),
      );
      await tester.enterText(title, 'Branch');
      await tester.pump();
      expect(
        editor.graph.activeSpace!.nodePresentations[node.id]!.title,
        'Branch',
      );
      await tester.tap(find.byTooltip('Undo'));
      await tester.pump();
      expect(
        editor.graph.activeSpace!.nodePresentations[node.id]!.title,
        isNull,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'workspace subgraph action creates one undoable space and declaration',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AutomationGraphWorkspace(editor: editor)),
        ),
      );
      await tester.tap(find.byTooltip('New subgraph'));
      await tester.pumpAndSettle();
      final signature = editor.document.subgraphs.values.single;
      expect(editor.graph.activeSpaceId, signature.spaceId);
      expect(editor.graph.undoCount, 1);
      await tester.tap(find.byTooltip('Undo'));
      await tester.pumpAndSettle();
      expect(editor.document.subgraphs, isEmpty);
      expect(editor.graph.activeSpaceId, mainAutomationSpace);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'invalid JSON remains a visible local draft and never changes document data',
    (tester) async {
      final id = editor.addNode('showrunner.if', GraphPoint.zero);
      final field = editor
          .graph
          .resolution
          .structures[mainAutomationSpace]![id]!
          .fields
          .single;
      final original = editor.graph.document;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GraphValueInput(
              field: field,
              value: true,
              onChanged: (value) => editor.updateField(id, field, value),
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), '{invalid');
      await tester.pump();
      expect(editor.graph.document, same(original));
      expect(find.textContaining('Unexpected'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'false');
      await tester.pump();
      expect(editor.graph.activeSpace!.nodes[id]!.data['condition'], false);
      editor.graph.undo();
      expect(editor.graph.document, original);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
