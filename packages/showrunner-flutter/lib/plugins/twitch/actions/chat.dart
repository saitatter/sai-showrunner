part of '../actions.dart';

List<ActionSpec<dynamic, dynamic>> _twitchChatActions(
  TwitchTransport transport,
) => [
  ActionSpec<TwitchChatConfig, RuntimeMap>(
    pluginId: PluginId('twitch'),
    actionId: ActionId('chat'),
    displayName: 'Chat Message',
    configSchema: _chatSchema,
    configCodec: twitchChatConfigCodec,
    invoke: (config, context) =>
        transport.request('POST', '/helix/chat/messages', {}, {
          'broadcaster_id': _idValue(
            config.broadcasterId,
            context,
            'broadcasterId',
          ),
          'sender_id': _idValue(config.moderatorId, context, 'moderatorId'),
          'message': config.message,
        }),
  ),
  ActionSpec<TwitchAnnouncementConfig, RuntimeMap>(
    pluginId: PluginId('twitch'),
    actionId: ActionId('annoucement'),
    displayName: 'Make Announcement',
    configSchema: _announcementSchema,
    configCodec: twitchAnnouncementConfigCodec,
    invoke: (config, context) => transport.request(
      'POST',
      '/helix/chat/announcements',
      {
        'broadcaster_id': _idValue(
          config.broadcasterId,
          context,
          'broadcasterId',
        ),
        'moderator_id': _idValue(config.moderatorId, context, 'moderatorId'),
      },
      {'message': config.message, 'color': config.color ?? 'primary'},
    ),
  ),
  ActionSpec<TwitchAnnouncementConfig, RuntimeMap>(
    pluginId: PluginId('twitch'),
    actionId: ActionId('announcement'),
    displayName: 'Make Announcement',
    configSchema: _announcementSchema,
    configCodec: twitchAnnouncementConfigCodec,
    invoke: (config, context) => transport.request(
      'POST',
      '/helix/chat/announcements',
      {
        'broadcaster_id': _idValue(
          config.broadcasterId,
          context,
          'broadcasterId',
        ),
        'moderator_id': _idValue(config.moderatorId, context, 'moderatorId'),
      },
      {'message': config.message, 'color': config.color ?? 'primary'},
    ),
  ),
  ActionSpec<TwitchShoutoutConfig, RuntimeMap>(
    pluginId: PluginId('twitch'),
    actionId: ActionId('shoutout'),
    displayName: 'Shoutout',
    configSchema: _shoutoutSchema,
    configCodec: twitchShoutoutConfigCodec,
    invoke: (config, context) =>
        transport.request('POST', '/helix/chat/shoutouts', {
          'from_broadcaster_id': _idValue(
            config.broadcasterId,
            context,
            'broadcasterId',
          ),
          'moderator_id': _idValue(config.moderatorId, context, 'moderatorId'),
          'to_broadcaster_id': config.streamer ?? config.viewerId,
        }, {}),
  ),
];
