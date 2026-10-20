import '../../graph/domain/automation_document.dart';
import '../../runtime/action_queue.dart';
import '../../runtime/automation_invocation_service.dart';
import '../../runtime/graph_invocation.dart';
import '../../runtime/execution_trace.dart';

/// Adapts editor run requests to the shared queue/execution boundary.
final class GraphExecutionWorkflow {
  const GraphExecutionWorkflow(this.invocations);
  final AutomationInvocationService invocations;

  Future<QueuedGraphExecution> run({
    required AutomationDocument automation,
    required ExecutionTraceSource source,
    String? entryNodeId,
    String? entrySpaceId,
  }) async {
    final result = await invocations.invokeOrThrow(
      GraphInvocation(
        target: InvocationDocument(automation),
        origin: InvocationOrigin.automation,
        sourceId: source.id,
        sourceSubId: source.subId,
        dispatch: InvocationDispatch.queued,
        entryNodeId: entryNodeId,
        entrySpaceId: entrySpaceId ?? mainAutomationSpace,
        queueId: automation.queueId,
      ),
    );
    final accepted = result as InvocationAccepted;
    final item = accepted.item;
    await invocations.queues!.drain(accepted.receipt.queueId);
    if (item.status == 'failed') {
      throw StateError(
        item.errorUserMessage ?? item.error ?? 'Execution failed',
      );
    }
    return item;
  }
}
