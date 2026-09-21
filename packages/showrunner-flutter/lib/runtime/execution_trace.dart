import 'dart:async';
import 'dart:convert';

import 'cancellation.dart';

enum ExecutionTraceMode { live, test }

enum ExecutionTraceRunStatus { starting, running, completed, aborted, error }

enum ExecutionTraceNodeStatus { running, success, error, aborted }

sealed class ExecutionGraphScope {
  const ExecutionGraphScope();

  const factory ExecutionGraphScope.main() = MainGraphScope;
  const factory ExecutionGraphScope.subgraph(String id) = SubgraphScope;

  Map<String, Object?> toJson();
}

final class MainGraphScope extends ExecutionGraphScope {
  const MainGraphScope();

  @override
  Map<String, Object?> toJson() => const {'type': 'main'};
}

final class SubgraphScope extends ExecutionGraphScope {
  const SubgraphScope(this.id);

  final String id;

  @override
  Map<String, Object?> toJson() => {'type': 'subgraph', 'subgraphId': id};
}

final class ExecutionTraceSource {
  const ExecutionTraceSource({
    required this.type,
    required this.id,
    this.subId,
  });

  final String type;
  final String id;
  final String? subId;

  factory ExecutionTraceSource.fromMetadata(Map value) => ExecutionTraceSource(
    type: value['sourceType']?.toString() ?? 'automation',
    id: value['sourceId']?.toString() ?? '',
    subId: value['sourceSubId']?.toString(),
  );

  Map<String, Object?> toJson() => {
    'type': type,
    'id': id,
    if (subId != null && subId!.isNotEmpty) 'subId': subId,
  };

  bool matches(ExecutionTraceSource other) =>
      type == other.type &&
      id == other.id &&
      (subId == null || subId!.isEmpty || subId == other.subId);

  @override
  String toString() => '$type:$id${subId == null ? '' : ':$subId'}';
}

final class ExecutionNodeRef {
  const ExecutionNodeRef({
    required this.nodeId,
    this.scope = const MainGraphScope(),
  });

  final String nodeId;
  final ExecutionGraphScope scope;

  String get key =>
      '${scope is SubgraphScope ? (scope as SubgraphScope).id : 'main'}:$nodeId';

  Map<String, Object?> toJson() => {
    'nodeId': nodeId,
    'graphScope': scope.toJson(),
  };
}

final class ExecutionEdgeRef {
  const ExecutionEdgeRef({
    required this.edgeId,
    required this.from,
    required this.to,
    this.port,
  });

  final String edgeId;
  final ExecutionNodeRef from;
  final ExecutionNodeRef to;
  final String? port;

  Map<String, Object?> toJson() => {
    'edgeId': edgeId,
    'from': from.toJson(),
    'to': to.toJson(),
    if (port != null) 'port': port,
  };
}

final class ExecutionTraceError {
  const ExecutionTraceError({this.name, required this.message, this.stack});

  final String? name;
  final String message;
  final String? stack;

  factory ExecutionTraceError.fromObject(Object error, [StackTrace? trace]) =>
      ExecutionTraceError(
        name: error.runtimeType.toString(),
        message: _boundedString(error.toString(), 4096),
        stack: trace == null ? null : _boundedString(trace.toString(), 8192),
      );

  Map<String, Object?> toJson() => {
    if (name != null) 'name': name,
    'message': message,
    if (stack != null) 'stack': stack,
  };

  @override
  String toString() => message;
}

final class ExecutionTraceRunInfo {
  const ExecutionTraceRunInfo({
    required this.executionId,
    required this.mode,
    required this.source,
    required this.status,
    required this.startedAt,
    this.endedAt,
    this.error,
  });

  final String executionId;
  final ExecutionTraceMode mode;
  final ExecutionTraceSource source;
  final ExecutionTraceRunStatus status;
  final DateTime startedAt;
  final DateTime? endedAt;
  final ExecutionTraceError? error;

  Duration? get duration => endedAt?.difference(startedAt);

  ExecutionTraceRunInfo copyWith({
    ExecutionTraceRunStatus? status,
    DateTime? endedAt,
    ExecutionTraceError? error,
  }) => ExecutionTraceRunInfo(
    executionId: executionId,
    mode: mode,
    source: source,
    status: status ?? this.status,
    startedAt: startedAt,
    endedAt: endedAt ?? this.endedAt,
    error: error ?? this.error,
  );

  Map<String, Object?> toJson() => {
    'executionId': executionId,
    'mode': mode.name,
    'source': source.toJson(),
    'status': status.name,
    'startedAt': startedAt.millisecondsSinceEpoch,
    if (endedAt != null) 'endedAt': endedAt!.millisecondsSinceEpoch,
    if (error != null) 'error': error!.toJson(),
  };
}

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

final class ExecutionTraceNodeSnapshot {
  const ExecutionTraceNodeSnapshot({
    required this.node,
    required this.status,
    required this.invocationCount,
    this.startedAt,
    this.duration,
    this.error,
    this.resultPreview,
  });

  final ExecutionNodeRef node;
  final ExecutionTraceNodeStatus status;
  final int invocationCount;
  final DateTime? startedAt;
  final Duration? duration;
  final ExecutionTraceError? error;
  final Object? resultPreview;
}

final class ExecutionTraceRunSnapshot {
  const ExecutionTraceRunSnapshot({
    required this.info,
    required this.events,
    required this.nodes,
  });

  final ExecutionTraceRunInfo info;
  final List<ExecutionTraceEvent> events;
  final Map<String, ExecutionTraceNodeSnapshot> nodes;
}

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
  void edgeTraversed(ExecutionEdgeRef edge);
  void loopIteration(ExecutionNodeRef node, int iteration);
  void end(
    ExecutionTraceRunStatus status, {
    Object? error,
    StackTrace? stackTrace,
  });
}

final class ExecutionTraceSession implements ExecutionTraceSink {
  ExecutionTraceSession._({required this.service, required this.info})
    : _started = info.startedAt;

  final ExecutionTraceService service;
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
    service._publish(
      ExecutionNodeStartedEvent(
        executionId: executionId,
        seq: service._nextSequence(executionId),
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
    service._publish(
      ExecutionNodeCompletedEvent(
        executionId: executionId,
        seq: service._nextSequence(executionId),
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
    service._publish(
      ExecutionNodeFailedEvent(
        executionId: executionId,
        seq: service._nextSequence(executionId),
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
    service._publish(
      ExecutionNodeResultEvent(
        executionId: executionId,
        seq: service._nextSequence(executionId),
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
  void edgeTraversed(ExecutionEdgeRef edge) {
    if (_ended) return;
    service._publish(
      ExecutionEdgeTraversedEvent(
        executionId: executionId,
        seq: service._nextSequence(executionId),
        timestamp: DateTime.now(),
        mode: info.mode,
        edge: edge,
      ),
    );
  }

  @override
  void loopIteration(ExecutionNodeRef node, int iteration) {
    if (_ended) return;
    service._publish(
      ExecutionLoopIterationEvent(
        executionId: executionId,
        seq: service._nextSequence(executionId),
        timestamp: DateTime.now(),
        mode: info.mode,
        node: node,
        iteration: iteration,
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
    service._publish(
      ExecutionRunEndedEvent(
        executionId: executionId,
        seq: service._nextSequence(executionId),
        timestamp: DateTime.now(),
        mode: info.mode,
        status: status,
        duration: DateTime.now().difference(_started),
        error: traceError,
      ),
    );
  }
}

final class ExecutionTraceService {
  ExecutionTraceService({this.maxRuns = 32, this.maxEventsPerRun = 512});

  final int maxRuns;
  final int maxEventsPerRun;
  final StreamController<ExecutionTraceEvent> _events =
      StreamController<ExecutionTraceEvent>.broadcast();
  final Map<String, _TraceRunState> _runs = {};
  int _counter = 0;
  bool _disposed = false;

  Stream<ExecutionTraceEvent> get events => _events.stream;

  List<ExecutionTraceRunSnapshot> get snapshots => [
    for (final run in _runs.values) run.snapshot(),
  ];

  ExecutionTraceRunSnapshot? snapshotFor(String executionId) =>
      _runs[executionId]?.snapshot();

  List<ExecutionTraceRunSnapshot> activeFor(ExecutionTraceSource source) =>
      snapshots
          .where(
            (snapshot) =>
                snapshot.info.source.matches(source) &&
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
    _runs[id] = _TraceRunState(info, maxEventsPerRun);
    final session = ExecutionTraceSession._(service: this, info: info);
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

  int _nextSequence(String executionId) =>
      _runs[executionId]?._nextSequence() ?? 0;

  void _publish(ExecutionTraceEvent event) {
    final run = _runs[event.executionId];
    if (run == null) return;
    run.accept(event);
    if (!_events.isClosed) _events.add(event);
    _trimRuns();
  }

  void _trimRuns() {
    while (_runs.length > maxRuns) {
      final removable = _runs.values.firstWhere(
        (run) => run.info.status != ExecutionTraceRunStatus.running,
        orElse: () => _runs.values.first,
      );
      _runs.remove(removable.info.executionId);
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _events.close();
    _runs.clear();
  }
}

final class _TraceRunState {
  _TraceRunState(this.info, this.maxEventsPerRun);

  ExecutionTraceRunInfo info;
  final int maxEventsPerRun;
  final List<ExecutionTraceEvent> events = [];
  final Map<String, _TraceNodeState> nodes = {};
  int sequence = 0;

  int _nextSequence() => sequence++;

  void accept(ExecutionTraceEvent event) {
    events.add(event);
    if (events.length > maxEventsPerRun) events.removeAt(0);
    switch (event) {
      case ExecutionRunStartedEvent():
        info = info.copyWith(status: ExecutionTraceRunStatus.running);
      case ExecutionRunEndedEvent(:final status, :final error):
        info = info.copyWith(
          status: status,
          endedAt: event.timestamp,
          error: error,
        );
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
        );
      case ExecutionEdgeTraversedEvent():
      case ExecutionLoopIterationEvent():
        break;
    }
  }

  ExecutionTraceRunSnapshot snapshot() => ExecutionTraceRunSnapshot(
    info: info,
    events: List.unmodifiable(events),
    nodes: {
      for (final entry in nodes.entries) entry.key: entry.value.snapshot(),
    },
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
  });

  final ExecutionNodeRef node;
  final ExecutionTraceNodeStatus status;
  final int invocationCount;
  final DateTime? startedAt;
  final Duration? duration;
  final ExecutionTraceError? error;
  final Object? resultPreview;

  ExecutionTraceNodeSnapshot snapshot() => ExecutionTraceNodeSnapshot(
    node: node,
    status: status,
    invocationCount: invocationCount,
    startedAt: startedAt,
    duration: duration,
    error: error,
    resultPreview: resultPreview,
  );
}

final class SanitizedExecutionResult {
  const SanitizedExecutionResult(this.value, this.truncated);

  final Object? value;
  final bool truncated;
}

SanitizedExecutionResult sanitizeExecutionResult(Object? value) {
  final sanitized = _sanitize(value, depth: 0);
  try {
    final encoded = jsonEncode(sanitized.value);
    if (encoded.length <= 16 * 1024) return sanitized;
    return SanitizedExecutionResult(_boundedString(encoded, 16 * 1024), true);
  } on Object {
    return const SanitizedExecutionResult('<unserializable result>', true);
  }
}

SanitizedExecutionResult _sanitize(Object? value, {required int depth}) {
  if (value == null || value is num || value is bool) {
    return SanitizedExecutionResult(value, false);
  }
  if (value is String) {
    final truncated = value.length > 4096;
    return SanitizedExecutionResult(_boundedString(value, 4096), truncated);
  }
  if (depth >= 5) return const SanitizedExecutionResult('<max depth>', true);
  if (value is Map) {
    final result = <String, Object?>{};
    var truncated = false;
    for (final entry in value.entries.take(100)) {
      final item = _sanitize(entry.value, depth: depth + 1);
      result[entry.key.toString()] = item.value;
      truncated = truncated || item.truncated;
    }
    if (value.length > 100) truncated = true;
    return SanitizedExecutionResult(result, truncated);
  }
  if (value is Iterable) {
    final result = <Object?>[];
    var truncated = false;
    for (final item in value.take(50)) {
      final sanitized = _sanitize(item, depth: depth + 1);
      result.add(sanitized.value);
      truncated = truncated || sanitized.truncated;
    }
    if (value.length > 50) truncated = true;
    return SanitizedExecutionResult(result, truncated);
  }
  return SanitizedExecutionResult(_boundedString(value.toString(), 4096), true);
}

String _boundedString(String value, int limit) =>
    value.length <= limit ? value : '${value.substring(0, limit)}…';

ExecutionTraceRunStatus traceStatusForError(Object error) =>
    error is DartCancelledException
    ? ExecutionTraceRunStatus.aborted
    : ExecutionTraceRunStatus.error;
