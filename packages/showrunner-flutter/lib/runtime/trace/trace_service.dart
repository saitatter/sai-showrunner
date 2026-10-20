import 'trace_updates.dart';
import 'dart:async';
import 'trace_models.dart';
import 'trace_events.dart';
import 'trace_snapshots.dart';
import 'trace_session.dart';
import 'trace_retention.dart';

final class ExecutionTraceService {
  ExecutionTraceService({
    this.maxRuns = 32,
    this.maxEventsPerRun = 512,
    this.maxNodesPerRun = 1024,
    this.maxEdgesPerRun = 2048,
  }) : _store = TraceRetentionStore(
         maxRuns: maxRuns,
         maxEventsPerRun: maxEventsPerRun,
         maxNodesPerRun: maxNodesPerRun,
         maxEdgesPerRun: maxEdgesPerRun,
       );

  final int maxRuns;
  final int maxEventsPerRun, maxNodesPerRun, maxEdgesPerRun;
  final TraceUpdateStream _events = TraceUpdateStream();
  int get coalescedNotifications => _events.coalesced;
  final TraceRetentionStore _store;
  int _counter = 0;
  bool _disposed = false;

  Stream<ExecutionTraceEvent> get events => _events;

  List<ExecutionTraceRunSnapshot> get snapshots => _store.snapshots;

  List<ExecutionTraceRunSnapshot> snapshotsFor(ExecutionTraceSource source) =>
      snapshots
          .where((snapshot) => source.matches(snapshot.info.source))
          .toList(growable: false);

  ExecutionTraceRunSnapshot? snapshotFor(String executionId) =>
      _store.snapshotFor(executionId);

  List<ExecutionTraceRunSnapshot> activeFor(ExecutionTraceSource source) =>
      snapshots
          .where(
            (snapshot) =>
                source.matches(snapshot.info.source) &&
                snapshot.info.status == ExecutionTraceRunStatus.running,
          )
          .toList(growable: false);

  ExecutionTraceSession start({
    required ExecutionTraceMode mode,
    required ExecutionTraceSource source,
  }) {
    if (_disposed) throw StateError('Execution trace service is disposed.');
    final id =
        'execution-${DateTime.now().microsecondsSinceEpoch}-${_counter++}';
    final now = DateTime.now();
    final info = ExecutionTraceRunInfo(
      executionId: id,
      mode: mode,
      source: source,
      status: ExecutionTraceRunStatus.running,
      startedAt: now,
    );
    _store.create(info);
    final session = ExecutionTraceSession(
      publish: _publish,
      nextSequence: _nextSequence,
      info: info,
      maxNodes: maxNodesPerRun,
      isRetained: (id) => !_disposed && _store.contains(id),
    );
    _publish(
      ExecutionRunStartedEvent(
        executionId: id,
        seq: _nextSequence(id),
        timestamp: now,
        mode: mode,
        source: source,
      ),
    );
    return session;
  }

  int _nextSequence(String executionId) => _store.nextSequence(executionId);
  void _publish(ExecutionTraceEvent event) {
    if (!_disposed && _store.accept(event)) _events.add(event);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _events.close();
    _store.clear();
  }
}
