import 'plugin_contract.dart';
import 'plugin_health.dart';
import 'plugin_host_context.dart';

abstract interface class DartPluginModule {
  DartPluginManifest get manifest;

  Future<void> initialize(DartPluginHostContext host);

  Future<void> start();

  Future<void> stop();

  Future<DartPluginHealth> checkHealth();
}

/// Manifest-backed module for built-in plugins.
final class ManifestDartPluginModule implements DartPluginModule {
  const ManifestDartPluginModule(
    this.manifest, {
    this.onStart,
    this.onStop,
    this.onHealthCheck,
  });

  @override
  final DartPluginManifest manifest;
  final DartPluginLifecycleHook? onStart;
  final DartPluginLifecycleHook? onStop;
  final Future<bool> Function()? onHealthCheck;

  @override
  Future<void> initialize(DartPluginHostContext host) async {}

  @override
  Future<void> start() async {
    await onStart?.call();
  }

  @override
  Future<void> stop() async {
    await onStop?.call();
  }

  @override
  Future<DartPluginHealth> checkHealth() async {
    final healthCheck = onHealthCheck;
    if (healthCheck == null) return const DartPluginHealth.ready();
    try {
      return await healthCheck()
          ? const DartPluginHealth.ready()
          : const DartPluginHealth(
              status: DartPluginHealthStatus.unavailable,
              message: 'Plugin reported an unavailable health state.',
            );
    } catch (error) {
      return DartPluginHealth(
        status: DartPluginHealthStatus.error,
        message: error.toString(),
        error: error,
      );
    }
  }
}
