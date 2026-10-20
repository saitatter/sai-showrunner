import 'dart:async';

import '../graph/domain/automation_document.dart';
import '../graph/runtime/automation_contract_validation.dart';
import '../graph/runtime/automation_runtime_projection.dart';
import '../graph/runtime/graph_execution_engine.dart';
import '../graph/runtime/graph_runtime.dart';
import '../plugins/registry/plugin_registry.dart';
import 'automation_queue_manager.dart';
import 'graph_invocation.dart';
import 'action_queue.dart';
import 'execution_trace.dart';
import 'expression.dart';

typedef InvocationDocumentLoader =
    Future<AutomationDocument?> Function(String fileName);

/// Orchestration only: graph execution, queue scheduling and file access retain
/// their own owners. This boundary never retries actions or equates acceptance
/// with completion. File loaders must enforce their repository's path boundary.
final class AutomationInvocationService {
  const AutomationInvocationService({
    required this.engine,
    required this.registry,
    this.queues,
    this.loadDocument,
  });
  final GraphExecutionEngine engine;
  final FutureOr<DartPluginRegistry> Function() registry;
  final DartAutomationQueueManager? queues;
  final InvocationDocumentLoader? loadDocument;

  Future<GraphExecutionResult> executeQueued(
    AutomationDocument document,
    EvaluationContext context,
    QueuedGraphExecution item,
  ) async {
    context.cancellationToken?.throwIfCancelled();
    final providerRegistry = await registry();
    context.cancellationToken?.throwIfCancelled();
    return engine.executeWithRegistry(
      automation: document,
      context: context,
      registry: providerRegistry,
      entryNodeId: item.source['entryNodeId'] as String?,
      entrySpaceId:
          item.source['entrySpaceId'] as String? ?? mainAutomationSpace,
      traceMode: item.source['traceMode'] == 'test'
          ? ExecutionTraceMode.test
          : ExecutionTraceMode.live,
      traceSource: ExecutionTraceSource.fromMetadata({
        ...item.source,
        'itemId': item.id,
      }),
    );
  }

  Future<InvocationResult> invoke(GraphInvocation request) async {
    var stage = InvocationFailureStage.load;
    try {
      request.cancellation?.throwIfCancelled();
      final AutomationDocument? document;
      switch (request.target) {
        case InvocationDocument(document: final value):
          document = value;
        case InvocationFile(:final fileName):
          final load = loadDocument;
          if (load == null) {
            throw StateError('Automation file loading is unavailable.');
          }
          document = await load(fileName);
      }
      request.cancellation?.throwIfCancelled();
      if (document == null) throw StateError('Automation does not exist.');
      stage = InvocationFailureStage.validation;
      if (request.sourceId.isEmpty) {
        throw ArgumentError('Invocation source ID is required.');
      }
      final providerRegistry = await registry();
      request.cancellation?.throwIfCancelled();
      final queueId = request.queueId ?? document.queueId;
      final enqueue =
          request.dispatch == InvocationDispatch.queued ||
          (request.dispatch == InvocationDispatch.documentQueue &&
              queueId != null &&
              queues != null);
      if (enqueue) {
        validateAutomationContracts(document, providerRegistry);
        AutomationRuntimeProjection(
          document,
          rootSpaceId: request.entrySpaceId,
        ).validate();
        if (request.entryNodeId != null &&
            !document.graph.spaces[request.entrySpaceId]!.nodes.containsKey(
              request.entryNodeId,
            )) {
          throw StateError(
            'Invocation entry node does not exist in its space.',
          );
        }
        stage = InvocationFailureStage.dispatch;
        final queue = queues;
        if (queue == null) {
          throw StateError('Automation queues are unavailable.');
        }
        final item = await queue.enqueue(
          document,
          request.context.evaluate(cancellation: request.cancellation),
          queueId: queueId,
          entryNodeId: request.entryNodeId,
          entrySpaceId: request.entrySpaceId,
          sourceMetadata: {
            ...request.sourceDetails,
            'sourceType': request.origin.tag,
            'sourceId': request.sourceId,
            'sourceSubId': ?request.sourceSubId,
            'documentId': document.id,
            'traceMode': request.mode.name,
          },
        );
        return InvocationAccepted(
          EnqueueReceipt(
            documentId: document.id,
            queueId: (item.source['queueId'] as String),
            itemId: item.id,
            acceptedAt: DateTime.now().toUtc(),
          ),
          item,
        );
      }
      stage = InvocationFailureStage.execution;
      final startedAt = DateTime.now().toUtc();
      final result = await engine.executeWithRegistry(
        automation: document,
        context: request.context.evaluate(cancellation: request.cancellation),
        registry: providerRegistry,
        entryNodeId: request.entryNodeId,
        entrySpaceId: request.entrySpaceId,
        onNodeEnter: request.onNodeEnter,
        onNodeExit: request.onNodeExit,
        traceMode: request.mode,
        traceSource: request.traceSource(document.id),
      );
      return InvocationCompleted(
        execution: result,
        startedAt: startedAt,
        completedAt: DateTime.now().toUtc(),
      );
    } catch (error, stack) {
      return InvocationFailed(
        stage: stage,
        error: error,
        stack: stack,
        failedAt: DateTime.now().toUtc(),
      );
    }
  }

  /// Preserve provider/domain error identity for callers whose public contract
  /// already throws; queue/command counters only advance after accepted results.
  Future<InvocationResult> invokeOrThrow(GraphInvocation request) async {
    final result = await invoke(request);
    if (result is InvocationFailed) result.rethrowError();
    return result;
  }
}
