/// Moderation plugin boundary reserved for the bespoke Flutter migration.
///
/// Moderation actions currently live in the YouTube and Twitch manifests;
/// this directory is the target home for shared moderation contracts.
library;

import '../registry/plugin_registry.dart';
import 'runtime.dart';
import 'ui/moderation_workspace.dart';

DartPluginManifest createModerationPlugin(ModerationService service) =>
    DartPluginManifest(
      id: 'moderation',
      name: 'Moderation Docker',
      workspaceBuilder:
          (context, dataService, providerEvents, registryFuture) =>
              ModerationWorkspace(service: service),
      settings: const [
        DartSettingDefinition(id: 'enabled', displayName: 'Enabled'),
        DartSettingDefinition(id: 'apiBaseUrl', displayName: 'API URL'),
        DartSettingDefinition(
          id: 'apiToken',
          displayName: 'API Token',
          secret: true,
        ),
        DartSettingDefinition(
          id: 'dashboardWsUrl',
          displayName: 'Dashboard WebSocket URL',
        ),
        DartSettingDefinition(
          id: 'forwardYouTube',
          displayName: 'Forward YouTube Chat',
          defaultValue: true,
        ),
      ],
      states: const [
        DartPluginStateDefinition(
          id: 'health',
          displayName: 'Health',
          initialValue: 'unknown',
        ),
      ],
      healthCheck: () async =>
          (await service.checkHealth()).health == 'healthy',
      actions: [
        DartActionDefinition(
          pluginId: 'moderation',
          actionId: 'moderateChatMessage',
          displayName: 'Filter Chat Message',
          invoke: (config, context) => service.moderateChatMessage(config),
        ),
        DartActionDefinition(
          pluginId: 'moderation',
          actionId: 'sendTestMessage',
          displayName: 'Send Test Moderation Event',
          invoke: (config, context) async => service.sendTestMessage(),
        ),
        DartActionDefinition(
          pluginId: 'moderation',
          actionId: 'requestOverride',
          displayName: 'Request Moderation Override',
          invoke: (config, context) => service.requestOverride(
            messageId: config['messageId']?.toString() ?? '',
            action: config['action']?.toString() ?? 'approve',
          ),
        ),
      ],
    );
