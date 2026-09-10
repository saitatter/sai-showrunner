import 'dart:convert';

import '../plugins/registry/plugin_registry.dart';
import '../schema/automation.dart';
import 'expression.dart';
import 'graph_runtime.dart';
import 'production_graph_vm.dart';

typedef GraphExecutionObserver = void Function(String nodeId);

/// The single execution boundary used by application-owned graph runners.
///
/// The interpreter remains available as a reference oracle, while the
/// production implementation uses the same flat-program/VM shape as the
/// reference desktop runtime.
abstract interface class GraphExecutionEngine {
  Future<GraphExecutionResult> executeWithRegistry({
    required AutomationData automation,
    required EvaluationContext context,
    required DartPluginRegistry registry,
    String? entryNodeId,
    GraphExecutionObserver? onNodeEnter,
    GraphExecutionObserver? onNodeExit,
  });
}

/// Reference implementation used by parity tests.
final class InterpreterExecutionEngine implements GraphExecutionEngine {
  const InterpreterExecutionEngine({this.maxSteps = 10000, this.maxDepth = 64});

  final int maxSteps;
  final int maxDepth;

  @override
  Future<GraphExecutionResult> executeWithRegistry({
    required AutomationData automation,
    required EvaluationContext context,
    required DartPluginRegistry registry,
    String? entryNodeId,
    GraphExecutionObserver? onNodeEnter,
    GraphExecutionObserver? onNodeExit,
  }) => DartGraphRuntime(maxSteps: maxSteps, maxDepth: maxDepth)
      .executeWithRegistry(
        graph: automation.graph,
        context: context,
        registry: registry,
        dataWires: automation.dataWires,
        subgraphs: automation.subgraphs,
        entryNodeId: entryNodeId,
        onNodeEnter: onNodeEnter,
        onNodeExit: onNodeExit,
      );
}

/// Production graph engine: compile to a flat program, cache it, and execute
/// through the 16-opcode VM.
final class CompiledExecutionEngine implements GraphExecutionEngine {
  CompiledExecutionEngine({
    this.maxIterations = 10000,
    this.maxCallDepth = 32,
    GraphProgramCache? cache,
  }) : cache = cache ?? GraphProgramCache();

  final int maxIterations;
  final int maxCallDepth;
  final GraphProgramCache cache;

  int get compilationCount => cache.compilationCount;
  int get cacheSize => cache.length;

  void clearCache() => cache.clear();

  @override
  Future<GraphExecutionResult> executeWithRegistry({
    required AutomationData automation,
    required EvaluationContext context,
    required DartPluginRegistry registry,
    String? entryNodeId,
    GraphExecutionObserver? onNodeEnter,
    GraphExecutionObserver? onNodeExit,
  }) async {
    final program = cache.getOrCompile(automation, entryNodeId: entryNodeId);
    final executionContext = EvaluationContext(
      locals: context.locals,
      contextState: {...registry.stateContext(), ...context.contextState},
      cancellationToken: context.cancellationToken,
    );
    return DartGraphVm(
      program,
      maxIterations: maxIterations,
      maxCallDepth: maxCallDepth,
      onNodeEnter: onNodeEnter,
      onNodeExit: onNodeExit,
    ).execute(
      context: executionContext,
      action: (node, config, actionContext) =>
          registry.invoke(node, actionContext, config),
    );
  }
}

/// Bounded in-memory cache matching the reference runtime's program cache.
final class GraphProgramCache {
  GraphProgramCache({this.maxEntries = 128});

  final int maxEntries;
  final Map<String, DartGraphProgram> _entries = {};
  int compilationCount = 0;

  int get length => _entries.length;

  DartGraphProgram getOrCompile(
    AutomationData automation, {
    String? entryNodeId,
  }) {
    final signature = jsonEncode({
      'automation': automation.toJson(),
      'entryNodeId': entryNodeId ?? automation.graph.entryNodeId,
    });
    final cached = _entries.remove(signature);
    if (cached != null) {
      _entries[signature] = cached;
      return cached;
    }
    final program = DartProductionGraphCompiler().compileAutomation(
      automation,
      entryNodeId: entryNodeId,
    );
    compilationCount++;
    _entries[signature] = program;
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
    return program;
  }

  void clear() {
    _entries.clear();
  }
}
