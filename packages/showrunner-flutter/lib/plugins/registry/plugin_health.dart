enum DartPluginHealthStatus {
  ready,
  notConfigured,
  disconnected,
  disabled,
  unavailable,
  error,
}

final class DartPluginHealth {
  const DartPluginHealth({required this.status, this.message, this.error});

  const DartPluginHealth.ready() : this(status: DartPluginHealthStatus.ready);

  const DartPluginHealth.notConfigured()
    : this(
        status: DartPluginHealthStatus.notConfigured,
        message:
            'Default provider connection is not configured. Resource-specific connections may still be available.',
      );

  const DartPluginHealth.connectionUnchecked()
    : this(
        status: DartPluginHealthStatus.disconnected,
        message: 'Provider connection has not been verified.',
      );

  final DartPluginHealthStatus status;
  final String? message;
  final Object? error;

  bool get isHealthy => status == DartPluginHealthStatus.ready;
}
