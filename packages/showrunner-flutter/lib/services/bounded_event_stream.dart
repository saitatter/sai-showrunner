import 'dart:async';
import 'dart:collection';

final class EventBackpressureException implements Exception {
  const EventBackpressureException(this.channel, this.capacity);
  final String channel;
  final int capacity;

  @override
  String toString() =>
      'Event channel "$channel" reached its $capacity pending-event limit. Delivery was rejected.';
}

/// Asynchronous broadcast delivery with a bounded queue for every subscriber,
/// including paused subscribers. An overflow rejects publication before any
/// subscriber receives that event; accepted events are never silently evicted.
final class BoundedEventStream<T> extends Stream<T> {
  BoundedEventStream({required this.channel, this.capacity = 4096}) {
    if (capacity < 1) throw ArgumentError.value(capacity, 'capacity');
  }

  final String channel;
  final int capacity;
  final Set<_EventListener<T>> _listeners = {};
  bool _closed = false;
  Future<void>? _closeFuture;

  @override
  bool get isBroadcast => true;

  void preflight() {
    if (_closed) throw StateError('Event channel is closed: $channel');
    if (_listeners.any((listener) => listener.pending >= capacity)) {
      throw EventBackpressureException(channel, capacity);
    }
  }

  void add(T value) {
    preflight();
    for (final listener in _listeners.toList(growable: false)) {
      listener.enqueue(value);
    }
  }

  @override
  StreamSubscription<T> listen(
    void Function(T event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    if (_closed) {
      return const Stream<Never>.empty().cast<T>().listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );
    }
    late final _EventListener<T> listener;
    listener = _EventListener<T>(() => _listeners.remove(listener));
    _listeners.add(listener);
    return listener.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  /// Host shutdown explicitly cancels pending delivery and subscriptions, even
  /// when a consumer remains paused. Consumers own their normal cancellation.
  Future<void> close() {
    _closed = true;
    return _closeFuture ??= _close();
  }

  Future<void> _close() async {
    await Future.wait(_listeners.toList().map((listener) => listener.close()));
    _listeners.clear();
  }
}

final class _EventListener<T> {
  _EventListener(this.onCancel) {
    _controller = StreamController<T>(
      sync: true,
      onPause: () => _paused = true,
      onResume: () {
        _paused = false;
        _schedule();
      },
      onCancel: () {
        _closed = true;
        _pending.clear();
        onCancel();
      },
    );
  }

  final void Function() onCancel;
  final _pending = ListQueue<T>();
  late final StreamController<T> _controller;
  StreamSubscription<T>? _subscription;
  bool _paused = false, _scheduled = false, _closed = false;
  int get pending => _pending.length;

  StreamSubscription<T> listen(
    void Function(T)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _subscription = _controller.stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  void enqueue(T value) {
    if (_closed) return;
    _pending.addLast(value);
    _schedule();
  }

  void _schedule() {
    if (_scheduled || _paused || _closed || _pending.isEmpty) return;
    _scheduled = true;
    scheduleMicrotask(_drain);
  }

  void _drain() {
    while (!_closed && !_paused && _pending.isNotEmpty) {
      _controller.add(_pending.removeFirst());
    }
    _scheduled = false;
  }

  Future<void> close() async {
    _closed = true;
    _pending.clear();
    if (_paused) await _subscription?.cancel();
    await _controller.close();
  }
}
