import 'dart:async';
import 'dart:io';
import '../../persistence/resource_repository.dart';
import '../../services/showrunner_data_service.dart';
import '../registry/plugin_registry.dart';
import 'manifest.dart';

Future<void> registerConfiguredMinecraft(
  DartPluginRegistry registry, {
  required ShowRunnerDataService dataService,
}) async {
  final rconConnectionRepository = ResourceRepository(
    Directory('${dataService.userDirectory.path}/minecraft/connections'),
    resourceType: 'RCONConnection',
    secretSettings: dataService.secretSettingsStore,
  );
  registry.register(
    createMinecraftPlugin(
      connectionResolver: (id) async =>
          (await rconConnectionRepository.load(id))?.config,
    ),
  );
}

void registerDefaultMinecraft(DartPluginRegistry registry) {
  registry.register(createMinecraftPlugin());
}
