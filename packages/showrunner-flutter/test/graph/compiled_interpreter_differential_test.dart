import 'dart:convert';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:sai_nodes_core/sai_nodes_core.dart';
import 'package:showrunner_flutter/graph/domain/automation_document.dart';
import 'package:showrunner_flutter/graph/runtime/graph_execution_engine.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/runtime/cancellation.dart';
import 'package:showrunner_flutter/runtime/expression.dart';
import '../support/graph_execution_fixture.dart';

void main() {
  for (var seed = 0; seed < 30; seed++) {
    for (final mode in ['complete', 'cancel', 'fail']) {
      test('seed=$seed mode=$mode compiled/interpreter differential', () async {
        final doc = seededDocument(seed);
        final original = jsonEncode(doc.toJson());
        // Only synthetic data goes into this reproducible failure description.
        final reason = 'seed=$seed mode=$mode graph=$original';
        final oracle = await run(doc, const InterpreterExecutionEngine(), mode);
        final compiled = await run(doc, CompiledExecutionEngine(), mode);
        expect(compiled, oracle, reason: reason);
        expect(jsonEncode(doc.toJson()), original, reason: reason);
        if (mode == 'complete') {
          expect(compiled['error'], isNull, reason: reason);
          expect(compiled['completed'], true, reason: reason);
        } else {
          expect(
            compiled['error'],
            mode == 'cancel' ? 'DartCancelledException' : 'StateError',
            reason: reason,
          );
          expect((compiled['observations'] as List).length, 1, reason: reason);
        }
      });
    }
  }
}

AutomationDocument seededDocument(int seed) {
  final random = Random(seed);
  final count = 1 + random.nextInt(5);
  final flag = random.nextBool();
  final kind = switch (seed % 3) {
    0 => 'for',
    1 => 'forEach',
    _ => 'while',
  };
  final inner = AutomationSubgraph(
    id: 'inner',
    name: 'Inner',
    entryNodeId: 'record',
    parameters: [
      AutomationParameter(id: 'p', name: 'value', defaultValue: seed),
    ],
    outputs: [AutomationParameter(id: 'o', name: 'answer')],
  );
  final outer = AutomationSubgraph(
    id: 'outer',
    name: 'Outer',
    entryNodeId: 'inner-call',
    outputs: [AutomationParameter(id: 'o', name: 'answer')],
  );
  final nodes = [
    GraphNode(
      id: 'loop',
      type: 'showrunner.$kind',
      data: kind == 'while'
          ? {
              'condition': {
                'type': 'binary',
                'op': '>',
                'left': {'type': 'variable', 'name': 'remaining'},
                'right': {'type': 'literal', 'value': 0},
              },
            }
          : kind == 'for'
          ? {'start': 0, 'end': count, 'step': 1, 'variable': 'counter'}
          : {
              'collection': [for (var i = 0; i < count; i++) seed + i],
              'variable': 'item',
            },
    ),
    GraphNode(
      id: 'flag',
      type: 'showrunner.variable',
      data: {'name': 'flag', 'value': flag, 'dataType': 'core.boolean'},
    ),
    GraphNode(id: 'branch', type: 'showrunner.if', data: {'condition': !flag}),
    action('then', value: seed),
    action('else', value: -seed),
    GraphNode(
      id: 'switch',
      type: 'showrunner.switch',
      data: {
        'expression': seed % 3,
        'cases': [
          {'id': 'selected', 'value': seed % 3},
        ],
      },
    ),
    GraphNode(
      id: 'outer-call',
      type: 'showrunner.subgraphCall',
      data: {'subgraphId': 'outer'},
    ),
    GraphNode(
      id: 'return',
      type: 'showrunner.return',
      data: {
        'outputs': {'result': seed},
      },
    ),
  ];
  final connections = [
    flow('loop', 'branch', port: 'flow:body'),
    wire('flag', 'value.out', 'branch', 'config:condition'),
    flow('branch', 'then', port: 'flow:then'),
    flow('branch', 'else', port: 'flow:else'),
    flow('then', 'switch'),
    flow('else', 'switch'),
    flow('switch', 'outer-call', port: 'case:selected'),
    flow('loop', 'return', port: 'flow:next'),
  ];
  final innerEdges = [
    flow('record', 'inner-ret'),
    wire('record', 'result:value', 'inner-ret', 'output:o'),
  ];
  final outerEdges = [
    flow('inner-call', 'outer-ret'),
    wire('inner-call', 'output:o', 'outer-ret', 'output:o'),
  ];
  return document(
    nodes,
    connections,
    entry: 'loop',
    subgraphs: {'inner': inner, 'outer': outer},
    spaces: {
      inner.spaceId: GraphSpace(
        id: inner.spaceId,
        nodes: {
          'record': action('record', value: '{{value}}'),
          'inner-ret': GraphNode(id: 'inner-ret', type: 'showrunner.return'),
        },
        connections: {for (final edge in innerEdges) edge.id: edge},
      ),
      outer.spaceId: GraphSpace(
        id: outer.spaceId,
        nodes: {
          'inner-call': GraphNode(
            id: 'inner-call',
            type: 'showrunner.subgraphCall',
            data: {
              'subgraphId': 'inner',
              'arguments': {'p': seed + 100},
            },
          ),
          'outer-ret': GraphNode(id: 'outer-ret', type: 'showrunner.return'),
        },
        connections: {for (final edge in outerEdges) edge.id: edge},
      ),
    },
  );
}

Future<Map<String, Object?>> run(
  AutomationDocument doc,
  GraphExecutionEngine engine,
  String mode,
) async {
  final token = DartCancellationToken();
  final observations = <Object?>[];
  final registry = DartPluginRegistry()
    ..register(
      DartPluginManifest(
        id: PluginId('fixture'),
        name: 'Differential',
        actions: [
          ActionSpec<Map<String, dynamic>, Object?>(
            pluginId: PluginId('fixture'),
            actionId: ActionId('record'),
            configSchema: fixtureSchema,
            resultSchema: fixtureSchema,
            invoke: (config, context) async {
              observations.add({
                'config': jsonDecode(jsonEncode(config)),
                'state': jsonDecode(jsonEncode(context.contextState)),
                'locals': {
                  for (final key in ['counter', 'item', 'value'])
                    if (context.locals.containsKey(key))
                      key: context.locals[key],
                },
              });
              context.contextState['remaining'] =
                  (context.contextState['remaining'] as int) - 1;
              if (mode == 'cancel') {
                token.cancel();
              }
              if (mode == 'fail') {
                throw StateError('Synthetic failure');
              }
              return {'value': config['value']};
            },
          ),
        ],
      ),
    );
  try {
    final result = await engine.executeWithRegistry(
      automation: doc,
      context: EvaluationContext(
        cancellationToken: token,
        contextState: {'remaining': 5},
      ),
      registry: registry,
    );
    return {
      'observations': observations,
      'completed': result.completed,
      'nodes': result.nodeResults,
      'state': result.contextState,
      'outputs': result.outputValues,
      'error': null,
    };
  } catch (error) {
    return {
      'observations': observations,
      'error': error.runtimeType.toString(),
    };
  } finally {
    await registry.close();
  }
}
