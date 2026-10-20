import 'dart:convert';
import '../cancellation.dart';
import 'trace_redaction.dart';

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
    this.queueId,
    this.queueName,
    this.itemId,
    this.documentId,
  });

  final String type;
  final String id;
  final String? subId;
  final String? queueId;
  final String? queueName;
  final String? itemId;
  final String? documentId;

  factory ExecutionTraceSource.fromMetadata(Map value) => ExecutionTraceSource(
    type: value['sourceType']?.toString() ?? 'automation',
    id: value['sourceId']?.toString() ?? '',
    subId: value['sourceSubId']?.toString(),
    queueId: value['queueId']?.toString(),
    queueName: value['queueName']?.toString(),
    itemId: value['itemId']?.toString(),
    documentId: value['documentId']?.toString(),
  );

  Map<String, Object?> toJson() => {
    'type': type,
    'id': id,
    if (subId != null && subId!.isNotEmpty) 'subId': subId,
    if (queueId != null && queueId!.isNotEmpty) 'queueId': queueId,
    if (queueName != null && queueName!.isNotEmpty) 'queueName': queueName,
    if (itemId != null && itemId!.isNotEmpty) 'itemId': itemId,
    if (documentId != null) 'documentId': documentId,
  };

  bool matches(ExecutionTraceSource other) =>
      type == other.type &&
      id == other.id &&
      (documentId == null || documentId == other.documentId) &&
      (subId == null || subId!.isEmpty || subId == other.subId);

  ExecutionTraceSource withDocumentId(String value) => ExecutionTraceSource(
    type: type,
    id: id,
    subId: subId,
    queueId: queueId,
    queueName: queueName,
    itemId: itemId,
    documentId: value,
  );

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

  String get key => jsonEncode([
    scope is SubgraphScope ? 'subgraph' : 'main',
    scope is SubgraphScope ? (scope as SubgraphScope).id : null,
    nodeId,
  ]);

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
        message: safeTraceErrorMessage(error),
        // Runtime exception text and stack can contain private values/paths.
        // The original error remains at the invocation/application boundary.
        stack: null,
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

ExecutionTraceRunStatus traceStatusForError(Object error) =>
    error is DartCancelledException
    ? ExecutionTraceRunStatus.aborted
    : ExecutionTraceRunStatus.error;
