import 'dart:async';

import 'package:sai_nodes_core/sai_nodes_core.dart';

import '../../runtime/execution_trace.dart';
import '../domain/automation_document.dart';

/// Projects trace state onto original document IDs. It never owns authoring
/// state or invokes actions, and can display retained runs after execution ends.
final class ShowrunnerExecutionVisualAdapter
    implements GraphExecutionVisualSource {
  ShowrunnerExecutionVisualAdapter({
    required this.service,
    required this._source,
    this.documentId,
  }) {
    _subscription = service.events.listen((_) => _refresh());
    _refresh();
  }
  final ExecutionTraceService service;
  late final StreamSubscription<ExecutionTraceEvent> _subscription;
  final GraphExecutionVisualController _visuals =
      GraphExecutionVisualController();
  ExecutionTraceSource _source;
  final String? documentId;
  String? _pinnedId;
  bool _disposed = false;
  String? get pinnedExecutionId => _pinnedId;
  List<ExecutionTraceRunSnapshot> get runs =>
      (documentId == null
            ? service.snapshotsFor(_source)
            : service.snapshots
                  .where((run) => run.info.source.documentId == documentId)
                  .toList())
        ..sort((a, b) => b.info.startedAt.compareTo(a.info.startedAt));
  @override
  GraphExecutionSnapshot get snapshot => _visuals.snapshot;
  void setSource(ExecutionTraceSource source) {
    _source = source;
    _pinnedId = null;
    _refresh();
  }

  void pin(String? executionId) {
    _pinnedId = executionId;
    _refresh();
  }

  void _refresh() {
    if (_disposed) return;
    final available = runs;
    final pinned = _pinnedId == null
        ? null
        : available
              .where((run) => run.info.executionId == _pinnedId)
              .firstOrNull;
    final active = available
        .where(
          (run) =>
              run.info.status == ExecutionTraceRunStatus.running ||
              run.info.status == ExecutionTraceRunStatus.starting,
        )
        .toList();
    final selected = _pinnedId != null
        ? [?pinned]
        : active.isNotEmpty
        ? active
        : available.take(1).toList();
    final nodes = <ScopedNodeRef, NodeExecutionVisual>{};
    final connections = <ScopedConnectionRef, ConnectionExecutionVisual>{};
    for (final run in selected) {
      for (final state in run.nodes.values) {
        final key = ScopedNodeRef(_space(state.node.scope), state.node.nodeId);
        final previous = nodes[key];
        final status = switch (state.status) {
          ExecutionTraceNodeStatus.running => GraphExecutionStatus.running,
          ExecutionTraceNodeStatus.success => GraphExecutionStatus.completed,
          ExecutionTraceNodeStatus.error => GraphExecutionStatus.error,
          ExecutionTraceNodeStatus.aborted => GraphExecutionStatus.aborted,
        };
        final activeCount = state.activeCount;
        nodes[key] = NodeExecutionVisual(
          status:
              previous == null || _priority(status) > _priority(previous.status)
              ? status
              : previous.status,
          activeCount: (previous?.activeCount ?? 0) + activeCount,
          invocationCount:
              (previous?.invocationCount ?? 0) + state.invocationCount,
          duration:
              (previous?.duration ?? Duration.zero) +
              (state.duration ?? Duration.zero),
          error: state.error?.message ?? previous?.error,
          metadata: {
            ...?previous?.metadata,
            if (state.resultPreview != null)
              'resultPreview': state.resultPreview,
            if (state.selectedPort != null) 'selectedPort': state.selectedPort,
            if (state.lastIteration != null)
              'lastIteration': state.lastIteration,
            if (state.subgraphId != null) 'subgraphId': state.subgraphId,
          },
        );
      }
      for (final state in run.edges.values) {
        final edge = state.edge;
        final key = ScopedConnectionRef(_space(edge.from.scope), edge.edgeId);
        final previous = connections[key];
        connections[key] = ConnectionExecutionVisual(
          active:
              (previous?.active ?? false) ||
              (run.info.status == ExecutionTraceRunStatus.running &&
                  (run.nodes[edge.to.key]?.activeCount ?? 0) > 0),
          traversalCount:
              (previous?.traversalCount ?? 0) + state.traversalCount,
        );
      }
    }
    _visuals.apply(
      GraphExecutionSnapshot(
        nodes: nodes,
        connections: connections,
        executionId: selected.length == 1
            ? selected.single.info.executionId
            : null,
      ),
    );
  }

  @override
  void addListener(void Function() listener) => _visuals.addListener(listener);
  @override
  void removeListener(void Function() listener) =>
      _visuals.removeListener(listener);
  void dispose() {
    _disposed = true;
    unawaited(_subscription.cancel());
    _visuals.dispose();
  }
}

String _space(ExecutionGraphScope scope) => switch (scope) {
  MainGraphScope() => mainAutomationSpace,
  SubgraphScope(:final id) => 'space:subgraph:$id',
};
int _priority(GraphExecutionStatus status) => switch (status) {
  GraphExecutionStatus.running => 5,
  GraphExecutionStatus.error => 4,
  GraphExecutionStatus.aborted => 3,
  GraphExecutionStatus.queued => 2,
  GraphExecutionStatus.completed => 1,
  GraphExecutionStatus.idle => 0,
};
