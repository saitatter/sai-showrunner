import '../registry/plugin_contract.dart';

final _discordWebhookResource = ResourceSpec(
  ownerId: const PluginId('discord'),
  resourceTypeId: const ResourceTypeId('DiscordWebhook'),
  displayName: 'Discord Webhook',
  storageDirectory: 'discord/webhooks',
  defaultConfigFactory: (name) => {'name': name, 'webhookUrl': ''},
);

final List<DartResourceContract> discordResourceContracts = List.unmodifiable([
  _discordWebhookResource,
]);
