import '../../runtime/expression.dart';
import '../../components/data_inputs/data_input.dart';
import '../registry/plugin_registry.dart';
import '../../services/plugin_event_hub.dart';
import 'channel_points.dart';
import 'ui/twitch_workspace.dart';

typedef TwitchRequest =
    Future<RuntimeMap> Function(
      String method,
      String path,
      RuntimeMap query,
      RuntimeMap body,
    );

final class TwitchTransport {
  const TwitchTransport(this.request);

  final TwitchRequest request;
}

DartDataInputSchema _twitchObject(
  String label,
  List<DartDataInputSchema> fields,
) => DartDataInputSchema(
  label: label,
  kind: DartDataInputKind.object,
  fields: fields,
);

DartDataInputSchema _twitchText(
  String label,
  String key, {
  bool required = false,
  bool multiline = false,
  bool secret = false,
}) => DartDataInputSchema(
  label: label,
  key: key,
  kind: multiline ? DartDataInputKind.multilineText : DartDataInputKind.text,
  required: required,
  multiline: multiline,
  secret: secret,
);

final _broadcaster = _twitchText('Broadcaster ID', 'broadcasterId');
final _moderator = _twitchText('Moderator ID', 'moderatorId');
final _identities = <DartDataInputSchema>[_broadcaster, _moderator];

final _clipSchema = _twitchObject('Twitch clip', [
  _broadcaster,
  DartDataInputSchema(
    label: 'Create after delay',
    key: 'createAfterDelay',
    kind: DartDataInputKind.boolean,
    defaultValue: true,
  ),
]);

final _markerSchema = _twitchObject('Twitch stream marker', [
  _broadcaster,
  _twitchText('Marker name', 'markerName', required: true),
]);

final _adSchema = _twitchObject('Twitch ad', [
  _broadcaster,
  DartDataInputSchema(
    label: 'Duration (seconds)',
    key: 'duration',
    kind: DartDataInputKind.number,
    required: true,
    defaultValue: 30,
  ),
]);

final _predictionSchema = _twitchObject('Twitch prediction', [
  _broadcaster,
  _twitchText('Title', 'title', required: true),
  DartDataInputSchema(
    label: 'Duration (seconds)',
    key: 'duration',
    kind: DartDataInputKind.number,
    required: true,
    defaultValue: 30,
  ),
  DartDataInputSchema(
    label: 'Outcomes',
    key: 'outcomes',
    kind: DartDataInputKind.array,
    itemKind: DartDataInputKind.text,
    required: true,
  ),
]);

final _chatSchema = _twitchObject('Twitch chat message', [
  ..._identities,
  _twitchText('Message', 'message', required: true, multiline: true),
]);

final _announcementSchema = _twitchObject('Twitch announcement', [
  ..._identities,
  _twitchText('Message', 'message', required: true),
  DartDataInputSchema(
    label: 'Color',
    key: 'color',
    kind: DartDataInputKind.enumeration,
    options: ['primary', 'blue', 'green', 'orange', 'purple'],
    defaultValue: 'primary',
  ),
]);

final _shoutoutSchema = _twitchObject('Twitch shoutout', [
  ..._identities,
  _twitchText('Target broadcaster ID', 'streamer', required: true),
]);

final _streamInfoSchema = _twitchObject('Twitch stream info', [
  _broadcaster,
  _twitchText('Title', 'title'),
  _twitchText('Category ID', 'categoryId'),
  DartDataInputSchema(
    label: 'Tags',
    key: 'tags',
    kind: DartDataInputKind.array,
    itemKind: DartDataInputKind.text,
  ),
]);

final _pollSchema = _twitchObject('Twitch poll', [
  _broadcaster,
  _twitchText('Title', 'title', required: true),
  DartDataInputSchema(
    label: 'Duration (seconds)',
    key: 'duration',
    kind: DartDataInputKind.number,
    required: true,
    defaultValue: 30,
  ),
  DartDataInputSchema(
    label: 'Choices',
    key: 'choices',
    kind: DartDataInputKind.array,
    itemKind: DartDataInputKind.text,
    required: true,
  ),
]);

final _raidSchema = _twitchObject('Twitch raid', [
  _broadcaster,
  _twitchText('Target broadcaster ID', 'target', required: true),
]);

final _cancelRaidSchema = _twitchObject('Twitch raid cancellation', [
  _broadcaster,
]);

final _listRewardsSchema = _twitchObject('Twitch channel point rewards', [
  _broadcaster,
  DartDataInputSchema(
    label: 'Only manageable rewards',
    key: 'onlyManageable',
    kind: DartDataInputKind.boolean,
  ),
]);

final _rewardIdSchema = _twitchObject('Twitch channel point reward', [
  _broadcaster,
  _twitchText('Reward ID', 'rewardId', required: true),
]);

final _rewardFields = <DartDataInputSchema>[
  _broadcaster,
  _twitchText('Title', 'title', required: true),
  _twitchText('Prompt', 'prompt', multiline: true),
  DartDataInputSchema(
    label: 'Background color',
    key: 'backgroundColor',
    kind: DartDataInputKind.color,
    defaultValue: '#9147ff',
  ),
  DartDataInputSchema(
    label: 'Cost',
    key: 'cost',
    kind: DartDataInputKind.number,
    required: true,
    defaultValue: 1,
  ),
  DartDataInputSchema(
    label: 'User input required',
    key: 'userInputRequired',
    kind: DartDataInputKind.boolean,
  ),
  DartDataInputSchema(
    label: 'Skip request queue',
    key: 'skipQueue',
    kind: DartDataInputKind.boolean,
  ),
  DartDataInputSchema(
    label: 'Enabled',
    key: 'isEnabled',
    kind: DartDataInputKind.boolean,
    defaultValue: true,
  ),
  DartDataInputSchema(
    label: 'Max redemptions per stream',
    key: 'maxRedemptionsPerStream',
    kind: DartDataInputKind.number,
  ),
  DartDataInputSchema(
    label: 'Max redemptions per user per stream',
    key: 'maxRedemptionsPerUserPerStream',
    kind: DartDataInputKind.number,
  ),
  DartDataInputSchema(
    label: 'Global cooldown (seconds)',
    key: 'cooldown',
    kind: DartDataInputKind.number,
  ),
];

final _createRewardSchema = _twitchObject(
  'Twitch channel point reward',
  _rewardFields,
);
final _updateRewardSchema =
    _twitchObject('Twitch channel point reward update', [
      _broadcaster,
      _twitchText('Reward ID', 'rewardId', required: true),
      ..._rewardFields.skip(1),
    ]);

final _redemptionSchema = _twitchObject('Twitch redemption', [
  _broadcaster,
  _twitchText('Reward ID', 'rewardId', required: true),
  _twitchText('Redemption ID', 'redemptionId', required: true),
  DartDataInputSchema(
    label: 'Status',
    key: 'status',
    kind: DartDataInputKind.enumeration,
    options: ['FULFILLED', 'CANCELED'],
    required: true,
    defaultValue: 'FULFILLED',
  ),
]);

final _moderationSchema = _twitchObject('Twitch moderation', [
  ..._identities,
  _twitchText('Viewer ID', 'viewerId', required: true),
  _twitchText('Reason', 'reason', multiline: true),
]);

final _timeoutSchema = _twitchObject('Twitch timeout', [
  ..._moderationSchema.fields,
  DartDataInputSchema(
    label: 'Duration (seconds)',
    key: 'duration',
    kind: DartDataInputKind.number,
    required: true,
    defaultValue: 600,
  ),
]);

DartPluginManifest createTwitchPlugin(
  TwitchTransport transport, {
  DartPluginEventHub? eventHub,
}) => DartPluginManifest(
  id: 'twitch',
  name: 'Twitch',
  workspaceBuilder: (context, dataService, providerEvents, registryFuture) =>
      TwitchWorkspace(
        providerEvents: providerEvents,
        registryFuture: registryFuture,
        dataService: dataService,
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
    DartSettingDefinition(id: 'broadcasterId', displayName: 'Broadcaster ID'),
    DartSettingDefinition(id: 'moderatorId', displayName: 'Moderator ID'),
    DartSettingDefinition(
      id: 'refreshToken',
      displayName: 'Refresh Token',
      secret: true,
    ),
  ],
  actions: [
    DartActionDefinition(
      pluginId: 'twitch',
      actionId: 'createClip',
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
    DartActionDefinition(
      pluginId: 'twitch',
      actionId: 'streamMarker',
      displayName: 'Place Stream Marker',
      configSchema: _markerSchema,
      invoke: (config, context) => transport.request(
        'POST',
        '/helix/streams/markers',
        {'broadcaster_id': _id(config, context, 'broadcasterId')},
        {'comment': config['markerName'] ?? ''},
      ),
    ),
    DartActionDefinition(
      pluginId: 'twitch',
      actionId: 'runAd',
      displayName: 'Run Ad',
      configSchema: _adSchema,
      invoke: (config, context) => transport.request(
        'POST',
        '/helix/channels/commercial',
        {'broadcaster_id': _id(config, context, 'broadcasterId')},
        {'length': config['duration'] ?? 30},
      ),
    ),
    DartActionDefinition(
      pluginId: 'twitch',
      actionId: 'snoozeAds',
      displayName: 'Snooze Ads',
      configSchema: _twitchObject('Twitch ad schedule', [_broadcaster]),
      invoke: (config, context) => transport.request(
        'POST',
        '/helix/channels/ads/schedule/snooze',
        {'broadcaster_id': _id(config, context, 'broadcasterId')},
        {},
      ),
    ),
    DartActionDefinition(
      pluginId: 'twitch',
      actionId: 'createPrediction',
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
    DartActionDefinition(
      pluginId: 'twitch',
      actionId: 'chat',
      displayName: 'Chat Message',
      configSchema: _chatSchema,
      invoke: (config, context) =>
          transport.request('POST', '/helix/chat/messages', {}, {
            'broadcaster_id': _id(config, context, 'broadcasterId'),
            'sender_id': _id(config, context, 'moderatorId'),
            'message': config['message'],
          }),
    ),
    DartActionDefinition(
      pluginId: 'twitch',
      actionId: 'annoucement',
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
    DartActionDefinition(
      pluginId: 'twitch',
      actionId: 'announcement',
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
    DartActionDefinition(
      pluginId: 'twitch',
      actionId: 'shoutout',
      displayName: 'Shoutout',
      configSchema: _shoutoutSchema,
      invoke: (config, context) =>
          transport.request('POST', '/helix/chat/shoutouts', {
            'from_broadcaster_id': _id(config, context, 'broadcasterId'),
            'moderator_id': _id(config, context, 'moderatorId'),
            'to_broadcaster_id': config['streamer'] ?? config['viewerId'],
          }, {}),
    ),
    DartActionDefinition(
      pluginId: 'twitch',
      actionId: 'setStreamInfo',
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
    DartActionDefinition(
      pluginId: 'twitch',
      actionId: 'createPoll',
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
    DartActionDefinition(
      pluginId: 'twitch',
      actionId: 'startRaid',
      displayName: 'Start Raid',
      configSchema: _raidSchema,
      invoke: (config, context) => transport.request('POST', '/helix/raids', {
        'from_broadcaster_id': _id(config, context, 'broadcasterId'),
        'to_broadcaster_id': config['target'] ?? config['targetId'],
      }, {}),
    ),
    DartActionDefinition(
      pluginId: 'twitch',
      actionId: 'cancelRaid',
      displayName: 'Cancel Raid',
      configSchema: _cancelRaidSchema,
      invoke: (config, context) => transport.request('DELETE', '/helix/raids', {
        'broadcaster_id': _id(config, context, 'broadcasterId'),
      }, {}),
    ),
    DartActionDefinition(
      pluginId: 'twitch',
      actionId: 'listChannelPointRewards',
      displayName: 'List Channel Point Rewards',
      configSchema: _listRewardsSchema,
      invoke: (config, context) =>
          transport.request('GET', '/helix/channel_points/custom_rewards', {
            'broadcaster_id': _id(config, context, 'broadcasterId'),
            if (_bool(config['onlyManageable']))
              'only_manageable_rewards': 'true',
          }, {}),
    ),
    DartActionDefinition(
      pluginId: 'twitch',
      actionId: 'createChannelPointReward',
      displayName: 'Create Channel Point Reward',
      configSchema: _createRewardSchema,
      invoke: (config, context) => transport.request(
        'POST',
        '/helix/channel_points/custom_rewards',
        {'broadcaster_id': _id(config, context, 'broadcasterId')},
        TwitchChannelPointRewardDraft.fromConfig(config).toRequestBody(),
      ),
    ),
    DartActionDefinition(
      pluginId: 'twitch',
      actionId: 'updateChannelPointReward',
      displayName: 'Update Channel Point Reward',
      configSchema: _updateRewardSchema,
      invoke: (config, context) => transport.request(
        'PATCH',
        '/helix/channel_points/custom_rewards',
        {
          'broadcaster_id': _id(config, context, 'broadcasterId'),
          'id': _required(config, 'rewardId', fallback: 'twitchId'),
        },
        TwitchChannelPointRewardDraft.fromConfig(config).toRequestBody(),
      ),
    ),
    DartActionDefinition(
      pluginId: 'twitch',
      actionId: 'deleteChannelPointReward',
      displayName: 'Delete Channel Point Reward',
      configSchema: _rewardIdSchema,
      invoke: (config, context) =>
          transport.request('DELETE', '/helix/channel_points/custom_rewards', {
            'broadcaster_id': _id(config, context, 'broadcasterId'),
            'id': _required(config, 'rewardId', fallback: 'twitchId'),
          }, {}),
    ),
    DartActionDefinition(
      pluginId: 'twitch',
      actionId: 'updateChannelPointRedemption',
      displayName: 'Update Channel Point Redemption',
      configSchema: _redemptionSchema,
      invoke: (config, context) => transport.request(
        'PATCH',
        '/helix/channel_points/custom_rewards/redemptions',
        {
          'broadcaster_id': _id(config, context, 'broadcasterId'),
          'reward_id': _required(config, 'rewardId'),
          'id': _required(config, 'redemptionId'),
        },
        {'status': config['status'] ?? 'FULFILLED'},
      ),
    ),
    DartActionDefinition(
      pluginId: 'twitch',
      actionId: 'timeout',
      displayName: 'Timeout Viewer',
      configSchema: _timeoutSchema,
      invoke: (config, context) =>
          _ban(transport, config, context, includeDuration: true),
    ),
    DartActionDefinition(
      pluginId: 'twitch',
      actionId: 'ban',
      displayName: 'Ban Viewer',
      configSchema: _moderationSchema,
      invoke: (config, context) => _ban(transport, config, context),
    ),
    DartActionDefinition(
      pluginId: 'twitch',
      actionId: 'unban',
      displayName: 'Unban Viewer',
      configSchema: _moderationSchema,
      invoke: (config, context) =>
          transport.request('DELETE', '/helix/moderation/bans', {
            'broadcaster_id': _id(config, context, 'broadcasterId'),
            'moderator_id': _id(config, context, 'moderatorId'),
            'user_id': config['viewerId'],
          }, {}),
    ),
  ],
  triggers: eventHub == null
      ? const []
      : [
          DartTriggerDefinition(
            pluginId: 'twitch',
            triggerId: 'chat',
            displayName: 'Chat Message',
            listen: () => eventHub.stream('chat'),
          ),
          DartTriggerDefinition(
            pluginId: 'twitch',
            triggerId: 'ban',
            displayName: 'Viewer Banned',
            listen: () => eventHub.stream('ban'),
          ),
          DartTriggerDefinition(
            pluginId: 'twitch',
            triggerId: 'timeout',
            displayName: 'Viewer Timed Out',
            listen: () => eventHub.stream('timeout'),
          ),
          for (final eventId in const [
            'adStarted',
            'adEnded',
            'adSchedule',
            'predictionStarted',
            'predictionLocked',
            'predictionSettled',
            'pollStarted',
            'pollEnded',
            'subscription',
            'giftedSub',
            'follow',
            'redemption',
            'bits',
            'watchstreak',
            'raid',
            'raidOut',
            'raidStarted',
            'raidCanceled',
            'hypeTrainStarted',
            'hypeTrainLevelUp',
            'hypeTrainEnded',
            'firstTimeChat',
            'shoutoutSent',
            'shoutoutReceived',
          ])
            DartTriggerDefinition(
              pluginId: 'twitch',
              triggerId: eventId,
              displayName: eventId,
              listen: () => eventHub.stream(eventId),
            ),
        ],
);

String _id(RuntimeMap config, EvaluationContext context, String key) =>
    (config[key] ?? context.contextState[key])?.toString() ?? '';

bool _bool(Object? value, {bool fallback = false}) {
  if (value is bool) return value;
  return switch (value?.toString().toLowerCase()) {
    'true' => true,
    'false' => false,
    _ => fallback,
  };
}

dynamic _clipId(RuntimeMap response) {
  if (response['id'] != null) return response['id'];
  final data = response['data'];
  if (data is List && data.isNotEmpty && data.first is Map) {
    return (data.first as Map)['id'];
  }
  return null;
}

String _required(RuntimeMap config, String key, {String? fallback}) {
  final value = config[key] ?? (fallback == null ? null : config[fallback]);
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty) throw ArgumentError('$key is required.');
  return text;
}

Future<RuntimeMap> _ban(
  TwitchTransport transport,
  RuntimeMap config,
  EvaluationContext context, {
  bool includeDuration = false,
}) {
  final body = <String, dynamic>{
    'user_id': config['viewerId'] ?? config['viewer'],
  };
  if (config['reason'] != null) body['reason'] = config['reason'];
  if (includeDuration && config['duration'] != null) {
    body['duration'] = config['duration'];
  }
  return transport.request('POST', '/helix/moderation/bans', {
    'broadcaster_id': _id(config, context, 'broadcasterId'),
    'moderator_id': _id(config, context, 'moderatorId'),
  }, body);
}
