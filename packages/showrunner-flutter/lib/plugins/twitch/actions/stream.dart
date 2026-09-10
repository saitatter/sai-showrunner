part of '../actions.dart';

List<ActionSpec<Map<String, dynamic>, Object?>> _twitchStreamActions(
  TwitchTransport transport,
) => [
  ActionSpec<Map<String, dynamic>, Object?>(
    pluginId: PluginId('twitch'),
    actionId: ActionId('streamMarker'),
    displayName: 'Place Stream Marker',
    configSchema: _markerSchema,
    invoke: (config, context) => transport.request(
      'POST',
      '/helix/streams/markers',
      {'broadcaster_id': _id(config, context, 'broadcasterId')},
      {'comment': config['markerName'] ?? ''},
    ),
  ),
  ActionSpec<Map<String, dynamic>, Object?>(
    pluginId: PluginId('twitch'),
    actionId: ActionId('createPrediction'),
    displayName: 'Create Prediction',
    configSchema: _predictionSchema,
    invoke: (config, context) => transport.request(
      'POST',
      '/helix/predictions',
      {'broadcaster_id': _id(config, context, 'broadcasterId')},
      {
        'title': config['title'],
        'prediction_window': config['duration'] ?? 30,
        'outcomes': (config['outcomes'] as List? ?? const [])
            .map((outcome) => outcome is Map ? outcome : {'title': outcome})
            .toList(),
      },
    ),
  ),
  ActionSpec<Map<String, dynamic>, Object?>(
    pluginId: PluginId('twitch'),
    actionId: ActionId('setStreamInfo'),
    displayName: 'Update Stream Info',
    configSchema: _streamInfoSchema,
    invoke: (config, context) => transport.request(
      'PATCH',
      '/helix/channels',
      {'broadcaster_id': _id(config, context, 'broadcasterId')},
      {
        if (config['title'] != null) 'title': config['title'],
        if (config['categoryId'] != null) 'game_id': config['categoryId'],
        if (config['tags'] is List) 'tags': config['tags'],
      },
    ),
  ),
  ActionSpec<Map<String, dynamic>, Object?>(
    pluginId: PluginId('twitch'),
    actionId: ActionId('createPoll'),
    displayName: 'Create Poll',
    configSchema: _pollSchema,
    invoke: (config, context) => transport.request(
      'POST',
      '/helix/polls',
      {'broadcaster_id': _id(config, context, 'broadcasterId')},
      {
        'title': config['title'],
        'duration': config['duration'] ?? 30,
        'choices': (config['choices'] as List? ?? const [])
            .map((choice) => choice is Map ? choice : {'title': choice})
            .toList(),
      },
    ),
  ),
  ActionSpec<Map<String, dynamic>, Object?>(
    pluginId: PluginId('twitch'),
    actionId: ActionId('startRaid'),
    displayName: 'Start Raid',
    configSchema: _raidSchema,
    invoke: (config, context) => transport.request('POST', '/helix/raids', {
      'from_broadcaster_id': _id(config, context, 'broadcasterId'),
      'to_broadcaster_id': config['target'] ?? config['targetId'],
    }, {}),
  ),
  ActionSpec<Map<String, dynamic>, Object?>(
    pluginId: PluginId('twitch'),
    actionId: ActionId('cancelRaid'),
    displayName: 'Cancel Raid',
    configSchema: _cancelRaidSchema,
    invoke: (config, context) => transport.request('DELETE', '/helix/raids', {
      'broadcaster_id': _id(config, context, 'broadcasterId'),
    }, {}),
  ),
];
