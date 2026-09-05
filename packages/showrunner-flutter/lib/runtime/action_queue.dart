import 'expression.dart';
import 'dart:async';
import 'dart:math';

import '../domain/errors/showrunner_error.dart';

final class QueuedGraphExecution {
  QueuedGraphExecution({
    required this.id,
    required this.source,
    required this.contextState,
    this.locals = const <String, dynamic>{},
    this.status = 'pending',
    this.startedAt,
    this.completedAt,
    this.error,
    this.errorCode,
    this.errorUserMessage,
    this.errorPluginId,
    this.errorOperationId,
    this.errorRetryable,
    this.reason,
  });

  final String id;
  final RuntimeMap source;
  final RuntimeMap contextState;
  final RuntimeMap locals;
  String status;
  DateTime? startedAt;
  DateTime? completedAt;
  String? error;
  String? errorCode;
  String? errorUserMessage;
  String? errorPluginId;
  String? errorOperationId;
  bool? errorRetryable;
  String? reason;

  Duration? get duration => startedAt == null || completedAt == null
      ? null
      : completedAt!.difference(startedAt!);

  RuntimeMap toJson() => {
    'id': id,
    'source': source,
    'contextState': contextState,
    if (locals.isNotEmpty) 'locals': locals,
    'status': status,
    if (startedAt != null) 'startedAt': startedAt!.toIso8601String(),
    if (completedAt != null) 'completedAt': completedAt!.toIso8601String(),
    if (error != null) 'error': error,
    if (errorCode != null) 'errorCode': errorCode,
    if (errorUserMessage != null) 'errorUserMessage': errorUserMessage,
    if (errorPluginId != null) 'errorPluginId': errorPluginId,
    if (errorOperationId != null) 'errorOperationId': errorOperationId,
    if (errorRetryable != null) 'errorRetryable': errorRetryable,
    if (reason != null) 'reason': reason,
  };

  static QueuedGraphExecution fromJson(Map value) => QueuedGraphExecution(
    id: value['id'].toString(),
    source: Map<String, dynamic>.from(value['source'] as Map),
    contextState: Map<String, dynamic>.from(value['contextState'] as Map),
    locals: value['locals'] is Map
        ? Map<String, dynamic>.from(value['locals'] as Map)
        : const <String, dynamic>{},
    status: value['status']?.toString() ?? 'completed',
    startedAt: _dateTime(value['startedAt']),
    completedAt: _dateTime(value['completedAt']),
    error: value['error']?.toString(),
    errorCode: value['errorCode']?.toString(),
    errorUserMessage: value['errorUserMessage']?.toString(),
    errorPluginId: value['errorPluginId']?.toString(),
    errorOperationId: value['errorOperationId']?.toString(),
    errorRetryable: value['errorRetryable'] as bool?,
    reason: value['reason']?.toString(),
  );
}

final class DartActionQueue {
  DartActionQueue({
    this.historyLimit = 20,
    this.defaultTimeout,
    this.defaultGap = Duration.zero,
  });

  final int historyLimit;
  Duration? defaultTimeout;
  Duration defaultGap;
  final List<QueuedGraphExecution> pending = [];
  final List<QueuedGraphExecution> history = [];
  final StreamController<QueuedGraphExecution?> _changes =
      StreamController<QueuedGraphExecution?>.broadcast();
  QueuedGraphExecution? running;
  bool paused = false;
  int _nextId = 0;
  Future<void> Function()? _cancelRunning;
  bool _cancelRequested = false;
  String? _cancelReason;

  Stream<QueuedGraphExecution?> get changes => _changes.stream;

  bool get isRunning => running != null;
  bool get isReady => !paused && !isRunning && pending.isEmpty;

  void setPaused(bool value) {
    if (paused == value) return;
    paused = value;
    _changes.add(null);
  }

  QueuedGraphExecution enqueue(
    RuntimeMap source,
    RuntimeMap contextState, {
    RuntimeMap locals = const <String, dynamic>{},
  }) {
    final item = QueuedGraphExecution(
      id: 'queue-${_nextId++}',
      source: Map<String, dynamic>.from(source),
      contextState: Map<String, dynamic>.from(contextState),
      locals: Map<String, dynamic>.from(locals),
    );
    pending.add(item);
    _changes.add(item);
    return item;
  }

  Future<void> processNext(
    Future<Object?> Function(QueuedGraphExecution item) execute, {
    Duration? timeout,
    Future<void> Function()? cancelRunning,
  }) async {
    if (paused || running != null || pending.isEmpty) return;
    final item = pending.removeAt(0);
    running = item;
    item.status = 'running';
    item.startedAt = DateTime.now();
    _cancelRunning = cancelRunning;
    _cancelRequested = false;
    _cancelReason = null;
    _changes.add(item);
    var recorded = false;
    try {
      final operation = execute(item);
      final limit = timeout ?? defaultTimeout;
      if (limit == null) {
        await operation;
      } else {
        await operation.timeout(limit);
      }
      item.status = _cancelRequested ? 'cancelled' : 'completed';
      item.reason = _cancelRequested ? _cancelReason : null;
      recorded = true;
    } catch (error) {
      if (_cancelRequested) {
        item.status = 'cancelled';
        item.reason = _cancelReason ?? error.toString();
      } else {
        item.status = 'failed';
        item.error = error.toString();
        if (error is ShowRunnerError) {
          item.errorCode = error.code;
          item.errorUserMessage = error.userMessage;
          item.errorPluginId = error.pluginId?.value;
          item.errorOperationId = error.operationId;
          item.errorRetryable = error.retryable;
        }
      }
      recorded = true;
      rethrow;
    } finally {
      item.completedAt = DateTime.now();
      if (recorded) {
        history.insert(0, item);
        if (history.length > historyLimit) history.removeLast();
      }
      running = null;
      _cancelRunning = null;
      _cancelRequested = false;
      _cancelReason = null;
      _changes.add(null);
    }
  }

  Future<void> processAll(
    Future<Object?> Function(QueuedGraphExecution item) execute, {
    Duration? gap,
    Duration? timeout,
  }) async {
    while (!paused && pending.isNotEmpty) {
      await processNext(execute, timeout: timeout);
      final effectiveGap = gap ?? defaultGap;
      if (!paused && pending.isNotEmpty && effectiveGap > Duration.zero) {
        await Future<void>.delayed(effectiveGap);
      }
    }
  }

  void skip(String id) {
    if (running?.id == id) {
      unawaited(cancelRunning(reason: 'Cancelled by operator'));
      return;
    }
    final index = pending.indexWhere((item) => item.id == id);
    if (index < 0) return;
    final item = pending.removeAt(index)
      ..status = 'skipped'
      ..completedAt = DateTime.now()
      ..reason = 'Skipped by operator';
    _recordHistory(item);
    _changes.add(item);
  }

  Future<void> cancelRunning({String reason = 'Cancelled by operator'}) async {
    final item = running;
    if (item == null) return;
    _cancelRequested = true;
    _cancelReason = reason;
    item.status = 'cancelling';
    item.reason = reason;
    _changes.add(item);
    final cancel = _cancelRunning;
    if (cancel != null) await cancel();
  }

  void clearPending() {
    pending.clear();
    _changes.add(null);
  }

  void replay(String id) {
    final item = history
        .where(
          (entry) =>
              entry.id == id &&
              (entry.status == 'completed' || entry.status == 'failed'),
        )
        .firstOrNull;
    if (item != null) {
      enqueue(item.source, item.contextState, locals: item.locals);
    }
  }

  RuntimeMap toJson() => {
    'pending': pending.map((item) => item.toJson()).toList(),
    'history': history.map((item) => item.toJson()).toList(),
    'paused': paused,
    'nextId': _nextId,
  };

  void restore(RuntimeMap value) {
    pending
      ..clear()
      ..addAll(_items(value['pending']));
    history
      ..clear()
      ..addAll(_items(value['history']).take(max(0, historyLimit)));
    paused = value['paused'] == true;
    _nextId = (value['nextId'] as num?)?.toInt() ?? _nextId;
  }

  void _recordHistory(QueuedGraphExecution item) {
    history.insert(0, item);
    if (history.length > historyLimit) history.removeLast();
  }

  List<QueuedGraphExecution> _items(dynamic value) => value is List
      ? value.whereType<Map>().map(QueuedGraphExecution.fromJson).toList()
      : <QueuedGraphExecution>[];

  Future<void> dispose() => _changes.close();
}

DateTime? _dateTime(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;
