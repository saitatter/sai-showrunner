import 'package:flutter_test/flutter_test.dart';
import 'package:sai_nodes_core/sai_nodes_core.dart';
import 'package:showrunner_flutter/graph/controller/automation_editor_controller.dart';
import 'package:showrunner_flutter/graph/domain/automation_document.dart';
import 'package:showrunner_flutter/graph/definitions/showrunner_graph_types.dart';
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

  test(
    'node and entry reconciliation share one undo entry and saved revision',
    () {
      final id = editor.addNode('showrunner.if', GraphPoint.zero);
      expect(editor.document.entryNodeId, id);
      expect(editor.graph.undoCount, 1);
      editor.graph.undo();
      expect(editor.document.entryNodeId, '');
      expect(editor.graph.activeSpace!.nodes, isEmpty);
      expect(editor.isDirty, false);
      editor.graph.redo();
      editor.markSaved();
      editor.graph.execute(RemoveNodesCommand(mainAutomationSpace, [id]));
      expect(editor.document.entryNodeId, '');
      editor.graph.undo();
      expect(editor.document.entryNodeId, id);
      expect(editor.isDirty, false);
    },
  );
  test('deleting the entry selects a remaining executable node atomically', () {
    final first = editor.addNode('showrunner.if', GraphPoint.zero);
    editor.addNode('showrunner.variable', GraphPoint.zero);
    final second = editor.addNode('showrunner.return', GraphPoint.zero);
    editor.graph.execute(RemoveNodesCommand(mainAutomationSpace, [first]));
    expect(editor.document.entryNodeId, second);
    editor.graph.undo();
    expect(editor.document.entryNodeId, first);
  });
  test(
    'subgraph creation, signatures and deletion use the same document history',
    () {
      final id = editor.createSubgraph();
      final signature = editor.document.subgraphs[id]!;
      expect(editor.graph.activeSpaceId, signature.spaceId);
      expect(editor.graph.undoCount, 1);
      editor.updateSubgraph(
        signature.copyWith(
          parameters: [
            AutomationParameter(id: 'p', name: 'Input', type: 'core.number'),
          ],
        ),
      );
      expect(editor.activeSubgraph!.parameters.single.id, 'p');
      editor.graph.undo();
      expect(editor.activeSubgraph!.parameters, isEmpty);
      editor.graph.redo();
      editor.deleteSubgraph(id);
      expect(editor.document.subgraphs, isEmpty);
      expect(editor.graph.document.spaces, isNot(contains(signature.spaceId)));
      expect(editor.graph.activeSpaceId, mainAutomationSpace);
      editor.graph.undo();
      expect(editor.document.subgraphs[id]!.parameters.single.id, 'p');
      expect(editor.graph.document.spaces, contains(signature.spaceId));
    },
  );
  test(
    'hot registration resolves existing unknown nodes without replacing IDs',
    () {
      final type = actionNodeType('late', 'action');
      editor.graph.execute(
        AddNodeCommand(
          mainAutomationSpace,
          GraphNode(id: 'original', type: type),
        ),
      );
      expect(editor.graph.resolution.diagnostics, isNotEmpty);
      registry.register(
        DartPluginManifest(
          id: PluginId('late'),
          name: 'Late',
          actions: [
            ActionSpec<Map<String, dynamic>, Object?>(
              pluginId: PluginId('late'),
              actionId: ActionId('action'),
              invoke: (config, context) async => config,
            ),
          ],
        ),
      );
      expect(editor.graph.activeSpace!.nodes.keys, ['original']);
      expect(editor.graph.resolution.diagnostics, isEmpty);
    },
  );
}
