import 'trace_models.dart';

abstract interface class ExecutionTraceSink {
  String get executionId;

  void nodeStarted(ExecutionNodeRef node, {int? invocation});
  void nodeCompleted(
    ExecutionNodeRef node, {
    int? invocation,
    Duration? duration,
  });
  void nodeFailed(
    ExecutionNodeRef node,
    Object error, {
    StackTrace? stackTrace,
    int? invocation,
    Duration? duration,
  });
  void nodeResult(ExecutionNodeRef node, Object? result, {int? invocation});
  void controlPath(ExecutionNodeRef node, String port, {int? iteration});
  void edgeTraversed(ExecutionEdgeRef edge);
  void loopIteration(ExecutionNodeRef node, int iteration);
  void subgraphEntered(
    ExecutionNodeRef callNode,
    String subgraphId, {
    required int depth,
  });
  void subgraphExited(
    ExecutionNodeRef callNode,
    String subgraphId, {
    required int depth,
    required Duration duration,
  });
  void end(
    ExecutionTraceRunStatus status, {
    Object? error,
    StackTrace? stackTrace,
  });
}
