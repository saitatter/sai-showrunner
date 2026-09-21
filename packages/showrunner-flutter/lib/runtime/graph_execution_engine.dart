import 'dart:convert';

import '../plugins/registry/plugin_registry.dart';
import '../schema/automation.dart';
import 'expression.dart';
import 'graph_runtime.dart';
import 'production_graph_vm.dart';
import 'execution_trace.dart';

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
    ExecutionTraceSink? traceSink,
    ExecutionTraceMode traceMode = ExecutionTraceMode.live,
    ExecutionTraceSource? traceSource,
  });
}

/// Reference implementation used by parity tests.
final class InterpreterExecutionEngine implements GraphExecutionEngine {
  const InterpreterExecutionEngine({
    this.maxSteps = 10000,
    this.maxDepth = 64,
    this.traceService,
  });

  final int maxSteps;
  final int maxDepth;
  final ExecutionTraceService? traceService;

  @override
  Future<GraphExecutionResult> executeWithRegistry({
    required AutomationData automation,
    required EvaluationContext context,
    required DartPluginRegistry registry,
    String? entryNodeId,
    GraphExecutionObserver? onNodeEnter,
    GraphExecutionObserver? onNodeExit,
    ExecutionTraceSink? traceSink,
    ExecutionTraceMode traceMode = ExecutionTraceMode.live,
    ExecutionTraceSource? traceSource,
  }) async {
    final session = traceSink == null && traceService != null
        ? traceService!.start(
            mode: traceMode,
            source: traceSource ?? _defaultTraceSource(automation),
          )
        : null;
    final sink = traceSink ?? session;
    try {
      final result =
          await DartGraphRuntime(
            maxSteps: maxSteps,
            maxDepth: maxDepth,
          ).executeWithRegistry(
            graph: automation.graph,
            context: context,
            registry: registry,
            dataWires: automation.dataWires,
            subgraphs: automation.subgraphs,
            entryNodeId: entryNodeId,
            onNodeEnter: onNodeEnter,
            onNodeExit: onNodeExit,
            traceSink: sink,
          );
      session?.end(ExecutionTraceRunStatus.completed);
      return result;
    } catch (error, stackTrace) {
      session?.end(
        traceStatusForError(error),
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }
}

/// Production graph engine: compile to a flat program, cache it, and execute
/// through the 16-opcode VM.
final class CompiledExecutionEngine implements GraphExecutionEngine {
  CompiledExecutionEngine({
    this.maxIterations = 10000,
    this.maxCallDepth = 32,
    GraphProgramCache? cache,
    this.traceService,
  }) : cache = cache ?? GraphProgramCache();

  final int maxIterations;
  final int maxCallDepth;
  final GraphProgramCache cache;
  final ExecutionTraceService? traceService;

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
    ExecutionTraceSink? traceSink,
    ExecutionTraceMode traceMode = ExecutionTraceMode.live,
    ExecutionTraceSource? traceSource,
  }) async {
    final program = cache.getOrCompile(automation, entryNodeId: entryNodeId);
    final executionContext = EvaluationContext(
      locals: context.locals,
      contextState: {...registry.stateContext(), ...context.contextState},
      cancellationToken: context.cancellationToken,
    );
    final session = traceSink == null && traceService != null
        ? traceService!.start(
            mode: traceMode,
            source: traceSource ?? _defaultTraceSource(automation),
          )
        : null;
    final sink = traceSink ?? session;
    try {
      final result =
          await DartGraphVm(
            program,
            maxIterations: maxIterations,
            maxCallDepth: maxCallDepth,
            onNodeEnter: onNodeEnter,
            onNodeExit: onNodeExit,
            traceSink: sink,
          ).execute(
            context: executionContext,
            action: (node, config, actionContext) =>
                registry.invoke(node, actionContext, config),
          );
      session?.end(ExecutionTraceRunStatus.completed);
      return result;
    } catch (error, stackTrace) {
      session?.end(
        traceStatusForError(error),
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }
}

ExecutionTraceSource _defaultTraceSource(AutomationData automation) =>
    ExecutionTraceSource(
      type: 'automation',
      id: automation.graph.entryNodeId.isEmpty
          ? 'unspecified'
          : automation.graph.entryNodeId,
    );

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
