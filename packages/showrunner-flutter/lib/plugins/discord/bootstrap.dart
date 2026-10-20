import 'dart:async';
import 'dart:io';
import '../../persistence/resource_repository.dart';
import '../../services/showrunner_data_service.dart';
import '../registry/plugin_registry.dart';
import 'manifest.dart';

Future<void> registerConfiguredDiscord(
  DartPluginRegistry registry, {
  required ShowRunnerDataService dataService,
}) async {
  final discordWebhookRepository = ResourceRepository(
    Directory('${dataService.userDirectory.path}/discord/webhooks'),
    resourceType: 'DiscordWebhook',
    secretSettings: dataService.secretSettingsStore,
  );
  registry.register(
    createDiscordPlugin(
      webhookResolver: (id) async =>
          (await discordWebhookRepository.load(id))?.config,
    ),

    initialHealth: const DartPluginHealth.connectionUnchecked(),
  );
}

void registerDefaultDiscord(DartPluginRegistry registry) {
  registry.register(
    createDiscordPlugin(),
    initialHealth: const DartPluginHealth.notConfigured(),
  );
}
