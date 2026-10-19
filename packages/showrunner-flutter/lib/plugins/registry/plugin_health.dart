enum DartPluginHealthStatus { ready, unavailable, error }

final class DartPluginHealth {
  const DartPluginHealth({required this.status, this.message, this.error});

  const DartPluginHealth.ready() : this(status: DartPluginHealthStatus.ready);

  final DartPluginHealthStatus status;
  final String? message;
  final Object? error;

  bool get isHealthy => status == DartPluginHealthStatus.ready;
}
