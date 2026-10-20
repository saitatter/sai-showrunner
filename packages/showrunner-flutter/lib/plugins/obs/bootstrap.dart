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

final _obsContribution = FirstPartyPluginContribution<ObsTransport>(
  id: const PluginId('obs'),
  createModule: (transport) => ManifestDartPluginModule(
    createObsPlugin(transport),
    onStop: transport.close,
    onHealthCheck: () async {
      await transport.call('GetVersion', {});
      return true;
    },
  ),
);

void _registerPack(
  DartPluginRegistry registry,
  ObsTransport obs,
  ObsTransport extensions,
  DartPluginEventHub? eventHub,
) {
  registry.registerModules([
    _obsContribution.create(obs),
    PluginModuleRegistration(
      id: const PluginId('aitum'),
      dependencies: const [PluginId('obs')],
      module: ManifestDartPluginModule(createAitumPlugin(extensions)),
    ),
    PluginModuleRegistration(
      id: const PluginId('advss'),
      dependencies: const [PluginId('obs')],
      module: ManifestDartPluginModule(
        createAdvssPlugin(extensions, eventHub: eventHub),
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
  _registerPack(registry, obsTransport, obsTransport, eventHub);
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
