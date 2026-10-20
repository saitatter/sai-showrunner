import '../runtime/provider_operation_policy.dart';
import 'dart:async';
import '../../runtime/expression.dart';
import '../../services/showrunner_data_service.dart';
import '../registry/plugin_factory_settings.dart';
import '../registry/plugin_registry.dart';
import 'manifest.dart';

Future<void> registerConfiguredLifx(
  DartPluginRegistry registry, {
  required ShowRunnerDataService dataService,
}) async {
  final scope = ProviderOperationScope();
  final lifxSettings = await dataService.loadPluginSettings('lifx');
  final lifxHost = lifxSettings['host']?.toString().trim();
  final lifxTransport = lifxHost?.isNotEmpty == true
      ? LifxUdpTransport(
          scope: scope,
          host: lifxHost!,
          port: pluginPort(lifxSettings['port'], 56700),
          target: parseLifxTarget(lifxSettings['target']?.toString()),
        )
      : null;
  final configuredLifxTransport = lifxTransport ?? _unconfiguredLifxTransport;
  registry.register(
    createLifxPlugin(
      configuredLifxTransport,
      transportResolver: (config) {
        final host = config['host']?.toString().trim() ?? '';
        if (host.isEmpty) return configuredLifxTransport;
        return LifxUdpTransport(
          scope: scope,
          host: host,
          port: pluginPort(config['port'], 56700),
          target: parseLifxTarget(config['target']?.toString()),
        );
      },
    ),

    initialHealth: (lifxTransport != null)
        ? const DartPluginHealth.connectionUnchecked()
        : const DartPluginHealth.notConfigured(),
    onStop: scope.close,
  );
}

void registerDefaultLifx(DartPluginRegistry registry) {
  registry.register(
    createLifxPlugin(_unconfiguredLifxTransport),
    initialHealth: const DartPluginHealth.notConfigured(),
  );
}

final LifxTransport _unconfiguredLifxTransport = CallbackLifxTransport(
  getStateCallback: () =>
      Future<RuntimeMap>.error(StateError('LIFX transport is not configured.')),
  setPowerCallback: (on, transitionMilliseconds) =>
      Future<RuntimeMap>.error(StateError('LIFX transport is not configured.')),
  setColorCallback: (color, transitionMilliseconds) =>
      Future<RuntimeMap>.error(StateError('LIFX transport is not configured.')),
);
