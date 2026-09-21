part of '../actions.dart';

List<DartActionContract> _twitchStreamActions(TwitchTransport transport) => [
  ActionSpec<TwitchStreamMarkerConfig, RuntimeMap>(
    pluginId: PluginId('twitch'),
    actionId: ActionId('streamMarker'),
    displayName: 'Place Stream Marker',
    configSchema: _markerSchema,
    configCodec: twitchStreamMarkerConfigCodec,
    invoke: (config, context) => transport.request(
      'POST',
      '/helix/streams/markers',
      {
        'broadcaster_id': _idValue(
          config.broadcasterId,
          context,
          'broadcasterId',
        ),
      },
      {'comment': config.markerName ?? ''},
    ),
  ),
  ActionSpec<TwitchPredictionConfig, RuntimeMap>(
    pluginId: PluginId('twitch'),
    actionId: ActionId('createPrediction'),
    displayName: 'Create Prediction',
    configSchema: _predictionSchema,
    configCodec: twitchPredictionConfigCodec,
    invoke: (config, context) => transport.request(
      'POST',
      '/helix/predictions',
      {
        'broadcaster_id': _idValue(
          config.broadcasterId,
          context,
          'broadcasterId',
        ),
      },
      {
        'title': config.title,
        'prediction_window': config.duration ?? 30,
        'outcomes': config.outcomes
            .map((outcome) => outcome is Map ? outcome : {'title': outcome})
            .toList(),
      },
    ),
  ),
  ActionSpec<TwitchStreamInfoConfig, RuntimeMap>(
    pluginId: PluginId('twitch'),
    actionId: ActionId('setStreamInfo'),
    displayName: 'Update Stream Info',
    configSchema: _streamInfoSchema,
    configCodec: twitchStreamInfoConfigCodec,
    invoke: (config, context) => transport.request(
      'PATCH',
      '/helix/channels',
      {
        'broadcaster_id': _idValue(
          config.broadcasterId,
          context,
          'broadcasterId',
        ),
      },
      {
        if (config.title != null) 'title': config.title,
        if (config.categoryId != null) 'game_id': config.categoryId,
        if (config.tags != null) 'tags': config.tags,
      },
    ),
  ),
  ActionSpec<TwitchPollConfig, RuntimeMap>(
    pluginId: PluginId('twitch'),
    actionId: ActionId('createPoll'),
    displayName: 'Create Poll',
    configSchema: _pollSchema,
    configCodec: twitchPollConfigCodec,
    invoke: (config, context) => transport.request(
      'POST',
      '/helix/polls',
      {
        'broadcaster_id': _idValue(
          config.broadcasterId,
          context,
          'broadcasterId',
        ),
      },
      {
        'title': config.title,
        'duration': config.duration ?? 30,
        'choices': config.choices
            .map((choice) => choice is Map ? choice : {'title': choice})
            .toList(),
      },
    ),
  ),
  ActionSpec<TwitchRaidConfig, RuntimeMap>(
    pluginId: PluginId('twitch'),
    actionId: ActionId('startRaid'),
    displayName: 'Start Raid',
    configSchema: _raidSchema,
    configCodec: twitchRaidConfigCodec,
    invoke: (config, context) => transport.request('POST', '/helix/raids', {
      'from_broadcaster_id': _idValue(
        config.broadcasterId,
        context,
        'broadcasterId',
      ),
      'to_broadcaster_id': config.target ?? config.targetId,
    }, {}),
  ),
  ActionSpec<TwitchBroadcasterConfig, RuntimeMap>(
    pluginId: PluginId('twitch'),
    actionId: ActionId('cancelRaid'),
    displayName: 'Cancel Raid',
    configSchema: _cancelRaidSchema,
    configCodec: twitchBroadcasterConfigCodec,
    invoke: (config, context) => transport.request('DELETE', '/helix/raids', {
      'broadcaster_id': _idValue(
        config.broadcasterId,
        context,
        'broadcasterId',
      ),
    }, {}),
  ),
];
