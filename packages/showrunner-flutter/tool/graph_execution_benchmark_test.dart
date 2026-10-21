import 'dart:convert';
import 'dart:io';
import 'benchmark_allocations.dart';
import 'package:showrunner_flutter/graph/runtime/graph_program_signature.dart';
import 'package:showrunner_flutter/graph/runtime/graph_vm.dart';
import 'package:showrunner_flutter/runtime/execution_trace.dart';
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
  final program = cache.getOrCompile(document);
  final allocations = await BenchmarkAllocations.connect();
  try {
    final signature = <int>[],
        cold = <int>[],
        hot = <int>[],
        vm = <int>[],
        traced = <int>[];
    var steps = 0;
    const samples = 21;
    // Warm all code paths before recording distributions.
    for (var sample = -3; sample < samples; sample++) {
      final signatureWatch = Stopwatch()..start();
      graphProgramSignature(document);
      signatureWatch.stop();
      final coldWatch = Stopwatch()..start();
      GraphProgramCache().getOrCompile(document);
      coldWatch.stop();
      final hotWatch = Stopwatch()..start();
      final cached = cache.getOrCompile(document);
      hotWatch.stop();
      expect(cached, same(program));
      final vmWatch = Stopwatch()..start();
      final result = await DartGraphVm(program).execute(
        context: EvaluationContext(),
        action: (node, config, context) async => {'done': true},
      );
      vmWatch.stop();
      expect(result.completed, true);
      steps = result.steps;
      final traces = ExecutionTraceService();
      final session = traces.start(
        mode: ExecutionTraceMode.test,
        source: const ExecutionTraceSource(type: 'benchmark', id: 'synthetic'),
      );
      final traceWatch = Stopwatch()..start();
      await DartGraphVm(program, traceSink: session).execute(
        context: EvaluationContext(),
        action: (node, config, context) async => {'done': true},
      );
      traceWatch.stop();
      session.end(ExecutionTraceRunStatus.completed);
      await traces.dispose();
      if (sample >= 0) {
        signature.add(signatureWatch.elapsedMicroseconds);
        cold.add(coldWatch.elapsedMicroseconds);
        hot.add(hotWatch.elapsedMicroseconds);
        vm.add(vmWatch.elapsedMicroseconds);
        traced.add(traceWatch.elapsedMicroseconds);
      }
    }
    final lookupSamples = await allocations?.measure(
      () => cache.getOrCompile(document),
    );
    final signatureSamples = await allocations?.measure(
      () => graphProgramSignature(document),
    );
    final coldSamples = await allocations?.measure(
      () => GraphProgramCache().getOrCompile(document),
    );
    expect(cache.compilationCount, 1);
    return {
      'scenario': name,
      ...size,
      'samples': samples,
      'signatureP50Us': percentile(signature, .5),
      'signatureP95Us': percentile(signature, .95),
      'compileP50Us': percentile(cold, .5),
      'compileP95Us': percentile(cold, .95),
      'cachedLookupP50Us': percentile(hot, .5),
      'cachedLookupP95Us': percentile(hot, .95),
      'vmP50Us': percentile(vm, .5),
      'vmP95Us': percentile(vm, .95),
      'traceVmP50Us': percentile(traced, .5),
      'traceVmP95Us': percentile(traced, .95),
      'lookupAllocationSamples': ?lookupSamples,
      'signatureAllocationSamples': ?signatureSamples,
      'coldAllocationSamples': ?coldSamples,
      'programInstructions': program.instructions.length,
      'executedInstructions': steps,
      'programActions': program.actionNodes.length,
      'programSlots': program.localSlotCount,
      'programSubgraphs': program.subgraphs.length,
      'programWires': program.wireMap.length,
      'signatureBytes': utf8.encode(graphProgramSignature(document)).length,
      'cacheHits': cache.hitCount,
      'cacheMisses': cache.missCount,
      'signatureBuilds': cache.signatureBuildCount,
      'compiledPrograms': cache.compilationCount,
      'completed': true,
    };
  } finally {
    await allocations?.close();
  }
}

int percentile(List<int> values, double fraction) {
  final sorted = [...values]..sort();
  return sorted[(fraction * sorted.length).ceil() - 1];
}
