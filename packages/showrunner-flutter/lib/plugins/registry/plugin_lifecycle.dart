/// Lifecycle describes ownership, not the provider's network connection.
enum PluginLifecycleState {
  registered,
  initialized,
  starting,
  running,
  stopping,
  stopped,
  disabled,
  failed,
}

/// Automation visibility is independent of shared chat, settings, resources and
/// overlay connections. A running provider stays owned until host shutdown.
enum PluginEnablePolicy { automationOnly }

final class PluginStartupCleanupError implements Exception {
  const PluginStartupCleanupError(this.cause, this.cleanupError);
  final Object cause;
  final Object cleanupError;

  @override
  String toString() =>
      'Plugin start failed: $cause; cleanup failed: $cleanupError';
}

final class PluginPolicyTransactionError implements Exception {
  const PluginPolicyTransactionError(this.cause, this.rollbackError);
  final Object cause;
  final Object rollbackError;

  @override
  String toString() =>
      'Plugin enable failed: $cause; policy rollback failed: $rollbackError';
}
