import 'dart:async';
import '../../runtime/expression.dart';
import '../../services/plugin_event_hub.dart';
import '../../services/showrunner_data_service.dart';
import '../advss/manifest.dart';
import '../aitum/manifest.dart';
import '../registry/plugin_registry.dart';
import '../registry/plugin_module.dart';
import '../registry/plugin_registration.dart';
import 'actions.dart';
import 'connection_router.dart';

final _obsContribution =
    FirstPartyPluginContribution<({ObsTransport transport, bool configured})>(
      id: const PluginId('obs'),
      createModule: (context) => ManifestDartPluginModule(
        createObsPlugin(context.transport),
        onStop: context.transport.close,
        initialHealth: context.configured
            ? const DartPluginHealth.connectionUnchecked()
            : const DartPluginHealth.notConfigured(),
        onHealthCheck: context.configured
            ? () async {
                await context.transport.call('GetVersion', {});
                return true;
              }
            : null,
      ),
    );

void _registerPack(
  DartPluginRegistry registry,
  ObsTransport obs,
  ObsTransport extensions,
  DartPluginEventHub? eventHub, {
  bool configured = false,
}) {
  final extensionHealth = configured
      ? const DartPluginHealth.connectionUnchecked()
      : const DartPluginHealth.notConfigured();
  registry.registerModules([
    _obsContribution.create((transport: obs, configured: configured)),
    PluginModuleRegistration(
      id: const PluginId('aitum'),
      dependencies: const [PluginId('obs')],
      module: ManifestDartPluginModule(
        createAitumPlugin(extensions),
        initialHealth: extensionHealth,
      ),
    ),
    PluginModuleRegistration(
      id: const PluginId('advss'),
      dependencies: const [PluginId('obs')],
      module: ManifestDartPluginModule(
        createAdvssPlugin(extensions, eventHub: eventHub),
        initialHealth: extensionHealth,
      ),
    ),
  ]);
}

void registerConfiguredObsPack(
  DartPluginRegistry registry, {
  required ShowRunnerDataService dataService,
  required DartPluginEventHub? eventHub,
  ObsTransport? ownedTransport,
}) {
  final obsTransport =
      ownedTransport ??
      ObsConnectionRouter(
        dataService: dataService,
        eventHub: eventHub,
        onStateChanged: (state, value) =>
            registry.updateState('obs', state, value),
      );
  _registerPack(
    registry,
    obsTransport,
    obsTransport,
    eventHub,
    configured: true,
  );
}

void registerDefaultObsPack(
  DartPluginRegistry registry, {
  required DartPluginEventHub? eventHub,
}) {
  final obsTransport = CallbackObsTransport(_unconfiguredObs);
  _registerPack(
    registry,
    obsTransport,
    CallbackObsTransport(_unconfiguredAitum),
    eventHub,
  );
}

Future<RuntimeMap> _unconfiguredObs(String request, RuntimeMap data) =>
    Future<RuntimeMap>.error(StateError('OBS transport is not configured.'));

Future<RuntimeMap> _unconfiguredAitum(String request, RuntimeMap data) =>
    Future<RuntimeMap>.error(
      StateError('Aitum requires a configured OBS connection.'),
    );
