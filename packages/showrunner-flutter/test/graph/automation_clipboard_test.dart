import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/graph/controller/automation_clipboard.dart';
import 'package:showrunner_flutter/graph/controller/automation_editor_controller.dart';
import 'package:showrunner_flutter/graph/runtime/graph_execution_engine.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/runtime/expression.dart';
import '../support/graph_fixtures.dart';

void main() {
  test(
    'cross-document paste copies nested dependencies with fresh IDs in one undo step',
    () async {
      final source = AutomationEditorController(document: dependencyDocument());
      final target = AutomationEditorController(
        document: AutomationDocument.empty(id: 'target'),
      );
      addTearDown(source.dispose);
      addTearDown(target.dispose);
      source.graph.select(GraphSelection(nodes: {'root-call'}));
      final fragment = GraphFragment.decode(source.captureFragment().encode());
      final before = target.document.graph;
      final selected = target.pasteFragment(fragment);
      expect(target.graph.undoCount, 1);
      expect(target.document.subgraphs.length, 2);
      expect(
        target.document.subgraphs.keys.toSet().intersection(
          source.document.subgraphs.keys.toSet(),
        ),
        isEmpty,
      );
      final copiedNodes = {
        for (final space in target.document.graph.spaces.values)
          ...space.nodes.keys,
      };
      final originalNodes = {
        for (final space in source.document.graph.spaces.values)
          ...space.nodes.keys,
      };
      expect(copiedNodes.intersection(originalNodes), isEmpty);
      expect(target.graph.resolution.diagnostics, isEmpty);
      final frames = [
        for (final space in target.document.graph.spaces.values)
          ...space.frames.values,
      ];
      expect(frames.single.id, isNot('frame'));
      expect(frames.single.memberNodeIds.every(copiedNodes.contains), true);
      final comments = [
        for (final space in target.document.graph.spaces.values)
          ...space.comments.values,
      ];
      expect(comments.single.id, isNot('comment'));
      expect(comments.single.text, 'Dependency comment');
      final registry = DartPluginRegistry();
      addTearDown(registry.close);
      final result = await CompiledExecutionEngine().executeWithRegistry(
        automation: target.document,
        context: EvaluationContext(),
        registry: registry,
      );
      expect(result.nodeResults[selected.nodes.single]!['Answer'], 42);
      final after = target.document.graph;
      target.graph.undo();
      expect(target.document.graph, before);
      target.graph.redo();
      expect(target.document.graph, after);
      expect(source.document.graph, dependencyDocument().graph);
    },
  );
  test(
    'same-document duplicate reuses unchanged signatures and keeps recursive closures finite',
    () {
      final editor = AutomationEditorController(
        document: dependencyDocument(recursive: true),
      );
      addTearDown(editor.dispose);
      editor.graph.select(GraphSelection(nodes: {'root-call'}));
      final fragment = GraphFragment.decode(editor.captureFragment().encode());
      expect(
        (fragment.hostPayload['showrunner'] as Map)['subgraphs'],
        hasLength(2),
      );
      editor.pasteFragment(fragment);
      expect(editor.document.subgraphs, hasLength(2));
      expect(editor.document.graph.spaces, hasLength(3));
      expect(editor.graph.activeSpace!.nodes, hasLength(2));
      final target = AutomationEditorController(
        document: AutomationDocument.empty(id: 'other'),
      );
      addTearDown(target.dispose);
      target.pasteFragment(fragment);
      expect(target.document.subgraphs, hasLength(2));
      final dependencyCalls = [
        for (final space in target.document.graph.spaces.values)
          for (final node in space.nodes.values)
            if (node.type == 'showrunner.subgraphCall') node,
      ];
      expect(
        dependencyCalls.every(
          (node) =>
              target.document.subgraphs.containsKey(node.data['subgraphId']),
        ),
        true,
      );
    },
  );
  test(
    'only expression references are remapped; literal variable JSON stays unchanged',
    () {
      final literal = {'type': 'port', 'nodeId': 'value', 'port': 'value'};
      final editor = AutomationEditorController(
        document: automationFixture(
          nodes: [
            GraphNode(
              id: 'value',
              type: 'showrunner.variable',
              data: {'name': 'json', 'value': literal},
            ),
            GraphNode(
              id: 'condition',
              type: 'showrunner.if',
              data: {
                'condition': {
                  'type': 'port',
                  'nodeId': 'value',
                  'port': 'value',
                },
              },
            ),
            GraphNode(
              id: 'return',
              type: 'showrunner.return',
              data: {
                'outputs': {
                  'literal': {'type': 'literal', 'value': literal},
                },
              },
            ),
          ],
          entryNodeId: 'condition',
        ),
      );
      addTearDown(editor.dispose);
      editor.graph.select(
        GraphSelection(nodes: {'value', 'condition', 'return'}),
      );
      final selected = editor.pasteFragment(editor.captureFragment());
      final pasted = selected.nodes
          .map((id) => editor.graph.activeSpace!.nodes[id]!)
          .toList();
      final variable = pasted.singleWhere(
        (node) => node.type == 'showrunner.variable',
      );
      final condition = pasted.singleWhere(
        (node) => node.type == 'showrunner.if',
      );
      final returned = pasted.singleWhere(
        (node) => node.type == 'showrunner.return',
      );
      expect(variable.data['value'], literal);
      expect((condition.data['condition'] as Map)['nodeId'], variable.id);
      expect(
        (((returned.data['outputs'] as Map)['literal']) as Map)['value'],
        literal,
      );
    },
  );
  test('malformed dependency payload leaves target and history untouched', () {
    final editor = AutomationEditorController(
      document: AutomationDocument.empty(),
    );
    addTearDown(editor.dispose);
    final before = editor.document.graph;
    expect(
      () => editor.pasteFragment(
        GraphFragment(
          space: GraphSpace(id: 'fragment'),
          hostPayload: {
            'showrunner': {'version': 99},
          },
        ),
      ),
      throwsFormatException,
    );
    expect(editor.document.graph, before);
    expect(editor.graph.undoCount, 0);
  });
}

AutomationDocument dependencyDocument({bool recursive = false}) {
  final leaf = AutomationSubgraph(
    id: 'leaf',
    name: 'Leaf',
    entryNodeId: 'leaf-return',
    outputs: [
      AutomationParameter(id: 'leaf-output', name: 'Answer', defaultValue: 42),
    ],
  );
  final branch = AutomationSubgraph(
    id: 'branch',
    name: 'Branch',
    entryNodeId: 'leaf-call',
    outputs: [AutomationParameter(id: 'branch-output', name: 'Answer')],
  );
  final leafReturn = GraphNode(id: 'leaf-return', type: 'showrunner.return');
  final leafCall = GraphNode(
    id: 'leaf-call',
    type: 'showrunner.subgraphCall',
    data: {'subgraphId': leaf.id},
  );
  final branchReturn = GraphNode(
    id: 'branch-return',
    type: 'showrunner.return',
  );
  final flow = controlFixture('return-flow', leafCall.id, branchReturn.id);
  final value = valueFixture(
    'return-value',
    leafCall.id,
    'output:leaf-output',
    branchReturn.id,
    'output:branch-output',
  );
  return automationFixture(
    id: 'source',
    nodes: [
      GraphNode(
        id: 'root-call',
        type: 'showrunner.subgraphCall',
        data: {'subgraphId': branch.id},
      ),
    ],
    entryNodeId: 'root-call',
    subgraphs: {leaf.id: leaf, branch.id: branch},
    spaces: {
      leaf.spaceId: GraphSpace(
        id: leaf.spaceId,
        nodes: {
          leafReturn.id: leafReturn,
          if (recursive)
            'recursive': GraphNode(
              id: 'recursive',
              type: 'showrunner.subgraphCall',
              data: {'subgraphId': branch.id},
            ),
        },
        frames: {
          'frame': GraphFrame(
            id: 'frame',
            title: 'Dependency',
            bounds: const GraphRect(0, 0, 400, 300),
            memberNodeIds: {leafReturn.id},
          ),
        },
        comments: {
          'comment': GraphComment(
            id: 'comment',
            bounds: const GraphRect(0, 320, 400, 90),
            text: 'Dependency comment',
          ),
        },
      ),
      branch.spaceId: GraphSpace(
        id: branch.spaceId,
        nodes: {leafCall.id: leafCall, branchReturn.id: branchReturn},
        connections: {flow.id: flow, value.id: value},
      ),
    },
  );
}
