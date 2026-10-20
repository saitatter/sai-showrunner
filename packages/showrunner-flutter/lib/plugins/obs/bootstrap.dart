import 'dart:async';
import '../../runtime/expression.dart';
import '../../services/plugin_event_hub.dart';
import '../../services/showrunner_data_service.dart';
import '../advss/manifest.dart';
import '../aitum/manifest.dart';
import '../registry/plugin_registry.dart';
import 'actions.dart';
import 'connection_router.dart';

void registerConfiguredObsPack(
  DartPluginRegistry registry, {
  required ShowRunnerDataService dataService,
  required DartPluginEventHub? eventHub,
}) {
  final obsTransport = ObsConnectionRouter(
    dataService: dataService,
    eventHub: eventHub,
    onStateChanged: (state, value) => registry.updateState('obs', state, value),
  );
  registry.register(
    createObsPlugin(obsTransport),
    onHealthCheck: () async {
      await obsTransport.call('GetVersion', {});
      return true;
    },
  );
  registry.register(createAitumPlugin(obsTransport));
  registry.register(createAdvssPlugin(obsTransport, eventHub: eventHub));
}

void registerDefaultObsPack(
  DartPluginRegistry registry, {
  required DartPluginEventHub? eventHub,
}) {
  final obsTransport = CallbackObsTransport(_unconfiguredObs);
  registry.register(
    createObsPlugin(obsTransport),
    onHealthCheck: () async {
      await obsTransport.call('GetVersion', {});
      return true;
    },
  );
  registry.register(
    createAitumPlugin(CallbackObsTransport(_unconfiguredAitum)),
  );
  registry.register(
    createAdvssPlugin(
      CallbackObsTransport(_unconfiguredAitum),
      eventHub: eventHub,
    ),
  );
}

Future<RuntimeMap> _unconfiguredObs(String request, RuntimeMap data) =>
    Future<RuntimeMap>.error(StateError('OBS transport is not configured.'));

Future<RuntimeMap> _unconfiguredAitum(String request, RuntimeMap data) =>
    Future<RuntimeMap>.error(
      StateError('Aitum requires a configured OBS connection.'),
    );
