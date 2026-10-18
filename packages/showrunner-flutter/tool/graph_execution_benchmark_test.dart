import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/graph/runtime/graph_execution_engine.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/runtime/expression.dart';
import '../test/support/graph_fixtures.dart';

void main() {
  test(
    'records compiler cache and VM timings for canonical documents',
    () async {
      final registry = DartPluginRegistry()
        ..register(
          DartPluginManifest(
            id: PluginId('test'),
            name: 'Benchmark',
            actions: [
              ActionSpec<Map<String, dynamic>, Object?>(
                pluginId: PluginId('test'),
                actionId: ActionId('record'),
                invoke: (config, context) async => {'done': true},
              ),
            ],
          ),
        );
      addTearDown(registry.close);
      final measurements = <Map<String, Object>>[];
      for (final count in [100, 500, 1000]) {
        measurements.add(
          await measure(
            'linear',
            automationFixture(
              nodes: [
                for (var i = 0; i < count; i++) actionFixture('action-$i'),
              ],
              connections: [
                for (var i = 0; i < count - 1; i++)
                  controlFixture('edge-$i', 'action-$i', 'action-${i + 1}'),
              ],
              entryNodeId: 'action-0',
            ),
            registry,
            {'nodes': count},
          ),
        );
      }
      measurements.add(
        await measure(
          'loop',
          automationFixture(
            nodes: [
              GraphNode(
                id: 'loop',
                type: 'showrunner.for',
                data: {'start': 0, 'end': 100, 'step': 1},
              ),
              actionFixture('body'),
            ],
            connections: [
              controlFixture('body-flow', 'loop', 'body', port: 'flow:body'),
            ],
            entryNodeId: 'loop',
          ),
          registry,
          {'iterations': 100},
        ),
      );
      final signatures = [
        for (var i = 0; i < 8; i++)
          AutomationSubgraph(
            id: 'sub-$i',
            name: 'Sub $i',
            entryNodeId: 'body-$i',
          ),
      ];
      measurements.add(
        await measure(
          'subgraph-heavy',
          automationFixture(
            nodes: [
              for (final signature in signatures)
                GraphNode(
                  id: 'call-${signature.id}',
                  type: 'showrunner.subgraphCall',
                  data: {'subgraphId': signature.id},
                ),
            ],
            connections: [
              for (var i = 0; i < signatures.length - 1; i++)
                controlFixture(
                  'call-flow-$i',
                  'call-sub-$i',
                  'call-sub-${i + 1}',
                ),
            ],
            entryNodeId: 'call-sub-0',
            subgraphs: {
              for (final signature in signatures) signature.id: signature,
            },
            spaces: {
              for (var i = 0; i < signatures.length; i++)
                signatures[i].spaceId: GraphSpace(
                  id: signatures[i].spaceId,
                  nodes: {'body-$i': actionFixture('body-$i')},
                ),
            },
          ),
          registry,
          {'subgraphs': signatures.length},
        ),
      );
      final file = File('.tmp/benchmarks/runtime.json');
      await file.parent.create(recursive: true);
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(measurements),
      );
      // ignore: avoid_print
      print('SHOWRUNNER_GRAPH_EXECUTION_BENCHMARK ${jsonEncode(measurements)}');
    },
  );
}

Future<Map<String, Object>> measure(
  String name,
  AutomationDocument document,
  DartPluginRegistry registry,
  Map<String, int> size,
) async {
  final cache = GraphProgramCache();
  final compile = Stopwatch()..start();
  final program = cache.getOrCompile(document);
  compile.stop();
  final lookup = Stopwatch()..start();
  expect(cache.getOrCompile(document), same(program));
  lookup.stop();
  final execution = Stopwatch()..start();
  final result = await CompiledExecutionEngine(cache: cache)
      .executeWithRegistry(
        automation: document,
        context: EvaluationContext(),
        registry: registry,
      );
  execution.stop();
  expect(result.completed, true);
  expect(cache.compilationCount, 1);
  return {
    'scenario': name,
    ...size,
    'compileUs': compile.elapsedMicroseconds,
    'cachedLookupUs': lookup.elapsedMicroseconds,
    'executionUs': execution.elapsedMicroseconds,
    'compiledPrograms': cache.compilationCount,
    'completed': result.completed,
  };
}
