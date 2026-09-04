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
            triggerId: 'membership',
            displayName: 'Membership',
            listen: () => eventHub.stream('membership'),
          ),
        ],
);
