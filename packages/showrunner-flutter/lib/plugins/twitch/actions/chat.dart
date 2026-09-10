part of '../actions.dart';

List<ActionSpec<Map<String, dynamic>, Object?>> _twitchChatActions(
  TwitchTransport transport,
) => [
  ActionSpec<Map<String, dynamic>, Object?>(
    pluginId: PluginId('twitch'),
    actionId: ActionId('chat'),
    displayName: 'Chat Message',
    configSchema: _chatSchema,
    invoke: (config, context) =>
        transport.request('POST', '/helix/chat/messages', {}, {
          'broadcaster_id': _id(config, context, 'broadcasterId'),
          'sender_id': _id(config, context, 'moderatorId'),
          'message': config['message'],
        }),
  ),
  ActionSpec<Map<String, dynamic>, Object?>(
    pluginId: PluginId('twitch'),
    actionId: ActionId('annoucement'),
    displayName: 'Make Announcement',
    configSchema: _announcementSchema,
    invoke: (config, context) => transport.request(
      'POST',
      '/helix/chat/announcements',
      {
        'broadcaster_id': _id(config, context, 'broadcasterId'),
        'moderator_id': _id(config, context, 'moderatorId'),
      },
      {'message': config['message'], 'color': config['color'] ?? 'primary'},
    ),
  ),
  ActionSpec<Map<String, dynamic>, Object?>(
    pluginId: PluginId('twitch'),
    actionId: ActionId('announcement'),
    displayName: 'Make Announcement',
    configSchema: _announcementSchema,
    invoke: (config, context) => transport.request(
      'POST',
      '/helix/chat/announcements',
      {
        'broadcaster_id': _id(config, context, 'broadcasterId'),
        'moderator_id': _id(config, context, 'moderatorId'),
      },
      {'message': config['message'], 'color': config['color'] ?? 'primary'},
    ),
  ),
  ActionSpec<Map<String, dynamic>, Object?>(
    pluginId: PluginId('twitch'),
    actionId: ActionId('shoutout'),
    displayName: 'Shoutout',
    configSchema: _shoutoutSchema,
    invoke: (config, context) =>
        transport.request('POST', '/helix/chat/shoutouts', {
          'from_broadcaster_id': _id(config, context, 'broadcasterId'),
          'moderator_id': _id(config, context, 'moderatorId'),
          'to_broadcaster_id': config['streamer'] ?? config['viewerId'],
        }, {}),
  ),
];
