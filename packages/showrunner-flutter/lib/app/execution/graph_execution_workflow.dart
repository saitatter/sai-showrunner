import '../../graph/domain/automation_document.dart';
import '../../runtime/action_queue.dart';
import '../../runtime/automation_queue_manager.dart';
import '../../runtime/execution_trace.dart';
import '../../runtime/expression.dart';

/// Adapts editor run requests to the shared queue/execution boundary.
final class GraphExecutionWorkflow {
  const GraphExecutionWorkflow(this.queues);
  final DartAutomationQueueManager queues;

  Future<QueuedGraphExecution> run({
    required AutomationDocument automation,
    required ExecutionTraceSource source,
    String? entryNodeId,
    String? entrySpaceId,
  }) async {
    final item = await queues.enqueue(
      automation,
      EvaluationContext(),
      entryNodeId: entryNodeId,
      entrySpaceId: entrySpaceId,
      queueId: automation.queueId,
      sourceMetadata: {'sourceType': source.type, 'sourceId': source.id},
    );
    await queues.drain(automation.queueId);
    if (item.status == 'failed') {
      throw StateError(
        item.errorUserMessage ?? item.error ?? 'Execution failed',
      );
    }
    return item;
  }
}
