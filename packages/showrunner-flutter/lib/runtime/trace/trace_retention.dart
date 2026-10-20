import 'dart:collection';
import 'dart:convert';
import 'trace_models.dart';
import 'trace_events.dart';
import 'trace_snapshots.dart';

final class TraceRetentionStore {
  TraceRetentionStore({
    required this.maxRuns,
    required this.maxEventsPerRun,
    required this.maxNodesPerRun,
    required this.maxEdgesPerRun,
  }) {
    if ([
      maxRuns,
      maxEventsPerRun,
      maxNodesPerRun,
      maxEdgesPerRun,
    ].any((value) => value < 1)) {
      throw ArgumentError('Trace retention limits must be positive.');
    }
  }
  final int maxRuns, maxEventsPerRun, maxNodesPerRun, maxEdgesPerRun;
  bool contains(String id) => _runs.containsKey(id);
  final Map<String, _TraceRunState> _runs = {};
  List<ExecutionTraceRunSnapshot> get snapshots => [
    for (final run in _runs.values) run.snapshot(),
  ];
  ExecutionTraceRunSnapshot? snapshotFor(String id) => _runs[id]?.snapshot();
  void create(ExecutionTraceRunInfo info) {
    _runs[info.executionId] = _TraceRunState(
      info,
      maxEventsPerRun,
      maxNodesPerRun,
      maxEdgesPerRun,
    );
  }

  int nextSequence(String id) => _runs[id]?._nextSequence() ?? 0;
  bool accept(ExecutionTraceEvent event) {
    final run = _runs[event.executionId];
    if (run == null) return false;
    run.accept(event);
    while (_runs.length > maxRuns) {
      final removable = _runs.values.firstWhere(
        (run) => run.info.status != ExecutionTraceRunStatus.running,
        orElse: () => _runs.values.first,
      );
      _runs.remove(removable.info.executionId);
    }
    return true;
  }

  void clear() => _runs.clear();
}

final class _TraceRunState {
  _TraceRunState(this.info, this.maxEventsPerRun, this.maxNodes, this.maxEdges);

  ExecutionTraceRunInfo info;
  final int maxEventsPerRun, maxNodes, maxEdges;
  int droppedEvents = 0, evictedNodes = 0, evictedEdges = 0;
  final Queue<ExecutionTraceEvent> events = Queue();
  final Map<String, _TraceNodeState> nodes = {};
  final Map<String, int> activeCounts = {}, invocationTotals = {};
  final Map<String, ExecutionTraceEdgeSnapshot> edges = {};
  int sequence = 0;

  int _nextSequence() => sequence++;

  void accept(ExecutionTraceEvent event) {
    switch (event) {
      case ExecutionNodeStartedEvent(:final node, :final invocation):
        activeCounts.update(node.key, (value) => value + 1, ifAbsent: () => 1);
        final previous = invocationTotals[node.key] ?? 0;
        invocationTotals[node.key] = invocation > previous
            ? invocation
            : previous;
      case ExecutionNodeCompletedEvent(:final node) ||
          ExecutionNodeFailedEvent(:final node):
        activeCounts.update(
          node.key,
          (value) => value > 0 ? value - 1 : 0,
          ifAbsent: () => 0,
        );
      case ExecutionRunEndedEvent():
        break;
      case ExecutionEdgeTraversedEvent(:final edge):
        final key = jsonEncode([edge.from.key, edge.edgeId]);
        edges[key] = ExecutionTraceEdgeSnapshot(
          edge,
          (edges[key]?.traversalCount ?? 0) + 1,
        );
      default:
        break;
    }
    events.add(event);
    if (events.length > maxEventsPerRun) {
      events.removeFirst();
      droppedEvents++;
    }
    switch (event) {
      case ExecutionRunStartedEvent():
        info = info.copyWith(status: ExecutionTraceRunStatus.running);
      case ExecutionRunEndedEvent(:final status, :final error):
        info = info.copyWith(
          status: status,
          endedAt: event.timestamp,
          error: error,
        );
        for (final entry in nodes.entries.toList()) {
          final previous = entry.value;
          if (previous.status != ExecutionTraceNodeStatus.running &&
              (activeCounts[entry.key] ?? 0) == 0) {
            continue;
          }
          nodes[entry.key] = _TraceNodeState(
            node: previous.node,
            status: status == ExecutionTraceRunStatus.aborted
                ? ExecutionTraceNodeStatus.aborted
                : status == ExecutionTraceRunStatus.completed
                ? ExecutionTraceNodeStatus.success
                : ExecutionTraceNodeStatus.error,
            invocationCount: previous.invocationCount,
            startedAt: previous.startedAt,
            duration: previous.startedAt == null
                ? null
                : event.timestamp.difference(previous.startedAt!),
            error: error,
            resultPreview: previous.resultPreview,
            selectedPort: previous.selectedPort,
            lastIteration: previous.lastIteration,
            subgraphId: previous.subgraphId,
          );
        }
      case ExecutionNodeStartedEvent(:final node, :final invocation):
        nodes[node.key] = _TraceNodeState(
          node: node,
          status: ExecutionTraceNodeStatus.running,
          invocationCount: invocation,
          startedAt: event.timestamp,
        );
      case ExecutionNodeCompletedEvent(
        :final node,
        :final invocation,
        :final duration,
      ):
        final previous = nodes[node.key];
        nodes[node.key] = _TraceNodeState(
          node: node,
          status: ExecutionTraceNodeStatus.success,
          invocationCount: invocation,
          startedAt: previous?.startedAt,
          duration: duration,
          error: previous?.error,
          resultPreview: previous?.resultPreview,
          selectedPort: previous?.selectedPort,
          lastIteration: previous?.lastIteration,
          subgraphId: previous?.subgraphId,
        );
      case ExecutionNodeFailedEvent(
        :final node,
        :final invocation,
        :final duration,
        :final error,
      ):
        final previous = nodes[node.key];
        nodes[node.key] = _TraceNodeState(
          node: node,
          status: ExecutionTraceNodeStatus.error,
          invocationCount: invocation,
          startedAt: previous?.startedAt,
          duration: duration,
          error: error,
          resultPreview: previous?.resultPreview,
          selectedPort: previous?.selectedPort,
          lastIteration: previous?.lastIteration,
          subgraphId: previous?.subgraphId,
        );
      case ExecutionNodeResultEvent(
        :final node,
        :final invocation,
        :final preview,
      ):
        final previous = nodes[node.key];
        nodes[node.key] = _TraceNodeState(
          node: node,
          status: previous?.status ?? ExecutionTraceNodeStatus.running,
          invocationCount: invocation,
          startedAt: previous?.startedAt,
          duration: previous?.duration,
          error: previous?.error,
          resultPreview: preview,
          selectedPort: previous?.selectedPort,
          lastIteration: previous?.lastIteration,
          subgraphId: previous?.subgraphId,
        );
      case ExecutionControlPathEvent(
        :final node,
        :final port,
        :final iteration,
      ):
        final previous = nodes[node.key];
        nodes[node.key] = _TraceNodeState(
          node: node,
          status: previous?.status ?? ExecutionTraceNodeStatus.running,
          invocationCount: previous?.invocationCount ?? 1,
          startedAt: previous?.startedAt,
          duration: previous?.duration,
          error: previous?.error,
          resultPreview: previous?.resultPreview,
          selectedPort: port,
          lastIteration: iteration ?? previous?.lastIteration,
          subgraphId: previous?.subgraphId,
        );
      case ExecutionLoopIterationEvent(:final node, :final iteration):
        final previous = nodes[node.key];
        nodes[node.key] = _TraceNodeState(
          node: node,
          status: previous?.status ?? ExecutionTraceNodeStatus.running,
          invocationCount: previous?.invocationCount ?? 1,
          startedAt: previous?.startedAt,
          duration: previous?.duration,
          error: previous?.error,
          resultPreview: previous?.resultPreview,
          selectedPort: previous?.selectedPort,
          lastIteration: iteration,
          subgraphId: previous?.subgraphId,
        );
      case ExecutionSubgraphEnteredEvent(:final callNode, :final subgraphId):
        final previous = nodes[callNode.key];
        nodes[callNode.key] = _TraceNodeState(
          node: callNode,
          status: ExecutionTraceNodeStatus.running,
          invocationCount: previous?.invocationCount ?? 1,
          startedAt: previous?.startedAt ?? event.timestamp,
          duration: previous?.duration,
          error: previous?.error,
          resultPreview: previous?.resultPreview,
          selectedPort: previous?.selectedPort,
          lastIteration: previous?.lastIteration,
          subgraphId: subgraphId,
        );
      case ExecutionSubgraphExitedEvent(
        :final callNode,
        :final subgraphId,
        :final duration,
      ):
        final previous = nodes[callNode.key];
        nodes[callNode.key] = _TraceNodeState(
          node: callNode,
          status: ExecutionTraceNodeStatus.success,
          invocationCount: previous?.invocationCount ?? 1,
          startedAt: previous?.startedAt,
          duration: duration,
          error: previous?.error,
          resultPreview: previous?.resultPreview,
          selectedPort: previous?.selectedPort,
          lastIteration: previous?.lastIteration,
          subgraphId: subgraphId,
        );
      case ExecutionEdgeTraversedEvent():
        break;
    }
    while (nodes.length > maxNodes) {
      final key = nodes.keys.first;
      nodes.remove(key);
      activeCounts.remove(key);
      invocationTotals.remove(key);
      evictedNodes++;
    }
    while (edges.length > maxEdges) {
      edges.remove(edges.keys.first);
      evictedEdges++;
    }
    if (event is ExecutionRunEndedEvent) activeCounts.clear();
  }

  ExecutionTraceRunSnapshot snapshot() => ExecutionTraceRunSnapshot(
    info: info,
    events: List.unmodifiable(events),
    nodes: Map.unmodifiable({
      for (final entry in nodes.entries)
        entry.key: entry.value.snapshot(
          activeCount: activeCounts[entry.key] ?? 0,
          invocationCount: invocationTotals[entry.key],
        ),
    }),
    edges: Map.unmodifiable(edges),
    droppedEventCount: droppedEvents,
    evictedNodeCount: evictedNodes,
    evictedEdgeCount: evictedEdges,
  );
}

final class _TraceNodeState {
  _TraceNodeState({
    required this.node,
    required this.status,
    required this.invocationCount,
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
  final DateTime? startedAt;
  final Duration? duration;
  final ExecutionTraceError? error;
  final Object? resultPreview;
  final String? selectedPort;
  final int? lastIteration;
  final String? subgraphId;

  ExecutionTraceNodeSnapshot snapshot({
    required int activeCount,
    int? invocationCount,
  }) => ExecutionTraceNodeSnapshot(
    node: node,
    status: activeCount > 0 ? ExecutionTraceNodeStatus.running : status,
    activeCount: activeCount,
    invocationCount: invocationCount ?? this.invocationCount,
    startedAt: startedAt,
    duration: duration,
    error: error,
    resultPreview: resultPreview,
    selectedPort: selectedPort,
    lastIteration: lastIteration,
    subgraphId: subgraphId,
  );
}
