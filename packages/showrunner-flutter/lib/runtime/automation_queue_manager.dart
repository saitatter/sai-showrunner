import 'dart:async';

import '../domain/errors/showrunner_error.dart';
import '../schema/automation.dart';
import '../schema/queue.dart';
import 'action_queue.dart';
import 'expression.dart';

typedef DartQueuedAutomationExecutor =
    Future<Object?> Function(
      AutomationData automation,
      EvaluationContext context,
      QueuedGraphExecution item,
    );

typedef DartQueueConfigLoader = Future<QueueConfig?> Function(String queueId);

/// Coordinates the resource-backed action queues used by automation runtime.
///
/// A queue is deliberately separate from the graph runtime: it owns ordering,
/// pause/gap/timeout policy and history, while the executor owns graph
/// execution and provider dependencies. This mirrors the reference runtime's
/// ActionQueue/ActionQueueManager boundary without putting persistence or
/// plugin singletons into graph code.
final class DartAutomationQueueManager {
  DartAutomationQueueManager({
    required DartActionQueue defaultQueue,
    required this.execute,
    this.loadConfig,
  }) : _queues = {'default': defaultQueue};

  final DartQueuedAutomationExecutor execute;
  final DartQueueConfigLoader? loadConfig;
  final Map<String, DartActionQueue> _queues;
  final Map<String, Future<DartActionQueue>> _queueLoads = {};
  final Map<String, Future<void>> _drains = {};
  bool _disposed = false;

  DartActionQueue get defaultQueue => _queues['default']!;

  Iterable<String> get queueIds => _queues.keys;

  DartActionQueue? registeredQueue(String queueId) => _queues[_key(queueId)];

  void register(String queueId, DartActionQueue queue) {
    _ensureOpen();
    final key = _key(queueId);
    if (key.isEmpty || key == 'default') {
      throw ArgumentError.value(queueId, 'queueId');
    }
    final previous = _queues[key];
    if (previous != null && !identical(previous, queue)) {
      throw ArgumentError('Queue is registered more than once: $queueId');
    }
    _queues[key] = queue;
  }

  Future<DartActionQueue> queueFor(String? queueId) {
    _ensureOpen();
    final key = _key(queueId);
    if (key.isEmpty || key == 'default') return Future.value(defaultQueue);
    final existing = _queues[key];
    if (existing != null) return Future.value(existing);
    return _queueLoads[key] ??= _loadQueue(key);
  }

  Future<QueuedGraphExecution> enqueue(
    AutomationData automation,
    EvaluationContext context, {
    String? queueId,
  }) async {
    final queueKey = _key(queueId);
    final queue = await queueFor(queueKey);
    final source = automation.toJson();
    final name = source['name']?.toString();
    if (name == null || name.trim().isEmpty) {
      source['name'] = 'Queued automation';
    }
    final item = queue.enqueue(
      source,
      context.contextState,
      locals: context.locals,
    );
    unawaited(drain(queueKey));
    return item;
  }

  /// Drains one queue until it is paused or empty.
  ///
  /// Errors are retained on the queue item and do not prevent following queue
  /// items from being processed, matching the desktop queue behavior.
  Future<void> drain(String? queueId) async {
    final key = _key(queueId).isEmpty ? 'default' : _key(queueId);
    final existing = _drains[key];
    if (existing != null) return existing;
    final queue = await queueFor(key);
    final operation = _drainQueue(key, queue);
    _drains[key] = operation;
    try {
      await operation;
    } finally {
      if (identical(_drains[key], operation)) _drains.remove(key);
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await Future.wait(_queues.values.toSet().map((queue) => queue.dispose()));
    _queues.clear();
    _queueLoads.clear();
    _drains.clear();
  }

  Future<DartActionQueue> _loadQueue(String key) async {
    final config = await loadConfig?.call(key);
    if (config == null) {
      throw ResourceNotFoundError(
        technicalMessage: 'Action queue resource was not found: $key',
        userMessage: 'The automation references a queue that no longer exists.',
        operationId: key,
      );
    }
    final queue = DartActionQueue(
      defaultGap: config.gap,
      defaultTimeout: config.timeout,
    )..setPaused(config.paused);
    _queues[key] = queue;
    return queue;
  }

  Future<void> _drainQueue(String key, DartActionQueue queue) async {
    while (!_disposed && !queue.paused && queue.pending.isNotEmpty) {
      try {
        await queue.processNext((item) async {
          final automation = AutomationData.fromJson(item.source);
          return execute(
            automation,
            EvaluationContext(
              locals: item.locals,
              contextState: item.contextState,
            ),
            item,
          );
        }, timeout: queue.defaultTimeout);
      } catch (_) {
        // processNext has already recorded the failure. Continue with the
        // remaining queue items, just as the reference scheduler does.
      }
      if (!_disposed && !queue.paused && queue.pending.isNotEmpty) {
        final gap = queue.defaultGap;
        if (gap > Duration.zero) await Future<void>.delayed(gap);
      }
    }
  }

  String _key(String? queueId) {
    final value = queueId?.trim() ?? '';
    if (value.isEmpty || value == 'default') return value;
    return value.endsWith('.yaml')
        ? value.substring(0, value.length - 5)
        : value;
  }

  void _ensureOpen() {
    if (_disposed) throw StateError('Action queue manager is disposed.');
  }
}
