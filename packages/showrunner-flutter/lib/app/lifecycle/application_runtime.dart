import 'dart:async';

typedef RuntimeOperation = Future<void> Function();

/// Resources are owned at construction, including ones without a start hook.
/// Declaration order is dependency order; stop always runs in reverse order.
final class ApplicationRuntimeResource {
  const ApplicationRuntimeResource({
    required this.name,
    this.start,
    required this.stop,
  });
  final String name;
  final RuntimeOperation? start;
  final RuntimeOperation stop;
}

enum ApplicationRuntimeState { created, starting, running, stopping, stopped }

final class ApplicationRuntime {
  ApplicationRuntime({
    required Iterable<ApplicationRuntimeResource> resources,
    this.onFailure,
  }) : resources = List.unmodifiable(resources);
  final List<ApplicationRuntimeResource> resources;
  final void Function(String resource, Object error, StackTrace stack)?
  onFailure;
  ApplicationRuntimeState _state = ApplicationRuntimeState.created;
  ApplicationRuntimeState get state => _state;
  Future<void>? _startFuture;
  Future<void>? _shutdownFuture;
  Future<void>? _stopFuture;
  bool _closing = false;

  Future<void> start() {
    if (_closing) {
      return Future.error(
        StateError(
          'Application runtime is closed; create a new instance to restart.',
        ),
      );
    }
    return _startFuture ??= _start();
  }

  Future<void> _start() async {
    _state = ApplicationRuntimeState.starting;
    try {
      for (final resource in resources) {
        if (_closing) return;
        await resource.start?.call();
      }
      if (!_closing) _state = ApplicationRuntimeState.running;
    } catch (error, stack) {
      _closing = true;
      try {
        await _stop();
      } catch (_) {
        /* Stop errors are reported by resource; preserve the startup failure. */
      }
      Error.throwWithStackTrace(error, stack);
    }
  }

  Future<void> shutdown() {
    _closing = true;
    return _shutdownFuture ??= _shutdown();
  }

  Future<void> _shutdown() async {
    try {
      await _startFuture;
    } catch (_) {
      /* The start caller owns this error. Cleanup still runs. */
    }
    await _stop();
  }

  Future<void> _stop() => _stopFuture ??= _stopResources();
  Future<void> _stopResources() async {
    _state = ApplicationRuntimeState.stopping;
    Object? firstError;
    StackTrace? firstStack;
    for (final resource in resources.reversed) {
      try {
        await resource.stop();
      } catch (error, stack) {
        firstError ??= error;
        firstStack ??= stack;
        try {
          onFailure?.call(resource.name, error, stack);
        } catch (_) {
          /* A reporter must not prevent releasing remaining owners. The original failure is rethrown. */
        }
      }
    }
    _state = ApplicationRuntimeState.stopped;
    if (firstError != null) Error.throwWithStackTrace(firstError, firstStack!);
  }
}
