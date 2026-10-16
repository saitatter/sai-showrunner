import 'package:flutter_test/flutter_test.dart';
import 'package:sai_nodes_core/sai_nodes_core.dart';
import 'package:showrunner_flutter/graph/domain/automation_document.dart';
import 'package:showrunner_flutter/graph/definitions/showrunner_graph_types.dart';
import 'package:showrunner_flutter/graph/runtime/graph_execution_engine.dart';
import 'package:showrunner_flutter/graph/runtime/graph_runtime.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/runtime/expression.dart';
import 'package:showrunner_flutter/runtime/cancellation.dart';
import 'package:showrunner_flutter/schema/data_input.dart';

void main() {
  test('literal variables retain objects containing a type property', () async {
    final result = await parity(
      document(
        [
          GraphNode(
            id: 'v',
            type: 'showrunner.variable',
            data: {
              'name': 'payload',
              'value': {'type': 'message', 'text': 'hello'},
            },
          ),
          action('a'),
        ],
        [wire('v', 'value.out', 'a', 'config:value')],
        entry: 'a',
      ),
    );
    expect(result.nodeResults['a']!['value'], {
      'type': 'message',
      'text': 'hello',
    });
  });
  test(
    'trigger payload and complete action results use actual node IDs',
    () async {
      final result = await parity(
        document(
          [
            GraphNode(
              id: 'source',
              type: triggerNodeType('fixture', 'message'),
            ),
            action('a'),
            action('b'),
            action('c'),
          ],
          [
            flow('source', 'a'),
            flow('a', 'b'),
            flow('b', 'c'),
            wire('source', 'event:text', 'a', 'config:value'),
            wire('a', 'result', 'b', 'config:value'),
            wire('source', 'event', 'c', 'config:value'),
          ],
          entry: 'source',
        ),
        context: () => EvaluationContext(
          contextState: {
            'trigger': {'text': 'hello', 'user': 'tester'},
          },
        ),
      );
      expect(result.nodeResults['a'], {'value': 'hello'});
      expect(result.nodeResults['b'], {
        'value': {'value': 'hello'},
      });
      expect(result.nodeResults['c']!['value'], {
        'text': 'hello',
        'user': 'tester',
      });
    },
  );
  test(
    'wired condition overrides literal and switch uses stable case ID',
    () async {
      final result = await parity(
        document(
          [
            GraphNode(
              id: 'v',
              type: 'showrunner.variable',
              data: {'name': 'flag', 'dataType': 'core.boolean', 'value': true},
            ),
            GraphNode(
              id: 'if',
              type: 'showrunner.if',
              data: {'condition': false},
            ),
            GraphNode(
              id: 'switch',
              type: 'showrunner.switch',
              data: {
                'expression': 'chosen',
                'cases': [
                  {'id': 'stable', 'value': 'chosen'},
                ],
              },
            ),
            action('a', value: 'matched'),
            action('wrong'),
          ],
          [
            wire('v', 'value.out', 'if', 'config:condition'),
            flow('if', 'switch', port: 'flow:then'),
            flow('if', 'wrong', port: 'flow:else'),
            flow('switch', 'a', port: 'case:stable'),
            flow('switch', 'wrong', port: 'flow:default'),
          ],
          entry: 'if',
        ),
      );
      expect(result.nodeResults['a'], {'value': 'matched'});
      expect(result.nodeResults, isNot(contains('wrong')));
    },
  );
  for (final kind in ['for', 'forEach']) {
    test(
      '$kind publishes loop values without index variable configuration',
      () async {
        final seen = <List<Object?>>[];
        await parity(
          document(
            [
              GraphNode(
                id: 'loop',
                type: 'showrunner.$kind',
                data: kind == 'for'
                    ? {'start': 0, 'end': 3, 'step': 1, 'variable': 'counter'}
                    : {
                        'collection': ['a', 'b', 'c'],
                        'variable': 'item',
                      },
              ),
              action('a'),
              GraphNode(id: 'done', type: 'showrunner.return'),
            ],
            [
              flow('loop', 'a', port: 'flow:body'),
              flow('a', 'loop'),
              flow('loop', 'done', port: 'flow:next'),
              wire('loop', 'loop:index', 'a', 'config:value'),
            ],
            entry: 'loop',
          ),
          runs: seen,
        );
        expect(seen, [
          [0, 1, 2],
          [0, 1, 2],
        ]);
      },
    );
  }
  test(
    'stable parameter and return ports survive declaration rename',
    () async {
      for (final name in ['original', 'renamed']) {
        final signature = AutomationSubgraph(
          id: 'sub',
          name: 'Sub',
          entryNodeId: 'return',
          parameters: [
            AutomationParameter(id: 'p', name: name, defaultValue: 42),
          ],
          outputs: [AutomationParameter(id: 'o', name: 'answer')],
        );
        final result = await parity(
          document(
            [
              GraphNode(
                id: 'call',
                type: 'showrunner.subgraphCall',
                data: {'subgraphId': 'sub'},
              ),
              action('a'),
            ],
            [flow('call', 'a'), wire('call', 'output:o', 'a', 'config:value')],
            entry: 'call',
            subgraphs: {'sub': signature},
            spaces: {
              signature.spaceId: GraphSpace(
                id: signature.spaceId,
                nodes: {
                  'parameter': GraphNode(
                    id: 'parameter',
                    type: 'showrunner.parameter',
                    data: {'parameterId': 'p'},
                  ),
                  'return': GraphNode(id: 'return', type: 'showrunner.return'),
                },
                connections: {
                  'parameter/value.out/return/output:o': wire(
                    'parameter',
                    'value.out',
                    'return',
                    'output:o',
                  ),
                },
              ),
            },
          ),
        );
        expect(result.nodeResults['a'], {'value': 42});
        expect(result.nodeResults.keys, isNot(contains('parameter')));
      }
    },
  );
  test(
    'descending loops and implicit body continuation execute identically',
    () async {
      final seen = <List<Object?>>[];
      await parity(
        document(
          [
            GraphNode(
              id: 'loop',
              type: 'showrunner.for',
              data: {'start': 3, 'end': 0, 'step': -1},
            ),
            action('a'),
          ],
          [
            flow('loop', 'a', port: 'flow:body'),
            wire('loop', 'loop:index', 'a', 'config:value'),
          ],
          entry: 'loop',
        ),
        runs: seen,
      );
      expect(seen, [
        [3, 2, 1],
        [3, 2, 1],
      ]);
    },
  );
  for (final control in ['break', 'continue']) {
    test(
      '$control targets its enclosing loop without explicit return edges',
      () async {
        final seen = <List<Object?>>[];
        await parity(
          document(
            [
              GraphNode(
                id: 'loop',
                type: 'showrunner.for',
                data: {'start': 0, 'end': 3, 'step': 1},
              ),
              action('a'),
              GraphNode(id: 'control', type: 'showrunner.$control'),
              action('unreachable'),
              action('done', value: 'done'),
            ],
            [
              flow('loop', 'a', port: 'flow:body'),
              flow('a', 'control'),
              flow('loop', 'done', port: 'flow:next'),
              wire('loop', 'loop:index', 'a', 'config:value'),
            ],
            entry: 'loop',
          ),
          runs: seen,
        );
        final expected = control == 'break' ? [0, 'done'] : [0, 1, 2, 'done'];
        expect(seen, [expected, expected]);
      },
    );
  }
  test(
    'recursive subgraphs restore caller node values and parameter locals',
    () async {
      final signature = AutomationSubgraph(
        id: 'recursive',
        name: 'Recursive',
        entryNodeId: 'condition',
        parameters: [AutomationParameter(id: 'p', name: 'n')],
        outputs: [AutomationParameter(id: 'o', name: 'answer')],
      );
      final nodes = [
        GraphNode(
          id: 'condition',
          type: 'showrunner.if',
          data: {
            'condition': {
              'type': 'binary',
              'op': '>',
              'left': {'type': 'variable', 'name': 'n'},
              'right': {'type': 'literal', 'value': 0},
            },
          },
        ),
        action('before', value: '{{n}}'),
        GraphNode(
          id: 'recursive-call',
          type: 'showrunner.subgraphCall',
          data: {
            'subgraphId': 'recursive',
            'arguments': {
              'p': {
                'type': 'binary',
                'op': '-',
                'left': {'type': 'variable', 'name': 'n'},
                'right': {'type': 'literal', 'value': 1},
              },
            },
          },
        ),
        GraphNode(id: 'return', type: 'showrunner.return'),
        GraphNode(
          id: 'base',
          type: 'showrunner.return',
          data: {
            'outputs': {'o': -1},
          },
        ),
      ];
      final connections = [
        flow('condition', 'before', port: 'flow:then'),
        flow('condition', 'base', port: 'flow:else'),
        flow('before', 'recursive-call'),
        flow('recursive-call', 'return'),
        wire('before', 'result:value', 'return', 'output:o'),
      ];
      final result = await parity(
        document(
          [
            GraphNode(
              id: 'call',
              type: 'showrunner.subgraphCall',
              data: {
                'subgraphId': 'recursive',
                'arguments': {'p': 3},
              },
            ),
            action('a'),
          ],
          [flow('call', 'a'), wire('call', 'output:o', 'a', 'config:value')],
          entry: 'call',
          subgraphs: {'recursive': signature},
          spaces: {
            signature.spaceId: GraphSpace(
              id: signature.spaceId,
              nodes: {for (final node in nodes) node.id: node},
              connections: {for (final edge in connections) edge.id: edge},
            ),
          },
        ),
      );
      expect(result.nodeResults['a'], {'value': 3});
      expect(result.nodeResults.keys, unorderedEquals(['call', 'a']));
    },
  );
  for (final engine in <GraphExecutionEngine>[
    const InterpreterExecutionEngine(),
    CompiledExecutionEngine(),
  ]) {
    test(
      '${engine.runtimeType} rejects invalid entries, zero steps and unbounded while loops',
      () async {
        final registry = DartPluginRegistry();
        addTearDown(registry.close);
        for (final doc in [
          document(
            [
              GraphNode(
                id: 'loop',
                type: 'showrunner.for',
                data: {'start': 0, 'end': 3, 'step': 0},
              ),
            ],
            [],
            entry: 'loop',
          ),
          document(
            [
              GraphNode(
                id: 'loop',
                type: 'showrunner.while',
                data: {'condition': true, 'maxIterations': 2},
              ),
            ],
            [],
            entry: 'loop',
          ),
          document(
            [GraphNode(id: 'break', type: 'showrunner.break')],
            [],
            entry: 'break',
          ),
          document([], [], entry: 'missing'),
        ]) {
          await expectLater(
            engine.executeWithRegistry(
              automation: doc,
              context: EvaluationContext(),
              registry: registry,
            ),
            throwsStateError,
          );
        }
        final token = DartCancellationToken()..cancel();
        await expectLater(
          engine.executeWithRegistry(
            automation: document([], [], entry: ''),
            context: EvaluationContext(cancellationToken: token),
            registry: registry,
          ),
          throwsA(isA<DartCancelledException>()),
        );
      },
    );
  }
  test(
    'parameter and output defaults are literal JSON, including type properties and null',
    () async {
      final value = {'type': 'event', 'text': 'literal'};
      for (final explicit in [false, true]) {
        final signature = AutomationSubgraph(
          id: 'defaults',
          name: 'Defaults',
          entryNodeId: explicit ? 'return' : 'noop',
          parameters: [
            AutomationParameter(
              id: 'p',
              name: 'parameter',
              defaultValue: value,
            ),
          ],
          outputs: [
            AutomationParameter(id: 'o', name: 'answer', defaultValue: value),
            AutomationParameter(id: 'null', name: 'nullable'),
          ],
        );
        final result = await parity(
          document(
            [
              GraphNode(
                id: 'call',
                type: 'showrunner.subgraphCall',
                data: {'subgraphId': signature.id},
              ),
              action('a'),
            ],
            [flow('call', 'a'), wire('call', 'output:o', 'a', 'config:value')],
            entry: 'call',
            subgraphs: {signature.id: signature},
            spaces: {
              signature.spaceId: GraphSpace(
                id: signature.spaceId,
                nodes: {
                  if (explicit)
                    'return': GraphNode(id: 'return', type: 'showrunner.return')
                  else
                    'noop': action('noop', value: 'done'),
                },
              ),
            },
          ),
        );
        expect(result.nodeResults['call'], {'answer': value, 'nullable': null});
        expect(result.nodeResults['a']!['value'], value);
      }
    },
  );
  for (final engine in <GraphExecutionEngine>[
    const InterpreterExecutionEngine(),
    CompiledExecutionEngine(),
  ]) {
    test(
      '${engine.runtimeType} refuses type-incompatible or unknown connection ports',
      () async {
        final registry = DartPluginRegistry();
        addTearDown(registry.close);
        for (final output in ['value.out', 'missing']) {
          await expectLater(
            engine.executeWithRegistry(
              automation: document(
                [
                  GraphNode(
                    id: 'number',
                    type: 'showrunner.variable',
                    data: {'name': 'n', 'dataType': 'core.number', 'value': 4},
                  ),
                  GraphNode(
                    id: 'condition',
                    type: 'showrunner.if',
                    data: {'condition': true},
                  ),
                ],
                [wire('number', output, 'condition', 'config:condition')],
                entry: 'condition',
              ),
              context: EvaluationContext(),
              registry: registry,
            ),
            throwsStateError,
          );
        }
      },
    );
  }
  test('layout changes reuse compilation; semantic changes invalidate it', () {
    final cache = GraphProgramCache();
    final initial = document([action('a')], [], entry: 'a');
    final first = cache.getOrCompile(initial);
    final space = initial.graph.spaces[mainAutomationSpace]!;
    final moved = AutomationDocument.fromGraph(
      initial.graph.copyWith(
        spaces: {
          mainAutomationSpace: space.copyWith(
            nodePresentations: {
              'a': NodePresentation(
                nodeId: 'a',
                position: const GraphPoint(400, 200),
              ),
            },
          ),
        },
      ),
    );
    expect(cache.getOrCompile(moved), same(first));
    cache.getOrCompile(
      document([action('a', value: 'changed')], [], entry: 'a'),
    );
    expect(cache.compilationCount, 2);
  });
}

AutomationDocument document(
  List<GraphNode> nodes,
  List<GraphConnection> connections, {
  required String entry,
  Map<String, AutomationSubgraph> subgraphs = const {},
  Map<String, GraphSpace> spaces = const {},
}) => AutomationDocument(
  graph: GraphDocument(
    id: 'test',
    spaces: {
      mainAutomationSpace: GraphSpace(
        id: mainAutomationSpace,
        nodes: {for (final node in nodes) node.id: node},
        connections: {for (final wire in connections) wire.id: wire},
      ),
      ...spaces,
    },
  ),
  settings: {'entryNodeId': entry},
  subgraphs: subgraphs,
);

GraphNode action(String id, {Object? value}) => GraphNode(
  id: id,
  type: actionNodeType('fixture', 'record'),
  data: {
    'config': {'value': value},
  },
);
GraphConnection flow(String from, String to, {String port = 'exec.out'}) =>
    GraphConnection(
      id: '$from/$port/$to',
      from: PortRef(nodeId: from, portId: port),
      to: PortRef(nodeId: to, portId: 'exec.in'),
      kind: GraphConnectionKind.control,
    );
GraphConnection wire(String from, String output, String to, String input) =>
    GraphConnection(
      id: '$from/$output/$to/$input',
      from: PortRef(nodeId: from, portId: output),
      to: PortRef(nodeId: to, portId: input),
      kind: GraphConnectionKind.data,
    );

Future<GraphExecutionResult> parity(
  AutomationDocument doc, {
  EvaluationContext Function()? context,
  List<List<Object?>>? runs,
}) async {
  final results = <GraphExecutionResult>[];
  final calls = <List<Object?>>[];
  for (final engine in <GraphExecutionEngine>[
    const InterpreterExecutionEngine(),
    CompiledExecutionEngine(),
  ]) {
    final recorded = <Object?>[];
    calls.add(recorded);
    final registry = DartPluginRegistry()
      ..register(
        DartPluginManifest(
          id: PluginId('fixture'),
          name: 'Fixture',
          triggers: [
            TriggerSpec<Map<String, dynamic>, Map<String, dynamic>>(
              pluginId: PluginId('fixture'),
              triggerId: TriggerId('message'),
              displayName: 'Message',
              listen: () => const Stream.empty(),
              eventSchema: const DartDataInputSchema(
                label: 'Event',
                kind: DartDataInputKind.object,
                fields: [
                  DartDataInputSchema(
                    key: 'text',
                    label: 'Text',
                    kind: DartDataInputKind.text,
                  ),
                ],
              ),
            ),
          ],
          actions: [
            ActionSpec<Map<String, dynamic>, Object?>(
              pluginId: PluginId('fixture'),
              actionId: ActionId('record'),
              configSchema: fixtureSchema,
              resultSchema: fixtureSchema,
              invoke: (config, context) async {
                recorded.add(config['value']);
                return {'value': config['value']};
              },
            ),
          ],
        ),
      );
    try {
      results.add(
        await engine.executeWithRegistry(
          automation: doc,
          context: context?.call() ?? EvaluationContext(),
          registry: registry,
        ),
      );
    } finally {
      await registry.close();
    }
  }
  expect(results.last.completed, results.first.completed);
  expect(results.last.nodeResults, results.first.nodeResults);
  expect(results.last.contextState, results.first.contextState);
  expect(results.last.outputValues, results.first.outputValues);
  expect(calls.last, calls.first);
  runs?.addAll(calls);
  return results.last;
}

const fixtureSchema = DartDataInputSchema(
  label: 'Record',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      key: 'value',
      label: 'Value',
      kind: DartDataInputKind.object,
      graphEditor: DartGraphEditorHints(dataType: 'core.any'),
    ),
  ],
);
