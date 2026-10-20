import 'trace_models.dart';
import 'trace_events.dart';
import 'trace_sink.dart';
import 'trace_redaction.dart';

final class ExecutionTraceSession implements ExecutionTraceSink {
  ExecutionTraceSession({
    required this._publish,
    required this._nextSequence,
    required this.info,
  }) : _started = info.startedAt;

  final void Function(ExecutionTraceEvent) _publish;
  final int Function(String) _nextSequence;
  ExecutionTraceRunInfo info;
  final DateTime _started;
  final Map<String, int> _invocations = {};
  bool _ended = false;

  @override
  String get executionId => info.executionId;

  int _nextInvocation(ExecutionNodeRef node, int? value) =>
      value ??= (_invocations[node.key] ?? 0) + 1;

  @override
  void nodeStarted(ExecutionNodeRef node, {int? invocation}) {
    if (_ended) return;
    final count = _nextInvocation(node, invocation);
    _invocations[node.key] = count;
    _publish(
      ExecutionNodeStartedEvent(
        executionId: executionId,
        seq: _nextSequence(executionId),
        timestamp: DateTime.now(),
        mode: info.mode,
        node: node,
        invocation: count,
      ),
    );
  }

  @override
  void nodeCompleted(
    ExecutionNodeRef node, {
    int? invocation,
    Duration? duration,
  }) {
    if (_ended) return;
    final count = _nextInvocation(node, invocation);
    _publish(
      ExecutionNodeCompletedEvent(
        executionId: executionId,
        seq: _nextSequence(executionId),
        timestamp: DateTime.now(),
        mode: info.mode,
        node: node,
        invocation: count,
        duration: duration ?? DateTime.now().difference(_started),
      ),
    );
  }

  @override
  void nodeFailed(
    ExecutionNodeRef node,
    Object error, {
    StackTrace? stackTrace,
    int? invocation,
    Duration? duration,
  }) {
    if (_ended) return;
    final count = _nextInvocation(node, invocation);
    _publish(
      ExecutionNodeFailedEvent(
        executionId: executionId,
        seq: _nextSequence(executionId),
        timestamp: DateTime.now(),
        mode: info.mode,
        node: node,
        invocation: count,
        duration: duration ?? DateTime.now().difference(_started),
        error: ExecutionTraceError.fromObject(error, stackTrace),
      ),
    );
  }

  @override
  void nodeResult(ExecutionNodeRef node, Object? result, {int? invocation}) {
    if (_ended) return;
    final count = _nextInvocation(node, invocation);
    final sanitized = sanitizeExecutionResult(result);
    _publish(
      ExecutionNodeResultEvent(
        executionId: executionId,
        seq: _nextSequence(executionId),
        timestamp: DateTime.now(),
        mode: info.mode,
        node: node,
        invocation: count,
        preview: sanitized.value,
        truncated: sanitized.truncated,
      ),
    );
  }

  @override
  void controlPath(ExecutionNodeRef node, String port, {int? iteration}) {
    if (_ended) return;
    _publish(
      ExecutionControlPathEvent(
        executionId: executionId,
        seq: _nextSequence(executionId),
        timestamp: DateTime.now(),
        mode: info.mode,
        node: node,
        port: port,
        iteration: iteration,
      ),
    );
  }

  @override
  void edgeTraversed(ExecutionEdgeRef edge) {
    if (_ended) return;
    _publish(
      ExecutionEdgeTraversedEvent(
        executionId: executionId,
        seq: _nextSequence(executionId),
        timestamp: DateTime.now(),
        mode: info.mode,
        edge: edge,
      ),
    );
  }

  @override
  void loopIteration(ExecutionNodeRef node, int iteration) {
    if (_ended) return;
    _publish(
      ExecutionLoopIterationEvent(
        executionId: executionId,
        seq: _nextSequence(executionId),
        timestamp: DateTime.now(),
        mode: info.mode,
        node: node,
        iteration: iteration,
      ),
    );
  }

  @override
  void subgraphEntered(
    ExecutionNodeRef callNode,
    String subgraphId, {
    required int depth,
  }) {
    if (_ended) return;
    _publish(
      ExecutionSubgraphEnteredEvent(
        executionId: executionId,
        seq: _nextSequence(executionId),
        timestamp: DateTime.now(),
        mode: info.mode,
        callNode: callNode,
        subgraphId: subgraphId,
        depth: depth,
      ),
    );
  }

  @override
  void subgraphExited(
    ExecutionNodeRef callNode,
    String subgraphId, {
    required int depth,
    required Duration duration,
  }) {
    if (_ended) return;
    _publish(
      ExecutionSubgraphExitedEvent(
        executionId: executionId,
        seq: _nextSequence(executionId),
        timestamp: DateTime.now(),
        mode: info.mode,
        callNode: callNode,
        subgraphId: subgraphId,
        depth: depth,
        duration: duration,
      ),
    );
  }

  @override
  void end(
    ExecutionTraceRunStatus status, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (_ended) return;
    _ended = true;
    final traceError = error == null
        ? null
        : ExecutionTraceError.fromObject(error, stackTrace);
    _publish(
      ExecutionRunEndedEvent(
        executionId: executionId,
        seq: _nextSequence(executionId),
        timestamp: DateTime.now(),
        mode: info.mode,
        status: status,
        duration: DateTime.now().difference(_started),
        error: traceError,
      ),
    );
  }
}
