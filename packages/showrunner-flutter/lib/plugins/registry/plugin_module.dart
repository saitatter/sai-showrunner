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

/// Compatibility adapter for built-in plugins that already expose a manifest.
final class ManifestDartPluginModule implements DartPluginModule {
  const ManifestDartPluginModule(this.manifest);

  @override
  final DartPluginManifest manifest;

  @override
  Future<void> initialize(DartPluginHostContext host) async {}

  @override
  Future<void> start() async {
    await manifest.start?.call();
  }

  @override
  Future<void> stop() async {
    await (manifest.stop ?? manifest.dispose)?.call();
  }

  @override
  Future<DartPluginHealth> checkHealth() async {
    final healthCheck = manifest.healthCheck;
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
