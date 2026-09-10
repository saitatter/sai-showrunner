part of '../actions.dart';

List<ActionSpec<Map<String, dynamic>, Object?>> _twitchAdActions(
  TwitchTransport transport,
) => [
  ActionSpec<Map<String, dynamic>, Object?>(
    pluginId: PluginId('twitch'),
    actionId: ActionId('createClip'),
    displayName: 'Create Clip',
    configSchema: _clipSchema,
    invoke: (config, context) async {
      final response = await transport.request(
        'POST',
        '/helix/clips',
        {'broadcaster_id': _id(config, context, 'broadcasterId')},
        {'has_delay': _bool(config['createAfterDelay'], fallback: true)},
      );
      return {'clipId': _clipId(response)};
    },
  ),
  ActionSpec<Map<String, dynamic>, Object?>(
    pluginId: PluginId('twitch'),
    actionId: ActionId('runAd'),
    displayName: 'Run Ad',
    configSchema: _adSchema,
    invoke: (config, context) => transport.request(
      'POST',
      '/helix/channels/commercial',
      {'broadcaster_id': _id(config, context, 'broadcasterId')},
      {'length': config['duration'] ?? 30},
    ),
  ),
  ActionSpec<Map<String, dynamic>, Object?>(
    pluginId: PluginId('twitch'),
    actionId: ActionId('snoozeAds'),
    displayName: 'Snooze Ads',
    configSchema: _twitchObject('Twitch ad schedule', [_broadcaster]),
    invoke: (config, context) => transport.request(
      'POST',
      '/helix/channels/ads/schedule/snooze',
      {'broadcaster_id': _id(config, context, 'broadcasterId')},
      {},
    ),
  ),
];
