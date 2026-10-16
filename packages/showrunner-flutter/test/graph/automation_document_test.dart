import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sai_nodes_core/sai_nodes_core.dart';
import 'package:showrunner_flutter/graph/domain/automation_document.dart';
import 'package:showrunner_flutter/graph/definitions/showrunner_graph_types.dart';
import 'package:showrunner_flutter/graph/definitions/showrunner_node_definition_provider.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_bootstrap.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/schema/data_input.dart';

void main() {
  test(
    'canonical envelope round-trips without duplicate host settings or graph IDs',
    () {
      var document = AutomationDocument.empty(id: 'doc');
      document = document
          .withSettings({'entryNodeId': 'missing', 'queue': 'test'})
          .withSubgraphs({
            'helper': AutomationSubgraph(
              id: 'helper',
              name: 'Helper',
              entryNodeId: 'entry',
              parameters: [
                AutomationParameter(
                  id: 'p',
                  name: 'value',
                  type: 'core.number',
                  defaultValue: 4,
                ),
              ],
            ),
          });
      final json = document.toJson();
      expect(
        (json['graph'] as Map)['metadata'],
        isNot(contains(automationHostMetadata)),
      );
      final restored = AutomationDocument.fromJson(
        jsonDecode(jsonEncode(json)) as Map<String, Object?>,
      );
      expect(restored.graph, document.graph);
      expect(restored.queueId, 'test');
      expect(restored.subgraphs['helper']!.parameters.single.defaultValue, 4);
      expect(
        () => restored.settings['queue'] = 'other',
        throwsUnsupportedError,
      );
      expect(
        () => AutomationDocument.fromJson({...json, 'schemaVersion': 2}),
        throwsFormatException,
      );
      expect(
        () => AutomationDocument.fromJson({...json, 'id': 'different'}),
        throwsFormatException,
      );
    },
  );
  test(
    'all plugin action/trigger schemas generate declarative definitions without truncation',
    () {
      final registry = createDefaultPluginRegistry();
      addTearDown(registry.close);
      final provider = ShowrunnerNodeDefinitionProvider(registry);
      addTearDown(provider.dispose);
      final empty = AutomationDocument.empty(id: 'catalog');
      final nodes = <String, GraphNode>{};
      var number = 0;
      for (final entry in provider.definitions.definitions.entries) {
        final id = 'node-${number++}';
        nodes[id] = GraphNode(
          id: id,
          type: entry.key,
          data: provider.defaultData(entry.key),
        );
      }
      final graph = empty.graph.copyWith(
        spaces: {
          mainAutomationSpace: GraphSpace(
            id: mainAutomationSpace,
            nodes: nodes,
          ),
        },
      );
      final result = GraphResolver(
        definitions: provider.definitions,
        types: createShowrunnerGraphTypes(),
      ).resolve(graph);
      expect(result.converged, true);
      expect(result.diagnostics, isEmpty);
      for (final plugin in registry.plugins) {
        for (final action in plugin.actions) {
          final node = nodes.values.singleWhere(
            (node) =>
                node.type ==
                actionNodeType(plugin.id.value, action.actionId.value),
          );
          final structure = result.structures[mainAutomationSpace]![node.id]!;
          expect(
            structure.fields.length,
            provider.schemaFields(action.configSchema).length,
            reason: node.type,
          );
        }
      }
    },
  );
  test(
    'subgraph signature edits preserve stable call ports and diagnose removed parameters',
    () {
      final registry = DartPluginRegistry();
      addTearDown(registry.close);
      final provider = ShowrunnerNodeDefinitionProvider(registry);
      addTearDown(provider.dispose);
      var document = AutomationDocument.empty(id: 'd').withSubgraphs({
        'helper': AutomationSubgraph(
          id: 'helper',
          name: 'Helper',
          entryNodeId: '',
          parameters: [
            AutomationParameter(id: 'p', name: 'Value', type: 'core.number'),
          ],
        ),
      });
      document = AutomationDocument.fromGraph(
        document.graph.copyWith(
          spaces: {
            mainAutomationSpace: GraphSpace(
              id: mainAutomationSpace,
              nodes: {
                'variable': GraphNode(
                  id: 'variable',
                  type: 'showrunner.variable',
                  data: {
                    'name': 'value',
                    'dataType': 'core.number',
                    'value': 4,
                  },
                ),
                'call': GraphNode(
                  id: 'call',
                  type: 'showrunner.subgraphCall',
                  data: {'subgraphId': 'helper'},
                ),
              },
              connections: {
                'wire': GraphConnection(
                  id: 'wire',
                  from: const PortRef(nodeId: 'variable', portId: 'value.out'),
                  to: const PortRef(nodeId: 'call', portId: 'parameter:p'),
                  kind: GraphConnectionKind.data,
                ),
              },
            ),
          },
        ),
      );
      final graph = GraphController(
        document: document.graph,
        resolver: GraphResolver(
          definitions: provider.definitions,
          types: createShowrunnerGraphTypes(),
        ),
      );
      addTearDown(graph.dispose);
      expect(graph.resolution.diagnostics, isEmpty);
      final renamed = document.withSubgraphs({
        'helper': document.subgraphs['helper']!.copyWith(
          parameters: [
            AutomationParameter(id: 'p', name: 'Renamed', type: 'core.number'),
          ],
        ),
      });
      graph.execute(UpdateDocumentMetadataCommand(renamed.graph.metadata));
      expect(graph.resolution.diagnostics, isEmpty);
      expect(
        graph.resolution.structures[mainAutomationSpace]!['call']!
            .port('parameter:p')!
            .label,
        'Renamed',
      );
      final removed = renamed.withSubgraphs({
        'helper': renamed.subgraphs['helper']!.copyWith(parameters: []),
      });
      graph.execute(UpdateDocumentMetadataCommand(removed.graph.metadata));
      expect(graph.document.spaces[mainAutomationSpace]!.connections.keys, [
        'wire',
      ]);
      expect(
        graph.resolution.diagnostics.map((issue) => issue.code),
        contains('missing-target-port'),
      );
      graph.undo();
      expect(graph.resolution.diagnostics, isEmpty);
      expect(graph.document.spaces[mainAutomationSpace]!.connections.keys, [
        'wire',
      ]);
    },
  );
  test('type bridge covers every input kind with stable string IDs', () {
    final types = createShowrunnerGraphTypes();
    for (final kind in DartDataInputKind.values) {
      expect(types.types.containsKey(graphTypeForInput(kind)), true);
    }
    expect(
      actionNodeType('plugin/name', 'action:with spaces'),
      'action:plugin%2Fname/action%3Awith%20spaces',
    );
    expect(
      decodeContractNodeType(
        actionNodeType('plugin/name', 'action:with spaces'),
        'action',
      ),
      ('plugin/name', 'action:with spaces'),
    );
  });
}
