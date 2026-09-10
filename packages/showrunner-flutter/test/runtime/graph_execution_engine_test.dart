import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/runtime/graph_execution_engine.dart';
import 'package:showrunner_flutter/runtime/production_graph_vm.dart';
import 'package:showrunner_flutter/runtime/cancellation.dart';
import 'package:showrunner_flutter/schema/automation.dart';
import 'package:showrunner_flutter/runtime/expression.dart';

void main() {
  test('uses the production sixteen-opcode program shape', () async {
    expect(DartGraphOpCode.values, hasLength(16));

    final cache = GraphProgramCache();
    final automation = _singleActionAutomation('first');
    final first = cache.getOrCompile(automation);
    final second = cache.getOrCompile(automation);

    expect(identical(first, second), isTrue);
    expect(cache.compilationCount, 1);
    expect(first.instructions.last.op, DartGraphOpCode.halt);

    final changed = _singleActionAutomation('changed');
    cache.getOrCompile(changed);
    expect(cache.compilationCount, 2);
  });

  test(
    'keeps interpreter and compiled engines equivalent for branches',
    () async {
      await _expectParity(
        AutomationData(
          graph: AutomationGraph(
            entryNodeId: 'condition',
            nodes: [
              GraphNode(
                id: 'condition',
                type: 'if',
                x: 0,
                y: 0,
                data: {
                  'condition': const {'type': 'literal', 'value': true},
                },
              ),
              _action('then', value: 'then'),
              _action('else', value: 'else'),
              const GraphNode(id: 'done', type: 'return', x: 0, y: 0),
            ],
            edges: const [
              GraphEdge(
                id: 'then',
                from: 'condition',
                to: 'then',
                port: 'then',
              ),
              GraphEdge(
                id: 'else',
                from: 'condition',
                to: 'else',
                port: 'else',
              ),
              GraphEdge(id: 'then-done', from: 'then', to: 'done'),
              GraphEdge(id: 'else-done', from: 'else', to: 'done'),
            ],
          ),
        ),
      );

      await _expectParity(
        AutomationData(
          graph: AutomationGraph(
            entryNodeId: 'switch',
            nodes: [
              GraphNode(
                id: 'switch',
                type: 'switch',
                x: 0,
                y: 0,
                data: {
                  'expression': const {'type': 'variable', 'name': 'selected'},
                  'cases': const [
                    {'value': 'b', 'port': 'case:b'},
                  ],
                },
              ),
              _action('case', value: 'matched'),
              _action('default', value: 'default'),
              const GraphNode(id: 'done', type: 'return', x: 0, y: 0),
            ],
            edges: const [
              GraphEdge(id: 'case', from: 'switch', to: 'case', port: 'case:b'),
              GraphEdge(
                id: 'default',
                from: 'switch',
                to: 'default',
                port: 'default',
              ),
              GraphEdge(id: 'case-done', from: 'case', to: 'done'),
              GraphEdge(id: 'default-done', from: 'default', to: 'done'),
            ],
          ),
        ),
        context: () => EvaluationContext(locals: {'selected': 'b'}),
      );
    },
  );

  test('keeps loop execution and data wires equivalent', () async {
    await _expectParity(ReferenceExecutionFixtures.forLoop());
    await _expectParity(
      ReferenceExecutionFixtures.whileLoop(),
      context: () => EvaluationContext(locals: {'count': 0}),
    );
    await _expectParity(ReferenceExecutionFixtures.breakLoop());
    await _expectParity(ReferenceExecutionFixtures.continueLoop());

    await _expectParity(
      AutomationData(
        graph: AutomationGraph(
          entryNodeId: 'each',
          nodes: [
            GraphNode(
              id: 'each',
              type: 'forEach',
              x: 0,
              y: 0,
              data: {
                'variable': 'item',
                'collection': const {
                  'type': 'literal',
                  'value': ['a', 'b', 'c'],
                },
              },
            ),
            GraphNode(
              id: 'record',
              type: 'action',
              x: 100,
              y: 0,
              data: {
                'plugin': 'fixture',
                'action': 'record',
                'config': const {
                  'value': {'type': 'variable', 'name': 'item'},
                },
              },
            ),
            const GraphNode(id: 'done', type: 'return', x: 0, y: 0),
          ],
          edges: const [
            GraphEdge(id: 'body', from: 'each', to: 'record', port: 'body'),
            GraphEdge(id: 'repeat', from: 'record', to: 'each'),
            GraphEdge(id: 'next', from: 'each', to: 'done', port: 'next'),
          ],
        ),
      ),
    );

    await _expectParity(
      AutomationData(
        graph: AutomationGraph(
          entryNodeId: 'producer',
          nodes: [
            _action('producer', value: 42),
            GraphNode(
              id: 'consumer',
              type: 'action',
              x: 100,
              y: 0,
              data: {
                'plugin': 'fixture',
                'action': 'record',
                'config': const {'value': 0},
              },
            ),
            const GraphNode(id: 'done', type: 'return', x: 0, y: 0),
          ],
          edges: const [
            GraphEdge(id: 'consumer', from: 'producer', to: 'consumer'),
            GraphEdge(id: 'done', from: 'consumer', to: 'done'),
          ],
        ),
        dataWires: const [
          DataWire(
            id: 'value',
            fromNode: 'producer',
            fromPort: 'value',
            toNode: 'consumer',
            toPort: 'value',
          ),
        ],
      ),
    );

    await _expectParity(
      AutomationData(
        graph: AutomationGraph(
          entryNodeId: 'consumer',
          nodes: [
            GraphNode(
              id: 'consumer',
              type: 'action',
              x: 0,
              y: 0,
              data: {
                'plugin': 'fixture',
                'action': 'record',
                'config': const {'value': 0},
                'resultMapping': const {'value': 'mappedValue'},
              },
            ),
            const GraphNode(id: 'done', type: 'return', x: 0, y: 0),
          ],
          edges: const [GraphEdge(id: 'done', from: 'consumer', to: 'done')],
        ),
        dataWires: const [
          DataWire(
            id: 'trigger-value',
            fromNode: 'trigger',
            fromPort: 'payload.value',
            toNode: 'consumer',
            toPort: 'value',
          ),
        ],
      ),
      context: () => EvaluationContext(
        contextState: const {
          'payload': {'value': 'from-trigger'},
        },
      ),
    );
  });

  test('keeps nested subgraphs and outputs equivalent', () async {
    final compiledTrace = <String>[];
    final automation = AutomationData(
      graph: AutomationGraph(
        entryNodeId: 'call',
        nodes: [
          GraphNode(
            id: 'call',
            type: 'subgraphCall',
            x: 0,
            y: 0,
            data: {
              'subgraphId': 'outer',
              'inputs': const {
                'message': {'type': 'literal', 'value': 'hello'},
              },
            },
          ),
          GraphNode(
            id: 'done',
            type: 'return',
            x: 100,
            y: 0,
            data: {
              'outputs': const {
                'result': {'type': 'port', 'nodeId': 'call', 'port': 'result'},
              },
            },
          ),
        ],
        edges: const [GraphEdge(id: 'done', from: 'call', to: 'done')],
      ),
      subgraphs: [
        SubgraphDefinition(
          id: 'outer',
          name: 'Outer',
          entryNodeId: 'innerCall',
          parameters: const [
            {'name': 'message'},
          ],
          nodes: [
            GraphNode(
              id: 'innerCall',
              type: 'subgraphCall',
              x: 0,
              y: 0,
              data: {
                'subgraphId': 'inner',
                'inputs': const {
                  'message': {'type': 'variable', 'name': 'message'},
                },
              },
            ),
            GraphNode(
              id: 'outerReturn',
              type: 'return',
              x: 100,
              y: 0,
              data: {
                'outputs': const {
                  'result': {
                    'type': 'port',
                    'nodeId': 'innerCall',
                    'port': 'result',
                  },
                },
              },
            ),
          ],
          edges: const [
            GraphEdge(id: 'outer-done', from: 'innerCall', to: 'outerReturn'),
          ],
        ),
        SubgraphDefinition(
          id: 'inner',
          name: 'Inner',
          entryNodeId: 'record',
          parameters: const [
            {'name': 'message'},
          ],
          outputs: const [
            {
              'name': 'result',
              'expression': {
                'type': 'port',
                'nodeId': 'record',
                'port': 'value',
              },
            },
          ],
          nodes: [
            GraphNode(
              id: 'record',
              type: 'action',
              x: 0,
              y: 0,
              data: {
                'plugin': 'fixture',
                'action': 'record',
                'config': const {'value': '{{message}}'},
              },
            ),
          ],
          edges: const [],
        ),
      ],
    );
    final compiled = await CompiledExecutionEngine().executeWithRegistry(
      automation: automation,
      context: EvaluationContext(),
      registry: _registry(compiledTrace),
    );
    expect(compiled.outputValues, {'result': 'hello'});
    expect(compiledTrace, ['record:hello']);

    await _expectParity(automation);
  });

  test(
    'propagates cancellation through actions, loops, and subgraphs',
    () async {
      final token = DartCancellationToken(id: 'parity-cancel');
      final automation = AutomationData(
        graph: AutomationGraph(
          entryNodeId: 'loop',
          nodes: [
            GraphNode(
              id: 'loop',
              type: 'while',
              x: 0,
              y: 0,
              data: const {
                'condition': {'type': 'literal', 'value': true},
              },
            ),
            GraphNode(
              id: 'cancel',
              type: 'action',
              x: 100,
              y: 0,
              data: {
                'plugin': 'fixture',
                'action': 'cancel',
                'config': const {},
              },
            ),
          ],
          edges: const [
            GraphEdge(id: 'body', from: 'loop', to: 'cancel', port: 'body'),
            GraphEdge(id: 'repeat', from: 'cancel', to: 'loop'),
          ],
        ),
      );
      final registry = _registry(<String>[], cancelToken: token);
      await expectLater(
        const InterpreterExecutionEngine().executeWithRegistry(
          automation: automation,
          context: EvaluationContext(cancellationToken: token),
          registry: registry,
        ),
        throwsA(isA<DartCancelledException>()),
      );

      final compiledToken = DartCancellationToken(id: 'compiled-cancel');
      await expectLater(
        CompiledExecutionEngine().executeWithRegistry(
          automation: automation,
          context: EvaluationContext(cancellationToken: compiledToken),
          registry: _registry(<String>[], cancelToken: compiledToken),
        ),
        throwsA(isA<DartCancelledException>()),
      );

      final subgraphAutomation = AutomationData(
        graph: AutomationGraph(
          entryNodeId: 'call',
          nodes: [
            GraphNode(
              id: 'call',
              type: 'subgraphCall',
              x: 0,
              y: 0,
              data: const {'subgraphId': 'cancel-subgraph'},
            ),
          ],
        ),
        subgraphs: [
          SubgraphDefinition(
            id: 'cancel-subgraph',
            name: 'Cancel subgraph',
            entryNodeId: 'cancel',
            nodes: [
              GraphNode(
                id: 'cancel',
                type: 'action',
                x: 0,
                y: 0,
                data: const {
                  'plugin': 'fixture',
                  'action': 'cancel',
                  'config': {},
                },
              ),
            ],
            edges: const [],
          ),
        ],
      );
      final interpreterSubgraphToken = DartCancellationToken(
        id: 'interpreter-subgraph-cancel',
      );
      await expectLater(
        const InterpreterExecutionEngine().executeWithRegistry(
          automation: subgraphAutomation,
          context: EvaluationContext(
            cancellationToken: interpreterSubgraphToken,
          ),
          registry: _registry(
            <String>[],
            cancelToken: interpreterSubgraphToken,
          ),
        ),
        throwsA(isA<DartCancelledException>()),
      );
      final compiledSubgraphToken = DartCancellationToken(
        id: 'compiled-subgraph-cancel',
      );
      await expectLater(
        CompiledExecutionEngine().executeWithRegistry(
          automation: subgraphAutomation,
          context: EvaluationContext(cancellationToken: compiledSubgraphToken),
          registry: _registry(<String>[], cancelToken: compiledSubgraphToken),
        ),
        throwsA(isA<DartCancelledException>()),
      );
    },
  );

  test('enforces compiled loop and call-depth guards', () async {
    final infinite = AutomationData(
      graph: AutomationGraph(
        entryNodeId: 'loop',
        nodes: [
          GraphNode(
            id: 'loop',
            type: 'while',
            x: 0,
            y: 0,
            data: const {
              'condition': {'type': 'literal', 'value': true},
            },
          ),
        ],
        edges: const [],
      ),
    );
    await expectLater(
      CompiledExecutionEngine(maxIterations: 3).executeWithRegistry(
        automation: infinite,
        context: EvaluationContext(),
        registry: _registry(<String>[]),
      ),
      throwsA(isA<StateError>()),
    );

    final recursive = AutomationData(
      graph: AutomationGraph(
        entryNodeId: 'call',
        nodes: [
          GraphNode(
            id: 'call',
            type: 'subgraphCall',
            x: 0,
            y: 0,
            data: const {'subgraphId': 'recursive'},
          ),
        ],
        edges: const [],
      ),
      subgraphs: [
        SubgraphDefinition(
          id: 'recursive',
          name: 'Recursive',
          entryNodeId: 'call',
          nodes: [
            GraphNode(
              id: 'call',
              type: 'subgraphCall',
              x: 0,
              y: 0,
              data: const {'subgraphId': 'recursive'},
            ),
          ],
          edges: const [],
        ),
      ],
    );
    await expectLater(
      CompiledExecutionEngine(maxCallDepth: 2).executeWithRegistry(
        automation: recursive,
        context: EvaluationContext(),
        registry: _registry(<String>[]),
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('surfaces action failures identically in both engines', () async {
    final automation = _singleActionAutomation('failure', action: 'fail');
    await expectLater(
      const InterpreterExecutionEngine().executeWithRegistry(
        automation: automation,
        context: EvaluationContext(),
        registry: _registry(<String>[]),
      ),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      CompiledExecutionEngine().executeWithRegistry(
        automation: automation,
        context: EvaluationContext(),
        registry: _registry(<String>[]),
      ),
      throwsA(isA<StateError>()),
    );
  });
}

Future<void> _expectParity(
  AutomationData automation, {
  EvaluationContext Function()? context,
}) async {
  final interpreterTrace = <String>[];
  final compiledTrace = <String>[];
  final interpreter = await const InterpreterExecutionEngine()
      .executeWithRegistry(
        automation: automation,
        context: context?.call() ?? EvaluationContext(),
        registry: _registry(interpreterTrace),
      );
  final compiled = await CompiledExecutionEngine().executeWithRegistry(
    automation: automation,
    context: context?.call() ?? EvaluationContext(),
    registry: _registry(compiledTrace),
  );
  expect(compiled.completed, interpreter.completed);
  expect(compiled.nodeResults, interpreter.nodeResults);
  expect(compiled.contextState, interpreter.contextState);
  expect(compiled.outputValues, interpreter.outputValues);
  expect(compiledTrace, interpreterTrace);
}

DartPluginRegistry _registry(
  List<String> trace, {
  DartCancellationToken? cancelToken,
}) {
  final registry = DartPluginRegistry();
  registry.register(
    DartPluginManifest(
      id: 'fixture',
      name: 'Fixture',
      actions: [
        DartActionDefinition(
          pluginId: 'fixture',
          actionId: 'record',
          invoke: (config, context) async {
            final value = config['value'];
            trace.add('record:$value');
            return {'value': value};
          },
        ),
        DartActionDefinition(
          pluginId: 'fixture',
          actionId: 'cancel',
          invoke: (config, context) async {
            trace.add('cancel');
            (cancelToken ?? context.cancellationToken)?.cancel();
            return const {};
          },
        ),
        DartActionDefinition(
          pluginId: 'fixture',
          actionId: 'increment',
          invoke: (config, context) async {
            trace.add('increment');
            context.locals['count'] =
                (context.locals['count'] as num? ?? 0) + 1;
            return {'value': context.locals['count']};
          },
        ),
        DartActionDefinition(
          pluginId: 'fixture',
          actionId: 'fail',
          invoke: (config, context) async {
            throw StateError('fixture action failed');
          },
        ),
      ],
    ),
  );
  return registry;
}

AutomationData _singleActionAutomation(
  String value, {
  String action = 'record',
}) => AutomationData(
  graph: AutomationGraph(
    entryNodeId: 'action',
    nodes: [
      GraphNode(
        id: 'action',
        type: 'action',
        x: 0,
        y: 0,
        data: {
          'plugin': 'fixture',
          'action': action,
          'config': {'value': value},
        },
      ),
    ],
  ),
);

final class ReferenceExecutionFixtures {
  static AutomationData forLoop() => AutomationData(
    graph: AutomationGraph(
      entryNodeId: 'for',
      nodes: [
        GraphNode(
          id: 'for',
          type: 'for',
          x: 0,
          y: 0,
          data: const {
            'variable': 'index',
            'start': {'type': 'literal', 'value': 0},
            'end': {'type': 'literal', 'value': 3},
            'step': {'type': 'literal', 'value': 1},
          },
        ),
        _action('body', valueExpression: 'index'),
        const GraphNode(id: 'done', type: 'return', x: 0, y: 0),
      ],
      edges: const [
        GraphEdge(id: 'body', from: 'for', to: 'body', port: 'body'),
        GraphEdge(id: 'repeat', from: 'body', to: 'for'),
        GraphEdge(id: 'next', from: 'for', to: 'done', port: 'next'),
      ],
    ),
  );

  static AutomationData whileLoop() => AutomationData(
    graph: AutomationGraph(
      entryNodeId: 'while',
      nodes: [
        GraphNode(
          id: 'while',
          type: 'while',
          x: 0,
          y: 0,
          data: const {
            'condition': {
              'type': 'binary',
              'op': '<',
              'left': {'type': 'variable', 'name': 'count'},
              'right': {'type': 'literal', 'value': 3},
            },
          },
        ),
        _action('increment', action: 'increment', value: 1),
        const GraphNode(id: 'done', type: 'return', x: 0, y: 0),
      ],
      edges: const [
        GraphEdge(id: 'body', from: 'while', to: 'increment', port: 'body'),
        GraphEdge(id: 'repeat', from: 'increment', to: 'while'),
        GraphEdge(id: 'next', from: 'while', to: 'done', port: 'next'),
      ],
    ),
  );

  static AutomationData breakLoop() => AutomationData(
    graph: AutomationGraph(
      entryNodeId: 'for',
      nodes: [
        GraphNode(
          id: 'for',
          type: 'for',
          x: 0,
          y: 0,
          data: const {
            'variable': 'index',
            'start': {'type': 'literal', 'value': 0},
            'end': {'type': 'literal', 'value': 3},
            'step': {'type': 'literal', 'value': 1},
          },
        ),
        const GraphNode(id: 'break', type: 'break', x: 0, y: 0),
        const GraphNode(id: 'done', type: 'return', x: 0, y: 0),
      ],
      edges: const [
        GraphEdge(id: 'body', from: 'for', to: 'break', port: 'body'),
        GraphEdge(id: 'exit', from: 'break', to: 'done', port: 'next'),
        GraphEdge(id: 'next', from: 'for', to: 'done', port: 'next'),
      ],
    ),
  );

  static AutomationData continueLoop() => AutomationData(
    graph: AutomationGraph(
      entryNodeId: 'for',
      nodes: [
        GraphNode(
          id: 'for',
          type: 'for',
          x: 0,
          y: 0,
          data: const {
            'variable': 'index',
            'start': {'type': 'literal', 'value': 0},
            'end': {'type': 'literal', 'value': 3},
            'step': {'type': 'literal', 'value': 1},
          },
        ),
        const GraphNode(id: 'continue', type: 'continue', x: 0, y: 0),
        const GraphNode(id: 'done', type: 'return', x: 0, y: 0),
      ],
      edges: const [
        GraphEdge(id: 'body', from: 'for', to: 'continue', port: 'body'),
        GraphEdge(id: 'repeat', from: 'continue', to: 'for', port: 'continue'),
        GraphEdge(id: 'next', from: 'for', to: 'done', port: 'next'),
      ],
    ),
  );
}

GraphNode _action(
  String id, {
  String action = 'record',
  Object? value,
  String? valueExpression,
}) => GraphNode(
  id: id,
  type: 'action',
  x: 0,
  y: 0,
  data: {
    'plugin': 'fixture',
    'action': action,
    'config': {
      'value': valueExpression == null
          ? value
          : {'type': 'variable', 'name': valueExpression},
    },
  },
);
