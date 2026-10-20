import 'dart:async';
import 'trace_events.dart';

/// Change hints, not an event spool. Every listener retains at most one latest
/// hint, even while paused. Ordered history/counters live in retained snapshots.
final class TraceUpdateStream extends Stream<ExecutionTraceEvent> {
  final Set<_TraceUpdateListener> _listeners = {};
  bool _closed = false;
  int coalesced = 0;
  @override
  bool get isBroadcast => true;
  void add(ExecutionTraceEvent event) {
    if (_closed) return;
    for (final listener in _listeners.toList()) {
      listener.enqueue(event);
    }
  }

  @override
  StreamSubscription<ExecutionTraceEvent> listen(
    void Function(ExecutionTraceEvent)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    if (_closed) {
      return const Stream<ExecutionTraceEvent>.empty().listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );
    }
    late final _TraceUpdateListener listener;
    listener = _TraceUpdateListener(
      () => _listeners.remove(listener),
      () => coalesced++,
    );
    _listeners.add(listener);
    return listener.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  Future<void> close() async {
    _closed = true;
    await Future.wait(_listeners.toList().map((listener) => listener.close()));
    _listeners.clear();
  }
}

final class _TraceUpdateListener {
  _TraceUpdateListener(this.onCancel, this.onCoalesced) {
    _controller = StreamController<ExecutionTraceEvent>(
      sync: true,
      onPause: () => _paused = true,
      onResume: () {
        _paused = false;
        _schedule();
      },
      onCancel: () {
        _closed = true;
        _latest = null;
        onCancel();
      },
    );
  }
  final void Function() onCancel, onCoalesced;
  late final StreamController<ExecutionTraceEvent> _controller;
  StreamSubscription<ExecutionTraceEvent>? _subscription;
  ExecutionTraceEvent? _latest;
  bool _paused = false, _scheduled = false, _closed = false;
  StreamSubscription<ExecutionTraceEvent> listen(
    void Function(ExecutionTraceEvent)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _subscription = _controller.stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  void enqueue(ExecutionTraceEvent event) {
    if (_closed) return;
    if (_latest != null) onCoalesced();
    _latest = event;
    _schedule();
  }

  void _schedule() {
    if (_scheduled || _paused || _closed || _latest == null) return;
    _scheduled = true;
    scheduleMicrotask(() {
      _scheduled = false;
      if (_paused || _closed) return;
      final event = _latest;
      _latest = null;
      if (event != null) _controller.add(event);
    });
  }

  Future<void> close() async {
    _closed = true;
    _latest = null;
    if (_paused) await _subscription?.cancel();
    await _controller.close();
  }
}
