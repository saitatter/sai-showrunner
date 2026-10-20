import 'trace_models.dart';
import 'trace_events.dart';
import 'trace_sink.dart';
import 'trace_redaction.dart';

final class ExecutionTraceSession implements ExecutionTraceSink {
  ExecutionTraceSession({
    required this._publish,
    required this._nextSequence,
    required this.info,
    required this.isRetained,
    required this.maxNodes,
    this.valuePolicy = TraceValuePolicy.metadata,
  }) : _started = info.startedAt;

  final void Function(ExecutionTraceEvent) _publish;
  final int Function(String) _nextSequence;
  ExecutionTraceRunInfo info;
  final bool Function(String) isRetained;
  final int maxNodes;
  final TraceValuePolicy valuePolicy;
  final DateTime _started;
  final Map<String, int> _invocations = {};
  bool _ended = false;
  bool get _accepts {
    if (_ended) return false;
    if (!isRetained(executionId)) {
      _ended = true;
      _invocations.clear();
      return false;
    }
    return true;
  }

  @override
  String get executionId => info.executionId;

  int _nextInvocation(ExecutionNodeRef node, int? value) =>
      value ??= (_invocations[node.key] ?? 0) + 1;

  @override
  void nodeStarted(ExecutionNodeRef node, {int? invocation}) {
    if (!_accepts) return;
    final count = _nextInvocation(node, invocation);
    _invocations[node.key] = count;
    while (_invocations.length > maxNodes) {
      _invocations.remove(_invocations.keys.first);
    }
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
    if (!_accepts) return;
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
    if (!_accepts) return;
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
    if (!_accepts) return;
    final count = _nextInvocation(node, invocation);
    final sanitized = sanitizeExecutionResult(result, policy: valuePolicy);
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
    if (!_accepts) return;
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
    if (!_accepts) return;
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
    if (!_accepts) return;
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
    if (!_accepts) return;
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
    if (!_accepts) return;
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
    if (!_accepts) return;
    _ended = true;
    _invocations.clear();
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
