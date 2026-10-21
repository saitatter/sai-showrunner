import 'dart:async';
import '../../services/showrunner_data_service.dart';
import '../registry/plugin_registry.dart';
import 'manifest.dart';

Future<void> registerConfiguredMinecraft(
  DartPluginRegistry registry, {
  required ShowRunnerDataService dataService,
}) async {
  final rconConnectionRepository = dataService.storage.resource(
    const ResourceTypeId('RCONConnection'),
  );
  registry.register(
    createMinecraftPlugin(
      connectionResolver: (id) async =>
          (await rconConnectionRepository.load(id))?.config,
    ),

    initialHealth: const DartPluginHealth.connectionUnchecked(),
  );
}

void registerDefaultMinecraft(DartPluginRegistry registry) {
  registry.register(
    createMinecraftPlugin(),
    initialHealth: const DartPluginHealth.notConfigured(),
  );
}
