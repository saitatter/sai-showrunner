import 'dart:async';

typedef AppLifecycleTask = Future<void> Function();

/// Owns the reverse dependency order used when the desktop application stops.
///
/// Shutdown is idempotent and all tasks are attempted even if one provider or
/// plugin fails. The first failure is rethrown after the rest of the runtime
/// has had a chance to release its resources.
final class AppLifecycleCoordinator {
  AppLifecycleCoordinator({required Iterable<AppLifecycleTask> shutdownTasks})
    : _shutdownTasks = List<AppLifecycleTask>.unmodifiable(shutdownTasks);

  final List<AppLifecycleTask> _shutdownTasks;
  Future<void>? _shutdownFuture;

  bool get isShuttingDown => _shutdownFuture != null;

  Future<void> shutdown() => _shutdownFuture ??= _shutdown();

  Future<void> _shutdown() async {
    Object? firstError;
    StackTrace? firstStackTrace;
    for (final task in _shutdownTasks) {
      try {
        await task();
      } on Object catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      }
    }
    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStackTrace!);
    }
  }
}
