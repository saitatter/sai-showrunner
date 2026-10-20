import 'runtime_snapshot.dart';
import 'expression.dart';
import 'dart:async';
import 'dart:math';

import '../domain/errors/showrunner_error.dart';
import 'cancellation.dart';

final class QueuedGraphExecution {
  QueuedGraphExecution({
    required this.id,
    required RuntimeMap source,
    required RuntimeMap contextState,
    RuntimeMap locals = const <String, dynamic>{},
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
  }) : source = freezeRuntimeMap(source),
       contextState = freezeRuntimeMap(contextState),
       locals = freezeRuntimeMap(locals);

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
  DartCancellationToken? _runningCancellationToken;
  bool _closed = false;
  Future<void>? _closing;
  Future<void>? _processing;
  final Set<Completer<void>> _gapWaits = {};
  void _ensureOpen() {
    if (_closed) throw StateError('Action queue is closed.');
  }

  bool _cancelRequested = false;
  String? _cancelReason;

  Stream<QueuedGraphExecution?> get changes => _changes.stream;

  bool get isRunning => running != null;
  bool get isReady => !paused && !isRunning && pending.isEmpty;
  DartCancellationToken? get runningCancellationToken =>
      _runningCancellationToken;

  void setPaused(bool value) {
    _ensureOpen();
    if (paused == value) return;
    paused = value;
    _changes.add(null);
  }

  QueuedGraphExecution enqueue(
    RuntimeMap source,
    RuntimeMap contextState, {
    RuntimeMap locals = const <String, dynamic>{},
  }) {
    _ensureOpen();
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
  }) {
    _ensureOpen();
    if (paused || running != null || pending.isEmpty) return Future.value();
    final completion = Completer<void>();
    _processing = completion.future;
    unawaited(_ownProcessing(execute, timeout, cancelRunning, completion));
    return completion.future;
  }

  Future<void> _ownProcessing(
    Future<Object?> Function(QueuedGraphExecution item) execute,
    Duration? timeout,
    Future<void> Function()? cancelRunning,
    Completer<void> completion,
  ) async {
    Object? failure;
    StackTrace? failureStack;
    try {
      await _processNext(
        execute,
        timeout: timeout,
        cancelRunning: cancelRunning,
      );
    } catch (error, stack) {
      failure = error;
      failureStack = stack;
    } finally {
      if (identical(_processing, completion.future)) _processing = null;
      if (failure == null) {
        completion.complete();
      } else {
        completion.completeError(failure, failureStack!);
      }
    }
  }

  Future<void> _processNext(
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
    final cancellationToken = DartCancellationToken(id: item.id);
    _runningCancellationToken = cancellationToken;
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
        try {
          await operation.timeout(limit);
        } on TimeoutException {
          cancellationToken.cancel();
          item.status = 'cancelling';
          item.reason = 'Execution timeout; waiting for cleanup';
          _changes.add(item);
          try {
            if (!_cancelRequested) await _cancelRunning?.call();
          } finally {
            // A deadline signals cancellation, not physical completion. Retain
            // queue ownership until the action has released its resources.
            await operation.then<void>(
              (_) {},
              onError: (Object _, StackTrace _) {},
            );
          }
          rethrow;
        }
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
      _runningCancellationToken = null;
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
    _ensureOpen();
    while (!_closed && !paused && pending.isNotEmpty) {
      await processNext(execute, timeout: timeout);
      final effectiveGap = gap ?? defaultGap;
      if (!_closed &&
          !paused &&
          pending.isNotEmpty &&
          effectiveGap > Duration.zero) {
        await _waitGap(effectiveGap);
      }
    }
  }

  void skip(String id) {
    _ensureOpen();
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
    _runningCancellationToken?.cancel();
    final cancel = _cancelRunning;
    if (cancel != null) await cancel();
  }

  void clearPending() {
    _ensureOpen();
    pending.clear();
    _changes.add(null);
  }

  void replay(String id) {
    _ensureOpen();
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
    _ensureOpen();
    final restoredPending = _items(value['pending']);
    final restoredHistory = _items(
      value['history'],
    ).take(max(0, historyLimit)).toList();
    if (running != null) throw StateError('Cannot restore a running queue.');
    pending
      ..clear()
      ..addAll(restoredPending);
    history
      ..clear()
      ..addAll(restoredHistory);
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

  Future<void> _waitGap(Duration gap) async {
    final completion = Completer<void>();
    final timer = Timer(gap, completion.complete);
    _gapWaits.add(completion);
    try {
      await completion.future;
    } finally {
      timer.cancel();
      _gapWaits.remove(completion);
    }
  }

  Future<void> dispose() => _closing ??= _dispose();
  Future<void> _dispose() async {
    _closed = true;
    for (final wait in _gapWaits.toList()) {
      if (!wait.isCompleted) wait.complete();
    }
    try {
      await cancelRunning(reason: 'Application shutdown');
    } finally {
      await _processing?.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {},
      );
      await _changes.close();
    }
  }
}

DateTime? _dateTime(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;
