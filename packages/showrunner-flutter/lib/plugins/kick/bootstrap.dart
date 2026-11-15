import '../../services/plugin_event_hub.dart';
import '../../services/showrunner_data_service.dart';
import '../registry/plugin_registry.dart';
import 'actions.dart';
import 'api_client.dart';

void registerDefaultKick(
  DartPluginRegistry registry, {
  DartPluginEventHub? eventHub,
}) {
  registry.register(
    createKickPlugin(
      KickTransport((_, _, _, _) async {
        throw StateError('Kick is not connected.');
      }),
      eventHub: eventHub,
    ),
    initialHealth: const DartPluginHealth.notConfigured(),
  );
}

void registerConfiguredKick(
  DartPluginRegistry registry, {
  required ShowRunnerDataService dataService,
  DartPluginEventHub? eventHub,
}) {
  final client = KickApiClient(dataService: dataService);
  registry.register(
    createKickPlugin(
      KickTransport(
        client.request,
        readBroadcasterId: client.readBroadcasterId,
      ),
      eventHub: eventHub,
    ),
    initialHealth: const DartPluginHealth.connectionUnchecked(),
    onStop: client.close,
  );
}
