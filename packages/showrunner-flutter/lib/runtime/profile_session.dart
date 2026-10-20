import 'dart:async';
import 'cancellation.dart';
import 'expression.dart';

final class ProfileTriggerFailure {
  const ProfileTriggerFailure(this.profileId, this.error, this.stack);
  final String profileId;
  final Object error;
  final StackTrace stack;
}

/// Owns subscriptions and direct trigger work. Already accepted queue items keep
/// their independent queue cancellation/retained snapshot policy.
final class DartProfileSession {
  DartProfileSession({
    required this._subscriptions,
    required this._listenerRemovers,
    required this.onFailure,
    required this.onDisposed,
  });
  final List<StreamSubscription<RuntimeMap>> _subscriptions;
  final List<void Function()> _listenerRemovers;
  final void Function(Object, StackTrace) onFailure;
  final void Function() onDisposed;
  final DartCancellationToken cancellation = DartCancellationToken();
  final Set<Future<void>> _pending = {};
  Future<void>? _closing;
  bool _closed = false;
  bool get isClosed => _closed;
  Object? _notificationError;
  StackTrace? _notificationStack;

  void dispatch(Future<Object?> Function() operation) {
    if (_closed || cancellation.isCancelled) return;
    late final Future<void> pending;
    pending = Future<Object?>.sync(operation)
        .then<void>(
          (_) {},
          onError: (Object error, StackTrace stack) {
            if (_closed && cancellation.isCancelled) return;
            try {
              onFailure(error, stack);
            } catch (failure, failureStack) {
              _notificationError ??= failure;
              _notificationStack ??= failureStack;
            }
          },
        )
        .whenComplete(() => _pending.remove(pending));
    _pending.add(pending);
  }

  Future<void> dispose() => _closing ??= _dispose();
  Future<void> _dispose() async {
    _closed = true;
    cancellation.cancel();
    Object? failure;
    StackTrace? failureStack;
    Future<void> release(FutureOr<void> Function() operation) async {
      try {
        await operation();
      } catch (error, stack) {
        failure ??= error;
        failureStack ??= stack;
      }
    }

    try {
      for (final remove in _listenerRemovers.toList()) {
        await release(remove);
      }
      _listenerRemovers.clear();
      await Future.wait(
        _subscriptions.map((subscription) => release(subscription.cancel)),
      );
      _subscriptions.clear();
      await Future.wait(_pending.toList());
    } finally {
      onDisposed();
    }
    if (failure != null) Error.throwWithStackTrace(failure!, failureStack!);
    if (_notificationError != null) {
      Error.throwWithStackTrace(_notificationError!, _notificationStack!);
    }
  }
}
