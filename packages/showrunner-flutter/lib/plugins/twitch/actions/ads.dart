part of '../actions.dart';

List<ActionSpec<dynamic, dynamic>> _twitchAdActions(
  TwitchTransport transport,
) => [
  ActionSpec<TwitchClipConfig, RuntimeMap>(
    pluginId: PluginId('twitch'),
    actionId: ActionId('createClip'),
    displayName: 'Create Clip',
    configSchema: _clipSchema,
    configCodec: twitchClipConfigCodec,
    invoke: (config, context) async {
      final response = await transport.request(
        'POST',
        '/helix/clips',
        {
          'broadcaster_id': _idValue(
            config.broadcasterId,
            context,
            'broadcasterId',
          ),
        },
        {'has_delay': config.createAfterDelay},
      );
      return {'clipId': _clipId(response)};
    },
  ),
  ActionSpec<TwitchAdConfig, RuntimeMap>(
    pluginId: PluginId('twitch'),
    actionId: ActionId('runAd'),
    displayName: 'Run Ad',
    configSchema: _adSchema,
    configCodec: twitchAdConfigCodec,
    invoke: (config, context) => transport.request(
      'POST',
      '/helix/channels/commercial',
      {
        'broadcaster_id': _idValue(
          config.broadcasterId,
          context,
          'broadcasterId',
        ),
      },
      {'length': config.duration ?? 30},
    ),
  ),
  ActionSpec<TwitchBroadcasterConfig, RuntimeMap>(
    pluginId: PluginId('twitch'),
    actionId: ActionId('snoozeAds'),
    displayName: 'Snooze Ads',
    configSchema: _twitchObject('Twitch ad schedule', [_broadcaster]),
    configCodec: twitchBroadcasterConfigCodec,
    invoke: (config, context) =>
        transport.request('POST', '/helix/channels/ads/schedule/snooze', {
          'broadcaster_id': _idValue(
            config.broadcasterId,
            context,
            'broadcasterId',
          ),
        }, {}),
  ),
];
