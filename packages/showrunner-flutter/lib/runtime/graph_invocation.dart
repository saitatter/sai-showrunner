import '../graph/domain/automation_document.dart';
import '../graph/runtime/graph_runtime.dart';
import 'action_queue.dart';
import 'cancellation.dart';
import 'execution_trace.dart';
import 'expression.dart';

enum InvocationOrigin {
  automation,
  inlineTest,
  profile,
  streamPlan,
  chatCommand,
  chatQuickAction,
}

extension InvocationOriginTag on InvocationOrigin {
  String get tag => switch (this) {
    InvocationOrigin.automation => 'automation',
    InvocationOrigin.inlineTest => 'inline-test',
    InvocationOrigin.profile => 'profile',
    InvocationOrigin.streamPlan => 'stream-plan',
    InvocationOrigin.chatCommand => 'chat-command',
    InvocationOrigin.chatQuickAction => 'chat-quick-action',
  };
}

enum InvocationDispatch { direct, queued, documentQueue }

enum InvocationStatus { accepted, completed, failed, cancelled }

enum InvocationFailureStage { load, validation, dispatch, execution }

sealed class GraphInvocationTarget {
  const GraphInvocationTarget();
}

final class InvocationDocument extends GraphInvocationTarget {
  const InvocationDocument(this.document);
  final AutomationDocument document;
}

final class InvocationFile extends GraphInvocationTarget {
  const InvocationFile(this.fileName);
  final String fileName;
}

/// A collection snapshot, separate from mutable evaluation state. Opaque runtime
/// capabilities are retained as references and are never serialized by this API.
final class InvocationContext {
  InvocationContext({RuntimeMap locals = const {}, RuntimeMap state = const {}})
    : locals = _snapshotMap(locals),
      state = _snapshotMap(state);
  factory InvocationContext.capture(EvaluationContext context) =>
      InvocationContext(locals: context.locals, state: context.contextState);
  final RuntimeMap locals;
  final RuntimeMap state;
  EvaluationContext evaluate({DartCancellationToken? cancellation}) =>
      EvaluationContext(
        locals: _copyMap(locals),
        contextState: _copyMap(state),
        cancellationToken: cancellation,
      );
}

/// Runtime-only request. Persistence/wire DTOs must not contain tokens, observers
/// or evaluation objects. Graph documents and all collection fields are immutable.
final class GraphInvocation {
  GraphInvocation({
    required this.target,
    required this.origin,
    required this.sourceId,
    required this.dispatch,
    InvocationContext? context,
    this.sourceSubId,
    this.queueId,
    this.entryNodeId,
    this.entrySpaceId = mainAutomationSpace,
    this.cancellation,
    this.mode = ExecutionTraceMode.live,
    this.onNodeEnter,
    this.onNodeExit,
    RuntimeMap sourceDetails = const {},
  }) : context = context ?? InvocationContext(),
       sourceDetails = _snapshotMap(sourceDetails);
  final GraphInvocationTarget target;
  final InvocationOrigin origin;
  final String sourceId;
  final String? sourceSubId, queueId, entryNodeId;
  final String entrySpaceId;
  final InvocationDispatch dispatch;
  final InvocationContext context;
  final DartCancellationToken? cancellation;
  final ExecutionTraceMode mode;
  final void Function(String)? onNodeEnter, onNodeExit;
  final RuntimeMap sourceDetails;
  ExecutionTraceSource traceSource(String documentId) => ExecutionTraceSource(
    type: origin.tag,
    id: sourceId,
    subId: sourceSubId,
    documentId: documentId,
  );
}

sealed class InvocationResult {
  const InvocationResult(this.status);
  final InvocationStatus status;
}

final class EnqueueReceipt {
  const EnqueueReceipt({
    required this.documentId,
    required this.queueId,
    required this.itemId,
    required this.acceptedAt,
  });
  final String documentId, queueId, itemId;
  final DateTime acceptedAt;
}

final class InvocationAccepted extends InvocationResult {
  const InvocationAccepted(this.receipt, this.item)
    : super(InvocationStatus.accepted);
  final EnqueueReceipt receipt;

  /// Mutable queue progress is deliberately separate from the immutable receipt.
  final QueuedGraphExecution item;
}

final class InvocationCompleted extends InvocationResult {
  const InvocationCompleted({
    required this.execution,
    required this.startedAt,
    required this.completedAt,
  }) : super(InvocationStatus.completed);
  final GraphExecutionResult execution;
  final DateTime startedAt, completedAt;
}

final class InvocationFailed extends InvocationResult {
  InvocationFailed({
    required this.stage,
    required this.error,
    required this.stack,
    required this.failedAt,
  }) : super(
         error is DartCancelledException
             ? InvocationStatus.cancelled
             : InvocationStatus.failed,
       );
  final InvocationFailureStage stage;
  final Object error;
  final StackTrace stack;
  final DateTime failedAt;
  Never rethrowError() => Error.throwWithStackTrace(error, stack);
}

RuntimeMap _snapshotMap(Map value) => Map<String, Object?>.unmodifiable({
  for (final entry in value.entries)
    entry.key as String: _snapshot(entry.value),
});
Object? _snapshot(Object? value) => switch (value) {
  Map map => _snapshotMap(map),
  List list => List<Object?>.unmodifiable(list.map(_snapshot)),
  _ => value,
};
Map<String, dynamic> _copyMap(Map value) => {
  for (final entry in value.entries) entry.key as String: _copy(entry.value),
};
Object? _copy(Object? value) => switch (value) {
  Map map => _copyMap(map),
  List list => list.map(_copy).toList(),
  _ => value,
};
