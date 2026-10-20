import 'dart:async';

/// Common budgets and retry classification. Protocol adapters retain their own
/// APIs, authentication and physical cancellation mechanisms.
final class ProviderOperationPolicy {
  const ProviderOperationPolicy({
    this.requestTimeout = defaultRequestTimeout,
    this.maxResponseBytes = defaultMaxResponseBytes,
  });

  static const defaultRequestTimeout = Duration(seconds: 20);
  static const defaultMaxResponseBytes = 4 * 1024 * 1024;
  static const healthTimeout = Duration(seconds: 10);
  static const deviceConnectTimeout = Duration(seconds: 2);
  static const deviceReplyTimeout = Duration(seconds: 5);
  static const datagramReplyTimeout = Duration(seconds: 2);
  static const maxDeviceFrameBytes = 1024 * 1024;
  static const maxReconnectDelay = Duration(minutes: 2);

  final Duration requestTimeout;
  final int maxResponseBytes;

  static bool canRetryHttpMethod(String method) =>
      const {'GET', 'HEAD'}.contains(method.toUpperCase());

  static Duration backoff(
    Duration base,
    int attempt, {
    required Duration maximum,
  }) {
    if (base.isNegative || maximum.isNegative || attempt < 0) {
      throw ArgumentError('Invalid provider backoff budget.');
    }
    if (attempt >= 63 && base > Duration.zero) return maximum;
    final multiplier = 1 << attempt.clamp(0, 62);
    if (base.inMicroseconds > maximum.inMicroseconds ~/ multiplier) {
      return maximum;
    }
    return base * multiplier;
  }
}

/// Owns physical abort callbacks, not a common transport interface. Closing
/// prevents new I/O and interrupts every registered client/socket once.
final class ProviderOperationScope {
  final Set<void Function()> _aborters = {};
  Completer<void>? _closedCompletion;
  bool get isClosed => _closedCompletion != null;

  void requireOpen() {
    if (isClosed) throw StateError('Provider operation scope is closed.');
  }

  void Function() track(void Function() abort) {
    requireOpen();
    _aborters.add(abort);
    return () {
      _aborters.remove(abort);
    };
  }

  Future<void> delay(Duration duration) async {
    requireOpen();
    final completion = Completer<void>();
    final timer = Timer(duration, completion.complete);
    final release = track(() {
      timer.cancel();
      if (!completion.isCompleted) {
        completion.completeError(StateError('Provider retry was cancelled.'));
      }
    });
    try {
      await completion.future;
      requireOpen();
    } finally {
      release();
      timer.cancel();
    }
  }

  Future<void> close() {
    final existing = _closedCompletion;
    if (existing != null) return existing.future;
    final completion = Completer<void>();
    _closedCompletion = completion;
    Object? firstError;
    StackTrace? firstStack;
    for (final abort in _aborters.toList().reversed) {
      try {
        abort();
      } catch (error, stack) {
        firstError ??= error;
        firstStack ??= stack;
      }
    }
    _aborters.clear();
    if (firstError == null) {
      completion.complete();
    } else {
      completion.completeError(firstError, firstStack!);
    }
    return completion.future;
  }
}
