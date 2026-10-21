import 'dart:async';
import '../../services/showrunner_data_service.dart';
import '../registry/plugin_registry.dart';
import 'manifest.dart';

Future<void> registerConfiguredDiscord(
  DartPluginRegistry registry, {
  required ShowRunnerDataService dataService,
}) async {
  final discordWebhookRepository = dataService.storage.resource(
    const ResourceTypeId('DiscordWebhook'),
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
