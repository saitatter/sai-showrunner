import 'dart:collection';
import 'automation_contract_validation.dart';
import 'graph_program_signature.dart';

import '../../plugins/registry/plugin_registry.dart';
import 'automation_runtime_projection.dart';
import '../domain/automation_document.dart';
import '../../runtime/expression.dart';
import 'graph_runtime.dart';
import 'production_graph_vm.dart';
import '../../runtime/execution_trace.dart';

typedef GraphExecutionObserver = void Function(String nodeId);

/// The single execution boundary used by application-owned graph runners.
///
/// The interpreter remains available as a reference oracle, while the
/// production implementation uses the same flat-program/VM shape as the
/// reference desktop runtime.
abstract interface class GraphExecutionEngine {
  Future<GraphExecutionResult> executeWithRegistry({
    required AutomationDocument automation,
    required EvaluationContext context,
    required DartPluginRegistry registry,
    String? entryNodeId,
    String entrySpaceId = mainAutomationSpace,
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
    required AutomationDocument automation,
    required EvaluationContext context,
    required DartPluginRegistry registry,
    String? entryNodeId,
    String entrySpaceId = mainAutomationSpace,
    GraphExecutionObserver? onNodeEnter,
    GraphExecutionObserver? onNodeExit,
    ExecutionTraceSink? traceSink,
    ExecutionTraceMode traceMode = ExecutionTraceMode.live,
    ExecutionTraceSource? traceSource,
  }) async {
    validateAutomationContracts(automation, registry);
    final projection = AutomationRuntimeProjection(
      automation,
      rootSpaceId: entrySpaceId,
    );
    projection.validate();
    final session = traceSink == null && traceService != null
        ? traceService!.start(
            mode: traceMode,
            source: (traceSource ?? _defaultTraceSource(automation))
                .withDocumentId(automation.id),
          )
        : null;
    final sink = traceSink ?? session;
    try {
      final result =
          await DartGraphRuntime(
            maxSteps: maxSteps,
            maxDepth: maxDepth,
          ).executeWithRegistry(
            graph: projection.graph,
            graphScope: projection.signatureForSpace(entrySpaceId) != null
                ? SubgraphScope(projection.signatureForSpace(entrySpaceId)!.id)
                : const MainGraphScope(),
            context: context,
            registry: registry,
            dataWires: projection.dataWires,
            subgraphs: projection.subgraphs,
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
    required AutomationDocument automation,
    required EvaluationContext context,
    required DartPluginRegistry registry,
    String? entryNodeId,
    String entrySpaceId = mainAutomationSpace,
    GraphExecutionObserver? onNodeEnter,
    GraphExecutionObserver? onNodeExit,
    ExecutionTraceSink? traceSink,
    ExecutionTraceMode traceMode = ExecutionTraceMode.live,
    ExecutionTraceSource? traceSource,
  }) async {
    validateAutomationContracts(automation, registry);
    final program = cache.getOrCompile(
      automation,
      entryNodeId: entryNodeId,
      entrySpaceId: entrySpaceId,
    );
    final executionContext = EvaluationContext(
      locals: context.locals,
      contextState: {...registry.stateContext(), ...context.contextState},
      cancellationToken: context.cancellationToken,
    );
    final session = traceSink == null && traceService != null
        ? traceService!.start(
            mode: traceMode,
            source: (traceSource ?? _defaultTraceSource(automation))
                .withDocumentId(automation.id),
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
            action: (node, config, actionContext) => registry.invokeAction(
              node.data['plugin'] as String,
              node.data['action'] as String,
              config,
              context: actionContext,
            ),
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

ExecutionTraceSource _defaultTraceSource(AutomationDocument automation) =>
    ExecutionTraceSource(type: 'automation', id: automation.id);

/// Bounded in-memory cache matching the reference runtime's program cache.
final class GraphProgramCache {
  GraphProgramCache({this.maxEntries = 128}) {
    if (maxEntries < 0) throw ArgumentError.value(maxEntries, 'maxEntries');
  }

  final int maxEntries;
  final Map<String, DartGraphProgram> _entries = {};
  int compilationCount = 0;
  int hitCount = 0;
  int missCount = 0;
  int signatureBuildCount = 0;
  final _signatures =
      LinkedHashMap<
        AutomationDocument,
        ({String space, String? entry, String payload})
      >.identity();

  String _signatureFor(
    AutomationDocument document,
    String space,
    String? entry,
  ) {
    final previous = _signatures.remove(document);
    if (previous != null &&
        previous.space == space &&
        previous.entry == entry) {
      _signatures[document] = previous;
      return previous.payload;
    }
    final payload = graphProgramSignature(
      document,
      entrySpaceId: space,
      entryNodeId: entry,
    );
    signatureBuildCount++;
    if (maxEntries > 0) {
      _signatures[document] = (space: space, entry: entry, payload: payload);
      while (_signatures.length > maxEntries) {
        _signatures.remove(_signatures.keys.first);
      }
    }
    return payload;
  }

  int get length => _entries.length;

  DartGraphProgram getOrCompile(
    AutomationDocument automation, {
    String? entryNodeId,
    String entrySpaceId = mainAutomationSpace,
  }) {
    final signature = _signatureFor(automation, entrySpaceId, entryNodeId);
    final cached = _entries.remove(signature);
    if (cached != null) {
      hitCount++;
      _entries[signature] = cached;
      return cached;
    }
    missCount++;
    final program = DartProductionGraphCompiler().compileAutomation(
      automation,
      entryNodeId: entryNodeId,
      entrySpaceId: entrySpaceId,
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
    _signatures.clear();
  }
}
