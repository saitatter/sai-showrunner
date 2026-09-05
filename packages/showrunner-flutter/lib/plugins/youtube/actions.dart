import '../../components/data_inputs/data_input.dart';
import '../../runtime/expression.dart';
import '../registry/plugin_registry.dart';
import '../../services/plugin_event_hub.dart';
import 'ui/youtube_workspace.dart';

typedef YouTubeRequest =
    Future<RuntimeMap> Function(
      String method,
      String path,
      RuntimeMap query,
      dynamic body,
    );

final class YouTubeTransport {
  const YouTubeTransport(this.request);

  final YouTubeRequest request;
}

DartDataInputSchema _youtubeObject(
  String label,
  List<DartDataInputSchema> fields,
) => DartDataInputSchema(
  label: label,
  kind: DartDataInputKind.object,
  fields: fields,
);

final _chatSchema = _youtubeObject('YouTube chat message', [
  DartDataInputSchema(
    label: 'Live chat ID',
    key: 'liveChatId',
    kind: DartDataInputKind.text,
  ),
  DartDataInputSchema(
    label: 'Message',
    key: 'message',
    kind: DartDataInputKind.multilineText,
    required: true,
  ),
]);

final _deleteMessageSchema = _youtubeObject('YouTube chat message', [
  DartDataInputSchema(
    label: 'Message ID',
    key: 'messageId',
    kind: DartDataInputKind.text,
    required: true,
  ),
]);

final _banSchema = _youtubeObject('YouTube chat ban', [
  DartDataInputSchema(
    label: 'Live chat ID',
    key: 'liveChatId',
    kind: DartDataInputKind.text,
  ),
  DartDataInputSchema(
    label: 'Channel ID',
    key: 'channelId',
    kind: DartDataInputKind.text,
    required: true,
  ),
  DartDataInputSchema(
    label: 'Duration (seconds; 0 = permanent)',
    key: 'banDurationSeconds',
    kind: DartDataInputKind.number,
    defaultValue: 0,
  ),
]);

final _removeBanSchema = _youtubeObject('YouTube chat ban', [
  DartDataInputSchema(
    label: 'Ban ID',
    key: 'banId',
    kind: DartDataInputKind.text,
    required: true,
  ),
]);

DartPluginManifest createYouTubePlugin(
  YouTubeTransport transport, {
  DartPluginEventHub? eventHub,
}) => DartPluginManifest(
  id: 'youtube',
  name: 'YouTube',
  workspaceBuilder: (context, dataService, providerEvents, registryFuture) =>
      YouTubeWorkspace(
        dataService: dataService,
        providerEvents: providerEvents,
        registryFuture: registryFuture,
      ),
  states: const [
    DartPluginStateDefinition(
      id: 'connection',
      displayName: 'Connection',
      initialValue: 'unconfigured',
    ),
    DartPluginStateDefinition(id: 'broadcast', displayName: 'Broadcast'),
    DartPluginStateDefinition(
      id: 'latestMessage',
      displayName: 'Latest Message',
    ),
  ],
  settings: const [
    DartSettingDefinition(id: 'clientId', displayName: 'Client ID'),
    DartSettingDefinition(
      id: 'clientSecret',
      displayName: 'Client Secret',
      secret: true,
    ),
    DartSettingDefinition(
      id: 'accessToken',
      displayName: 'Access Token',
      secret: true,
    ),
    DartSettingDefinition(
      id: 'refreshToken',
      displayName: 'Refresh Token',
      secret: true,
    ),
    DartSettingDefinition(id: 'liveChatId', displayName: 'Live Chat ID'),
  ],
  actions: [
    DartActionDefinition(
      pluginId: 'youtube',
      actionId: 'sendChatMessage',
      displayName: 'Send Chat Message',
      configSchema: _chatSchema,
      invoke: (config, context) => transport.request(
        'POST',
        '/youtube/v3/liveChat/messages',
        {'part': 'snippet'},
        {
          'snippet': {
            'liveChatId':
                config['liveChatId'] ?? context.contextState['liveChatId'],
            'type': 'textMessageEvent',
            'textMessageDetails': {'messageText': config['message']},
          },
        },
      ),
    ),
    DartActionDefinition(
      pluginId: 'youtube',
      actionId: 'deleteMessage',
      displayName: 'Delete Chat Message',
      configSchema: _deleteMessageSchema,
      invoke: (config, context) => transport.request(
        'DELETE',
        '/youtube/v3/liveChat/messages',
        {'id': config['messageId']},
        null,
      ),
    ),
    DartActionDefinition(
      pluginId: 'youtube',
      actionId: 'banUser',
      displayName: 'Ban User from Chat',
      configSchema: _banSchema,
      invoke: (config, context) {
        final duration = (config['banDurationSeconds'] as num?)?.toInt() ?? 0;
        return transport.request(
          'POST',
          '/youtube/v3/liveChat/bans',
          {'part': 'snippet'},
          {
            'snippet': {
              'liveChatId':
                  config['liveChatId'] ?? context.contextState['liveChatId'],
              'type': duration > 0 ? 'temporary' : 'permanent',
              'bannedUserDetails': {'channelId': config['channelId']},
              if (duration > 0) 'banDurationSeconds': duration,
            },
          },
        );
      },
    ),
    DartActionDefinition(
      pluginId: 'youtube',
      actionId: 'removeBan',
      displayName: 'Unban User from Chat',
      configSchema: _removeBanSchema,
      invoke: (config, context) => transport.request(
        'DELETE',
        '/youtube/v3/liveChat/bans',
        {'id': config['banId']},
        null,
      ),
    ),
  ],
  triggers: eventHub == null
      ? const []
      : [
          DartTriggerDefinition(
            pluginId: 'youtube',
            triggerId: 'chatMessage',
            displayName: 'Chat Message',
            listen: () => eventHub.stream('chatMessage'),
          ),
          DartTriggerDefinition(
            pluginId: 'youtube',
            triggerId: 'superChat',
            displayName: 'Super Chat',
            listen: () => eventHub.stream('superChat'),
          ),
          DartTriggerDefinition(
            pluginId: 'youtube',
            triggerId: 'superSticker',
            displayName: 'Super Sticker',
            listen: () => eventHub.stream('superSticker'),
          ),
          DartTriggerDefinition(
            pluginId: 'youtube',
            triggerId: 'membership',
            displayName: 'Membership',
            listen: () => eventHub.stream('membership'),
          ),
        ],
);
