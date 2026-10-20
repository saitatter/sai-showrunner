import '../graph/domain/automation_document.dart';
import 'execution_trace.dart';
import 'expression.dart';
import 'runtime_snapshot.dart';

/// Typed runtime ownership; toWire/fromWire retain the existing queue persistence
/// envelope. Trace metadata can never replace the captured automation document.
final class QueuedAutomationSource {
  QueuedAutomationSource({
    required this.document,
    required this.queueId,
    required this.queueName,
    this.entryNodeId,
    this.entrySpaceId,
    RuntimeMap metadata = const {},
  }) : metadata = freezeRuntimeMap(metadata) {
    if (metadata.keys.any(_owned.contains)) {
      throw ArgumentError(
        'Queue source metadata contains an owned snapshot field.',
      );
    }
  }
  static const _owned = {
    'automation',
    'queueId',
    'queueName',
    'name',
    'entryNodeId',
    'entrySpaceId',
  };
  final AutomationDocument document;
  final String queueId, queueName;
  final String? entryNodeId, entrySpaceId;
  final RuntimeMap metadata;
  ExecutionTraceSource get trace => ExecutionTraceSource.fromMetadata({
    ...metadata,
    'queueId': queueId,
    'queueName': queueName,
    'documentId': document.id,
  });
  RuntimeMap toWire() => freezeRuntimeMap({
    'automation': document.toJson(),
    ...metadata,
    'queueId': queueId,
    'queueName': queueName,
    'name': document.metadata['name'] ?? 'Queued automation',
    'entryNodeId': ?entryNodeId,
    'entrySpaceId': ?entrySpaceId,
  });
  factory QueuedAutomationSource.fromWire(RuntimeMap value) {
    final raw = value['automation'];
    if (raw is! Map) {
      throw const FormatException('Queued automation snapshot is missing.');
    }
    return QueuedAutomationSource(
      document: AutomationDocument.fromJson(Map<String, Object?>.from(raw)),
      queueId: value['queueId'] as String? ?? 'default',
      queueName: value['queueName'] as String? ?? 'Default',
      entryNodeId: value['entryNodeId'] as String?,
      entrySpaceId: value['entrySpaceId'] as String?,
      metadata: {
        for (final entry in value.entries)
          if (!_owned.contains(entry.key)) entry.key: entry.value,
      },
    );
  }
}
