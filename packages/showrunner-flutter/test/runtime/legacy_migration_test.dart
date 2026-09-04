import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/runtime/expression.dart';
import 'package:showrunner_flutter/runtime/graph_runtime.dart';
import 'package:showrunner_flutter/schema/automation.dart';

void main() {
  test('converts legacy sequence actions into an executable graph', () async {
    final automation = AutomationData.fromJson({
      'name': 'Legacy alert',
      'sequence': {
        'actions': [
          {
            'id': 'first',
            'plugin': 'sample',
            'action': 'emit',
            'config': {'value': 'hello'},
            'resultMapping': {'value': 'lastValue'},
          },
          {
            'id': 'stack',
            'stack': [
              {
                'id': 'second',
                'plugin': 'sample',
                'action': 'emit',
                'config': {'value': 'world'},
              },
            ],
          },
          {
            'plugin': 'sample',
            'action': 'emit',
            'config': {'value': 'nested'},
            'subFlows': [
              {
                'actions': [
                  {
                    'plugin': 'sample',
                    'action': 'emit',
                    'config': {'value': 'done'},
                  },
                ],
              },
            ],
          },
        ],
      },
      'floatingSequences': [
        {
          'id': 'old-floating',
          'name': 'Old floating alert',
          'actions': [
            {
              'id': 'floating-action',
              'plugin': 'sample',
              'action': 'emit',
              'config': {'value': 'floating'},
            },
          ],
        },
      ],
      'variableNodes': [
        {'id': 'message', 'name': 'Message', 'type': 'string', 'value': ''},
      ],
      'dataWires': [
        {
          'id': 'legacy-wire',
          'fromNode': 'first',
          'fromPort': 'value',
          'toNode': 'legacy-action-3',
          'toPort': 'value',
        },
      ],
    });

    expect(automation.schemaVersion, 2);
    expect(automation.extra['name'], 'Legacy alert');
    expect(automation.graph.nodes.map((node) => node.id), [
      'first',
      'second',
      'legacy-action-3',
      'legacy-action-4',
    ]);
    expect(automation.graph.edges, hasLength(3));
    expect(automation.subgraphs.single.id, 'old-floating');
    expect(automation.subgraphs.single.nodes.single.id, 'floating-action');
    expect(automation.variableNodes.single['id'], 'message');
    expect(automation.dataWires.single.id, 'legacy-wire');
    expect(automation.graph.nodes[0].data['resultMapping'], {
      'value': 'lastValue',
    });
    expect(automation.toJson().containsKey('sequence'), isFalse);
    expect(automation.toJson().containsKey('floatingSequences'), isFalse);
    expect(automation.toJson()['subgraphs'], isNotEmpty);

    final registry = DartPluginRegistry()
      ..register(
        DartPluginManifest(
          id: 'sample',
          name: 'Sample',
          actions: [
            DartActionDefinition(
              pluginId: 'sample',
              actionId: 'emit',
              invoke: (config, context) async => {'value': config['value']},
            ),
          ],
        ),
      );
    final result = await const DartGraphRuntime().executeWithRegistry(
      graph: automation.graph,
      context: EvaluationContext(),
      registry: registry,
    );

    expect(result.completed, isTrue);
    expect(result.steps, 4);
    expect(result.contextState['lastValue'], 'hello');
    expect(result.nodeResults['legacy-action-4'], {'value': 'done'});
  });

  test('prefers an existing graph over a legacy sequence', () {
    final automation = AutomationData.fromJson({
      'graph': {
        'nodes': [
          {'id': 'graph-node', 'type': 'action', 'x': 0, 'y': 0},
        ],
        'edges': [],
        'entryNodeId': 'graph-node',
      },
      'sequence': {
        'actions': [
          {'plugin': 'sample', 'action': 'old'},
        ],
      },
    });

    expect(automation.graph.nodes.single.id, 'graph-node');
  });
}
