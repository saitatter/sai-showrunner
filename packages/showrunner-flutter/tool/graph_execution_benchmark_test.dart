import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/runtime/expression.dart';
import 'package:showrunner_flutter/runtime/graph_execution_engine.dart';
import 'package:showrunner_flutter/schema/automation.dart';

void main() {
  test('records graph compiler cache and VM timings', () async {
    final measurements = <Map<String, Object>>[];
    for (final count in const [100, 500, 1000]) {
      measurements.add(await _benchmarkLinear(count));
    }
    measurements.add(await _benchmarkLoop(100));
    measurements.add(await _benchmarkSubgraphs(8));

    for (final measurement in measurements) {
      expect(measurement['compileUs'], greaterThanOrEqualTo(0));
      expect(measurement['cachedLookupUs'], greaterThanOrEqualTo(0));
      expect(measurement['executionUs'], greaterThanOrEqualTo(0));
      expect(measurement['completed'], isTrue);
    }

    // ignore: avoid_print
    print('SHOWRUNNER_GRAPH_EXECUTION_BENCHMARK ${jsonEncode(measurements)}');
  });
}

Future<Map<String, Object>> _benchmarkLinear(int count) async {
  final automation = AutomationData(graph: _linearGraph(count));
  final cache = GraphProgramCache();
  final compileTimer = Stopwatch()..start();
  cache.getOrCompile(automation);
  compileTimer.stop();
  final lookupTimer = Stopwatch()..start();
  cache.getOrCompile(automation);
  lookupTimer.stop();
  final engine = CompiledExecutionEngine(cache: cache);
  final executionTimer = Stopwatch()..start();
  final result = await engine.executeWithRegistry(
    automation: automation,
    context: EvaluationContext(),
    registry: _registry(),
  );
  executionTimer.stop();
  return {
    'scenario': 'linear',
    'nodes': count,
    'compileUs': compileTimer.elapsedMicroseconds,
    'cachedLookupUs': lookupTimer.elapsedMicroseconds,
    'executionUs': executionTimer.elapsedMicroseconds,
    'compiledPrograms': cache.compilationCount,
    'completed': result.completed,
  };
}

Future<Map<String, Object>> _benchmarkLoop(int iterations) async {
  final automation = AutomationData(
    graph: AutomationGraph(
      entryNodeId: 'loop',
      nodes: [
        GraphNode(
          id: 'loop',
          type: 'for',
          x: 0,
          y: 0,
          data: {
            'variable': 'index',
            'start': {'type': 'literal', 'value': 0},
            'end': {'type': 'literal', 'value': iterations},
            'step': {'type': 'literal', 'value': 1},
          },
        ),
        _action('body'),
        const GraphNode(id: 'done', type: 'return', x: 0, y: 0),
      ],
      edges: const [
        GraphEdge(id: 'body', from: 'loop', to: 'body', port: 'body'),
        GraphEdge(id: 'repeat', from: 'body', to: 'loop'),
        GraphEdge(id: 'next', from: 'loop', to: 'done', port: 'next'),
      ],
    ),
  );
  final engine = CompiledExecutionEngine();
  final timer = Stopwatch()..start();
  final result = await engine.executeWithRegistry(
    automation: automation,
    context: EvaluationContext(),
    registry: _registry(),
  );
  timer.stop();
  return {
    'scenario': 'long-loop',
    'iterations': iterations,
    'compileUs': 0,
    'cachedLookupUs': 0,
    'executionUs': timer.elapsedMicroseconds,
    'completed': result.completed,
  };
}

Future<Map<String, Object>> _benchmarkSubgraphs(int count) async {
  final subgraphs = <SubgraphDefinition>[];
  for (var index = 0; index < count; index++) {
    final nodes = index + 1 < count
        ? [
            GraphNode(
              id: 'call-$index',
              type: 'subgraphCall',
              x: 0,
              y: 0,
              data: {'subgraphId': 'sg-${index + 1}'},
            ),
          ]
        : [_action('final')];
    subgraphs.add(
      SubgraphDefinition(
        id: 'sg-$index',
        name: 'Subgraph $index',
        entryNodeId: nodes.single.id,
        nodes: nodes,
        edges: const [],
      ),
    );
  }
  final automation = AutomationData(
    graph: AutomationGraph(
      entryNodeId: 'call',
      nodes: [
        GraphNode(
          id: 'call',
          type: 'subgraphCall',
          x: 0,
          y: 0,
          data: const {'subgraphId': 'sg-0'},
        ),
      ],
    ),
    subgraphs: subgraphs,
  );
  final engine = CompiledExecutionEngine();
  final timer = Stopwatch()..start();
  final result = await engine.executeWithRegistry(
    automation: automation,
    context: EvaluationContext(),
    registry: _registry(),
  );
  timer.stop();
  return {
    'scenario': 'subgraph-heavy',
    'subgraphs': count,
    'compileUs': 0,
    'cachedLookupUs': 0,
    'executionUs': timer.elapsedMicroseconds,
    'completed': result.completed,
  };
}

AutomationGraph _linearGraph(int count) {
  final nodes = [
    for (var index = 0; index < count; index++) _action('node-$index'),
  ];
  return AutomationGraph(
    entryNodeId: nodes.first.id,
    nodes: nodes,
    edges: [
      for (var index = 1; index < nodes.length; index++)
        GraphEdge(
          id: 'edge-$index',
          from: nodes[index - 1].id,
          to: nodes[index].id,
        ),
    ],
  );
}

GraphNode _action(String id) => GraphNode(
  id: id,
  type: 'action',
  x: 0,
  y: 0,
  data: const {'plugin': 'benchmark', 'action': 'noop', 'config': {}},
);

DartPluginRegistry _registry() {
  final registry = DartPluginRegistry();
  registry.register(
    DartPluginManifest(
      id: 'benchmark',
      name: 'Benchmark',
      actions: [
        DartActionDefinition(
          pluginId: 'benchmark',
          actionId: 'noop',
          invoke: (config, context) async => const {},
        ),
      ],
    ),
  );
  return registry;
}
