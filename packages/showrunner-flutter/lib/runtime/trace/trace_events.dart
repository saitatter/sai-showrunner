import 'trace_models.dart';

sealed class ExecutionTraceEvent {
  const ExecutionTraceEvent({
    required this.executionId,
    required this.seq,
    required this.timestamp,
    required this.mode,
  });

  final String executionId;
  final int seq;
  final DateTime timestamp;
  final ExecutionTraceMode mode;
  String get type;

  Map<String, Object?> toJson() => {
    'type': type,
    'executionId': executionId,
    'seq': seq,
    'timestamp': timestamp.millisecondsSinceEpoch,
    'mode': mode.name,
  };
}

final class ExecutionRunStartedEvent extends ExecutionTraceEvent {
  const ExecutionRunStartedEvent({
    required super.executionId,
    required super.seq,
    required super.timestamp,
    required super.mode,
    required this.source,
  });

  final ExecutionTraceSource source;

  @override
  String get type => 'run.started';

  @override
  Map<String, Object?> toJson() => {
    ...super.toJson(),
    'source': source.toJson(),
  };
}

final class ExecutionRunEndedEvent extends ExecutionTraceEvent {
  const ExecutionRunEndedEvent({
    required super.executionId,
    required super.seq,
    required super.timestamp,
    required super.mode,
    required this.status,
    required this.duration,
    this.error,
  });

  final ExecutionTraceRunStatus status;
  final Duration duration;
  final ExecutionTraceError? error;

  @override
  String get type => 'run.ended';

  @override
  Map<String, Object?> toJson() => {
    ...super.toJson(),
    'status': status.name,
    'durationMs': duration.inMilliseconds,
    if (error != null) 'error': error!.toJson(),
  };
}

final class ExecutionNodeStartedEvent extends ExecutionTraceEvent {
  const ExecutionNodeStartedEvent({
    required super.executionId,
    required super.seq,
    required super.timestamp,
    required super.mode,
    required this.node,
    required this.invocation,
  });

  final ExecutionNodeRef node;
  final int invocation;

  @override
  String get type => 'node.started';

  @override
  Map<String, Object?> toJson() => {
    ...super.toJson(),
    'node': node.toJson(),
    'invocation': invocation,
  };
}

final class ExecutionNodeCompletedEvent extends ExecutionTraceEvent {
  const ExecutionNodeCompletedEvent({
    required super.executionId,
    required super.seq,
    required super.timestamp,
    required super.mode,
    required this.node,
    required this.invocation,
    required this.duration,
  });

  final ExecutionNodeRef node;
  final int invocation;
  final Duration duration;

  @override
  String get type => 'node.completed';

  @override
  Map<String, Object?> toJson() => {
    ...super.toJson(),
    'node': node.toJson(),
    'invocation': invocation,
    'durationMs': duration.inMilliseconds,
  };
}

final class ExecutionNodeFailedEvent extends ExecutionTraceEvent {
  const ExecutionNodeFailedEvent({
    required super.executionId,
    required super.seq,
    required super.timestamp,
    required super.mode,
    required this.node,
    required this.invocation,
    required this.duration,
    required this.error,
  });

  final ExecutionNodeRef node;
  final int invocation;
  final Duration duration;
  final ExecutionTraceError error;

  @override
  String get type => 'node.failed';

  @override
  Map<String, Object?> toJson() => {
    ...super.toJson(),
    'node': node.toJson(),
    'invocation': invocation,
    'durationMs': duration.inMilliseconds,
    'error': error.toJson(),
  };
}

final class ExecutionNodeResultEvent extends ExecutionTraceEvent {
  const ExecutionNodeResultEvent({
    required super.executionId,
    required super.seq,
    required super.timestamp,
    required super.mode,
    required this.node,
    required this.invocation,
    required this.preview,
    required this.truncated,
  });

  final ExecutionNodeRef node;
  final int invocation;
  final Object? preview;
  final bool truncated;

  @override
  String get type => 'node.result';

  @override
  Map<String, Object?> toJson() => {
    ...super.toJson(),
    'node': node.toJson(),
    'invocation': invocation,
    if (preview != null) 'resultPreview': preview,
    'truncated': truncated,
  };
}

final class ExecutionControlPathEvent extends ExecutionTraceEvent {
  const ExecutionControlPathEvent({
    required super.executionId,
    required super.seq,
    required super.timestamp,
    required super.mode,
    required this.node,
    required this.port,
    this.iteration,
  });

  final ExecutionNodeRef node;
  final String port;
  final int? iteration;

  @override
  String get type => 'control.path';

  @override
  Map<String, Object?> toJson() => {
    ...super.toJson(),
    'node': node.toJson(),
    'port': port,
    if (iteration != null) 'iteration': iteration,
  };
}

final class ExecutionEdgeTraversedEvent extends ExecutionTraceEvent {
  const ExecutionEdgeTraversedEvent({
    required super.executionId,
    required super.seq,
    required super.timestamp,
    required super.mode,
    required this.edge,
  });

  final ExecutionEdgeRef edge;

  @override
  String get type => 'edge.traversed';

  @override
  Map<String, Object?> toJson() => {...super.toJson(), 'edge': edge.toJson()};
}

final class ExecutionLoopIterationEvent extends ExecutionTraceEvent {
  const ExecutionLoopIterationEvent({
    required super.executionId,
    required super.seq,
    required super.timestamp,
    required super.mode,
    required this.node,
    required this.iteration,
  });

  final ExecutionNodeRef node;
  final int iteration;

  @override
  String get type => 'loop.iteration';

  @override
  Map<String, Object?> toJson() => {
    ...super.toJson(),
    'node': node.toJson(),
    'iteration': iteration,
  };
}

final class ExecutionSubgraphEnteredEvent extends ExecutionTraceEvent {
  const ExecutionSubgraphEnteredEvent({
    required super.executionId,
    required super.seq,
    required super.timestamp,
    required super.mode,
    required this.callNode,
    required this.subgraphId,
    required this.depth,
  });

  final ExecutionNodeRef callNode;
  final String subgraphId;
  final int depth;

  @override
  String get type => 'subgraph.entered';

  @override
  Map<String, Object?> toJson() => {
    ...super.toJson(),
    'callNode': callNode.toJson(),
    'subgraphId': subgraphId,
    'depth': depth,
  };
}

final class ExecutionSubgraphExitedEvent extends ExecutionTraceEvent {
  const ExecutionSubgraphExitedEvent({
    required super.executionId,
    required super.seq,
    required super.timestamp,
    required super.mode,
    required this.callNode,
    required this.subgraphId,
    required this.depth,
    required this.duration,
  });

  final ExecutionNodeRef callNode;
  final String subgraphId;
  final int depth;
  final Duration duration;

  @override
  String get type => 'subgraph.exited';

  @override
  Map<String, Object?> toJson() => {
    ...super.toJson(),
    'callNode': callNode.toJson(),
    'subgraphId': subgraphId,
    'depth': depth,
    'durationMs': duration.inMilliseconds,
  };
}
