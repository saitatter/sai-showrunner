import '../../schema/data_input.dart';
import '../../runtime/expression.dart';
import '../registry/plugin_contract.dart';
import '../../services/plugin_event_hub.dart';

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

const _chatEventSchema = DartDataInputSchema(
  label: 'YouTube chat event',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'Viewer ID',
      key: 'viewerId',
      kind: DartDataInputKind.text,
      required: true,
    ),
    DartDataInputSchema(
      label: 'Viewer Name',
      key: 'viewerName',
      kind: DartDataInputKind.text,
      required: true,
    ),
    DartDataInputSchema(
      label: 'Message',
      key: 'message',
      kind: DartDataInputKind.text,
      required: true,
    ),
    DartDataInputSchema(
      label: 'Message ID',
      key: 'messageId',
      kind: DartDataInputKind.text,
      required: true,
    ),
    DartDataInputSchema(
      label: 'Avatar URL',
      key: 'avatarUrl',
      kind: DartDataInputKind.text,
    ),
    DartDataInputSchema(
      label: 'Moderator',
      key: 'isModerator',
      kind: DartDataInputKind.boolean,
      required: true,
    ),
    DartDataInputSchema(
      label: 'Member',
      key: 'isMember',
      kind: DartDataInputKind.boolean,
      required: true,
    ),
    DartDataInputSchema(
      label: 'Owner',
      key: 'isOwner',
      kind: DartDataInputKind.boolean,
      required: true,
    ),
  ],
);

const _paidEventSchema = DartDataInputSchema(
  label: 'YouTube paid event',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'Viewer ID',
      key: 'viewerId',
      kind: DartDataInputKind.text,
      required: true,
    ),
    DartDataInputSchema(
      label: 'Viewer Name',
      key: 'viewerName',
      kind: DartDataInputKind.text,
      required: true,
    ),
    DartDataInputSchema(
      label: 'Message',
      key: 'message',
      kind: DartDataInputKind.text,
      required: true,
    ),
    DartDataInputSchema(
      label: 'Message ID',
      key: 'messageId',
      kind: DartDataInputKind.text,
      required: true,
    ),
    DartDataInputSchema(
      label: 'Amount Micros',
      key: 'amountMicros',
      kind: DartDataInputKind.number,
      required: true,
    ),
    DartDataInputSchema(
      label: 'Currency',
      key: 'currency',
      kind: DartDataInputKind.text,
      required: true,
    ),
  ],
);

const _membershipEventSchema = DartDataInputSchema(
  label: 'YouTube membership event',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'Viewer Name',
      key: 'viewerName',
      kind: DartDataInputKind.text,
      required: true,
    ),
    DartDataInputSchema(
      label: 'Message',
      key: 'message',
      kind: DartDataInputKind.text,
      required: true,
    ),
    DartDataInputSchema(
      label: 'Event Type',
      key: 'eventType',
      kind: DartDataInputKind.text,
      required: true,
    ),
    DartDataInputSchema(
      label: 'Member Level',
      key: 'memberLevelName',
      kind: DartDataInputKind.text,
    ),
    DartDataInputSchema(
      label: 'Member Month',
      key: 'memberMonth',
      kind: DartDataInputKind.number,
    ),
  ],
);

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
  id: PluginId('youtube'),
  name: 'YouTube',
  states: const [
    StateSpec(
      id: StateId('connection'),
      displayName: 'Connection',
      initialValue: 'unconfigured',
    ),
    StateSpec(id: StateId('broadcast'), displayName: 'Broadcast'),
    StateSpec(id: StateId('latestMessage'), displayName: 'Latest Message'),
  ],
  settings: const [
    SettingSpec(id: SettingId('clientId'), displayName: 'Client ID'),
    SettingSpec(
      id: SettingId('clientSecret'),
      displayName: 'Client Secret',
      secret: true,
    ),
    SettingSpec(
      id: SettingId('accessToken'),
      displayName: 'Access Token',
      secret: true,
    ),
    SettingSpec(
      id: SettingId('refreshToken'),
      displayName: 'Refresh Token',
      secret: true,
    ),
    SettingSpec(id: SettingId('liveChatId'), displayName: 'Live Chat ID'),
  ],
  actions: [
    ActionSpec<Map<String, dynamic>, Object?>(
      pluginId: PluginId('youtube'),
      actionId: ActionId('sendChatMessage'),
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
    ActionSpec<Map<String, dynamic>, Object?>(
      pluginId: PluginId('youtube'),
      actionId: ActionId('deleteMessage'),
      displayName: 'Delete Chat Message',
      configSchema: _deleteMessageSchema,
      invoke: (config, context) => transport.request(
        'DELETE',
        '/youtube/v3/liveChat/messages',
        {'id': config['messageId']},
        null,
      ),
    ),
    ActionSpec<Map<String, dynamic>, Object?>(
      pluginId: PluginId('youtube'),
      actionId: ActionId('banUser'),
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
    ActionSpec<Map<String, dynamic>, Object?>(
      pluginId: PluginId('youtube'),
      actionId: ActionId('removeBan'),
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
  triggers: [
    TriggerSpec<Map<String, dynamic>, Map<String, dynamic>>(
      pluginId: PluginId('youtube'),
      triggerId: TriggerId('chatMessage'),
      displayName: 'Chat Message',
      listen: () => _youtubeEventStream(eventHub, 'chatMessage'),
      eventSchema: _chatEventSchema,
    ),
    TriggerSpec<Map<String, dynamic>, Map<String, dynamic>>(
      pluginId: PluginId('youtube'),
      triggerId: TriggerId('superChat'),
      displayName: 'Super Chat',
      listen: () => _youtubeEventStream(eventHub, 'superChat'),
      eventSchema: _paidEventSchema,
    ),
    TriggerSpec<Map<String, dynamic>, Map<String, dynamic>>(
      pluginId: PluginId('youtube'),
      triggerId: TriggerId('superSticker'),
      displayName: 'Super Sticker',
      listen: () => _youtubeEventStream(eventHub, 'superSticker'),
      eventSchema: _paidEventSchema,
    ),
    TriggerSpec<Map<String, dynamic>, Map<String, dynamic>>(
      pluginId: PluginId('youtube'),
      triggerId: TriggerId('membership'),
      displayName: 'Membership',
      listen: () => _youtubeEventStream(eventHub, 'membership'),
      eventSchema: _membershipEventSchema,
    ),
  ],
);

Stream<RuntimeMap> _youtubeEventStream(
  DartPluginEventHub? eventHub,
  String eventId,
) => eventHub?.stream(eventId) ?? const Stream<RuntimeMap>.empty();
