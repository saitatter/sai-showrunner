/// Moderation plugin boundary for the Flutter desktop runtime.
///
/// Moderation actions currently live in the YouTube and Twitch manifests;
/// this directory is the target home for shared moderation contracts.
library;

import '../registry/plugin_contract.dart';
import '../registry/plugin_ui.dart';
import '../../schema/data_input.dart';
import 'runtime.dart';
import 'ui/moderation_workspace.dart';

const _moderateChatSchema = DartDataInputSchema(
  label: 'Moderation chat message',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'Platform',
      key: 'platform',
      kind: DartDataInputKind.text,
      defaultValue: 'twitch',
    ),
    DartDataInputSchema(
      label: 'Message ID',
      key: 'messageId',
      kind: DartDataInputKind.text,
    ),
    DartDataInputSchema(
      label: 'Viewer ID',
      key: 'viewerId',
      kind: DartDataInputKind.text,
    ),
    DartDataInputSchema(
      label: 'Viewer name',
      key: 'viewerName',
      kind: DartDataInputKind.text,
    ),
    DartDataInputSchema(
      label: 'Message',
      key: 'message',
      kind: DartDataInputKind.multilineText,
      required: true,
    ),
    DartDataInputSchema(
      label: 'Badges (comma-separated)',
      key: 'badges',
      kind: DartDataInputKind.text,
    ),
    DartDataInputSchema(
      label: 'Moderator',
      key: 'isModerator',
      kind: DartDataInputKind.boolean,
    ),
    DartDataInputSchema(
      label: 'Member',
      key: 'isMember',
      kind: DartDataInputKind.boolean,
    ),
    DartDataInputSchema(
      label: 'Owner',
      key: 'isOwner',
      kind: DartDataInputKind.boolean,
    ),
  ],
);

const _overrideSchema = DartDataInputSchema(
  label: 'Moderation override',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'Message ID',
      key: 'messageId',
      kind: DartDataInputKind.text,
      required: true,
    ),
    DartDataInputSchema(
      label: 'Action',
      key: 'action',
      kind: DartDataInputKind.enumeration,
      options: ['approve', 'block', 'falsePositive'],
      required: true,
      defaultValue: 'approve',
    ),
  ],
);

const _emptySchema = DartDataInputSchema(
  label: 'Moderation action',
  kind: DartDataInputKind.object,
);

DartPluginManifest createModerationPlugin(ModerationService service) =>
    DartPluginManifest(
      id: 'moderation',
      name: 'Moderation Docker',
      ui: DartFlutterPluginUiContribution(
        builder: (context, dataService, providerEvents, registryFuture) =>
            ModerationWorkspace(service: service),
      ),
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
      dispose: service.dispose,
      actions: [
        DartActionDefinition(
          pluginId: 'moderation',
          actionId: 'moderateChatMessage',
          displayName: 'Filter Chat Message',
          configSchema: _moderateChatSchema,
          invoke: (config, context) => service.moderateChatMessage(config),
        ),
        DartActionDefinition(
          pluginId: 'moderation',
          actionId: 'sendTestMessage',
          displayName: 'Send Test Moderation Event',
          configSchema: _emptySchema,
          invoke: (config, context) async => service.sendTestMessage(),
        ),
        DartActionDefinition(
          pluginId: 'moderation',
          actionId: 'requestOverride',
          displayName: 'Request Moderation Override',
          configSchema: _overrideSchema,
          invoke: (config, context) => service.requestOverride(
            messageId: config['messageId']?.toString() ?? '',
            action: config['action']?.toString() ?? 'approve',
          ),
        ),
      ],
    );
