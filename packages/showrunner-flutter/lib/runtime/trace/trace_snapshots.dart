import 'trace_models.dart';
import 'trace_events.dart';

final class ExecutionTraceNodeSnapshot {
  const ExecutionTraceNodeSnapshot({
    required this.node,
    required this.status,
    required this.invocationCount,
    this.activeCount = 0,
    this.startedAt,
    this.duration,
    this.error,
    this.resultPreview,
    this.selectedPort,
    this.lastIteration,
    this.subgraphId,
  });

  final ExecutionNodeRef node;
  final ExecutionTraceNodeStatus status;
  final int invocationCount;
  final int activeCount;
  final DateTime? startedAt;
  final Duration? duration;
  final ExecutionTraceError? error;
  final Object? resultPreview;
  final String? selectedPort;
  final int? lastIteration;
  final String? subgraphId;
}

final class ExecutionTraceRunSnapshot {
  const ExecutionTraceRunSnapshot({
    required this.info,
    required this.events,
    required this.nodes,
    this.edges = const {},
    this.droppedEventCount = 0,
    this.evictedNodeCount = 0,
    this.evictedEdgeCount = 0,
  });

  final ExecutionTraceRunInfo info;
  final List<ExecutionTraceEvent> events;
  final Map<String, ExecutionTraceNodeSnapshot> nodes;
  final Map<String, ExecutionTraceEdgeSnapshot> edges;
  final int droppedEventCount, evictedNodeCount, evictedEdgeCount;
  bool get isTruncated =>
      droppedEventCount + evictedNodeCount + evictedEdgeCount > 0;
}

final class ExecutionTraceEdgeSnapshot {
  const ExecutionTraceEdgeSnapshot(this.edge, this.traversalCount);
  final ExecutionEdgeRef edge;
  final int traversalCount;
}
