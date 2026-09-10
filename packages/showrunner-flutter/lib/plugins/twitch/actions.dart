import '../../runtime/expression.dart';
import '../../schema/data_input.dart';
import '../../persistence/resource_repository.dart';
import '../../schema/resource.dart';
import '../registry/plugin_contract.dart';
import '../../services/plugin_event_hub.dart';
import 'channel_points.dart';

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

final _chatEventSchema = _twitchObject('Twitch chat message event', [
  _twitchText('Viewer ID', 'viewerId', required: true),
  _twitchText('Viewer Name', 'viewerName', required: true),
  _twitchText('Platform', 'platform', required: true),
  _twitchText('Message', 'message', required: true, multiline: true),
  _twitchText('Message ID', 'messageId', required: true),
  _twitchText('Badges', 'badges'),
]);

final _viewerEventSchema = _twitchObject('Twitch viewer event', [
  _twitchText('Viewer ID', 'viewerId', required: true),
  _twitchText('Viewer Name', 'viewerName'),
]);

final _bitsEventSchema = _twitchObject('Twitch bits event', [
  _twitchText('Viewer ID', 'viewerId', required: true),
  _twitchText('Viewer Name', 'viewerName'),
  DartDataInputSchema(
    label: 'Bits',
    key: 'bits',
    kind: DartDataInputKind.number,
    required: true,
  ),
  _twitchText('Message', 'message'),
]);

final _subscriptionEventSchema = _twitchObject('Twitch subscription event', [
  _twitchText('Viewer ID', 'viewerId', required: true),
  _twitchText('Viewer Name', 'viewerName'),
  DartDataInputSchema(
    label: 'Tier',
    key: 'tier',
    kind: DartDataInputKind.number,
    required: true,
  ),
  DartDataInputSchema(
    label: 'Total Months',
    key: 'totalMonths',
    kind: DartDataInputKind.number,
  ),
  DartDataInputSchema(
    label: 'Streak Months',
    key: 'streakMonths',
    kind: DartDataInputKind.number,
  ),
  _twitchText('Message', 'message'),
]);

final _giftedSubscriptionEventSchema =
    _twitchObject('Twitch gifted subscription event', [
      _twitchText('Gifter ID', 'gifterId', required: true),
      _twitchText('Gifter Name', 'gifterName'),
      DartDataInputSchema(
        label: 'Tier',
        key: 'tier',
        kind: DartDataInputKind.number,
        required: true,
      ),
      DartDataInputSchema(
        label: 'Subscriptions',
        key: 'subs',
        kind: DartDataInputKind.number,
        required: true,
      ),
    ]);

final _redemptionEventSchema = _twitchObject('Twitch redemption event', [
  _twitchText('Viewer ID', 'viewerId', required: true),
  _twitchText('Viewer Name', 'viewerName'),
  _twitchText('Reward ID', 'rewardId'),
  _twitchText('Reward Name', 'rewardName'),
  _twitchText('User Input', 'userInput'),
  _twitchText('Redemption ID', 'redemptionId'),
]);

final _predictionEventSchema = _twitchObject('Twitch prediction event', [
  _twitchText('Prediction ID', 'predictionId'),
  _twitchText('Title', 'title'),
  _twitchText('Status', 'status'),
]);

final _pollEventSchema = _twitchObject('Twitch poll event', [
  _twitchText('Poll ID', 'pollId'),
  _twitchText('Title', 'title'),
  _twitchText('Status', 'status'),
]);

final _raidEventSchema = _twitchObject('Twitch raid event', [
  _twitchText('Viewer ID', 'viewerId'),
  _twitchText('Viewer Name', 'viewerName'),
  _twitchText('Target Broadcaster ID', 'targetBroadcasterId'),
  DartDataInputSchema(
    label: 'Viewers',
    key: 'viewers',
    kind: DartDataInputKind.number,
  ),
]);

final _eventTypeSchema = _twitchObject('Twitch event', [
  _twitchText('Event Type', 'eventType', required: true),
]);

final _twitchEventSchemas = <String, DartDataInputSchema>{
  'chat': _chatEventSchema,
  'ban': _viewerEventSchema,
  'timeout': _viewerEventSchema,
  'firstTimeChat': _chatEventSchema,
  'bits': _bitsEventSchema,
  'subscription': _subscriptionEventSchema,
  'giftedSub': _giftedSubscriptionEventSchema,
  'follow': _viewerEventSchema,
  'redemption': _redemptionEventSchema,
  'predictionStarted': _predictionEventSchema,
  'predictionLocked': _predictionEventSchema,
  'predictionSettled': _predictionEventSchema,
  'pollStarted': _pollEventSchema,
  'pollEnded': _pollEventSchema,
  'raid': _raidEventSchema,
  'raidOut': _raidEventSchema,
  'shoutoutSent': _viewerEventSchema,
  'shoutoutReceived': _viewerEventSchema,
};

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

final _redemptionTriggerSchema = _twitchObject('Twitch redemption trigger', [
  _twitchText('Reward Twitch ID', 'rewardId'),
]);

final _viewerGroupSchema = _twitchObject('Twitch viewer group', [
  _twitchText('Group resource ID', 'group', required: true),
  _twitchText('Viewer ID', 'viewer', required: true),
]);

final _clearViewerGroupSchema = _twitchObject('Twitch viewer group', [
  _twitchText('Group resource ID', 'group', required: true),
]);

DartPluginManifest createTwitchPlugin(
  TwitchTransport transport, {
  DartPluginEventHub? eventHub,
  ResourceRepository? viewerGroupRepository,
}) => DartPluginManifest(
  id: PluginId('twitch'),
  name: 'Twitch',
  states: const [
    StateSpec(
      id: StateId('connection'),
      displayName: 'Connection',
      initialValue: 'unconfigured',
    ),
    StateSpec(id: StateId('adSnoozeRefresh'), displayName: 'Ad Snooze Refresh'),
    StateSpec(id: StateId('adSnoozes'), displayName: 'Ad Snoozes'),
    StateSpec(id: StateId('adTimer'), displayName: 'Ad Timer'),
    StateSpec(id: StateId('category'), displayName: 'Category'),
    StateSpec(id: StateId('followers'), displayName: 'Followers'),
    StateSpec(id: StateId('hypeTrainExists'), displayName: 'Hype Train Exists'),
    StateSpec(id: StateId('hypeTrainGoal'), displayName: 'Hype Train Goal'),
    StateSpec(id: StateId('hypeTrainLevel'), displayName: 'Hype Train Level'),
    StateSpec(
      id: StateId('hypeTrainProgress'),
      displayName: 'Hype Train Progress',
    ),
    StateSpec(id: StateId('hypeTrainTotal'), displayName: 'Hype Train Total'),
    StateSpec(id: StateId('inAdBreak'), displayName: 'In Ad Break'),
    StateSpec(id: StateId('lastFollower'), displayName: 'Last Follower'),
    StateSpec(id: StateId('lastSubscriber'), displayName: 'Last Subscriber'),
    StateSpec(id: StateId('live'), displayName: 'Live'),
    StateSpec(id: StateId('nextAdDuration'), displayName: 'Next Ad Duration'),
    StateSpec(id: StateId('nextAdTimer'), displayName: 'Next Ad Timer'),
    StateSpec(id: StateId('pollId'), displayName: 'Poll ID'),
    StateSpec(id: StateId('pollTitle'), displayName: 'Poll Title'),
    StateSpec(
      id: StateId('predictionChoiceNames'),
      displayName: 'Prediction Choice Names',
    ),
    StateSpec(
      id: StateId('predictionChoiceTotals'),
      displayName: 'Prediction Choice Totals',
    ),
    StateSpec(
      id: StateId('predictionExists'),
      displayName: 'Prediction Exists',
    ),
    StateSpec(id: StateId('predictionId'), displayName: 'Prediction ID'),
    StateSpec(id: StateId('predictionTitle'), displayName: 'Prediction Title'),
    StateSpec(id: StateId('predictionTotal'), displayName: 'Prediction Total'),
    StateSpec(id: StateId('prerollFreeTime'), displayName: 'Preroll Free Time'),
    StateSpec(id: StateId('raidTarget'), displayName: 'Raid Target'),
    StateSpec(id: StateId('raidTimer'), displayName: 'Raid Timer'),
    StateSpec(
      id: StateId('subscriberPoints'),
      displayName: 'Subscriber Points',
    ),
    StateSpec(id: StateId('subscribers'), displayName: 'Subscribers'),
    StateSpec(id: StateId('title'), displayName: 'Title'),
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
    SettingSpec(id: SettingId('broadcasterId'), displayName: 'Broadcaster ID'),
    SettingSpec(id: SettingId('moderatorId'), displayName: 'Moderator ID'),
    SettingSpec(
      id: SettingId('refreshToken'),
      displayName: 'Refresh Token',
      secret: true,
    ),
  ],
  actions: [
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
    ActionSpec<Map<String, dynamic>, Object?>(
      pluginId: PluginId('twitch'),
      actionId: ActionId('listChannelPointRewards'),
      displayName: 'List Channel Point Rewards',
      configSchema: _listRewardsSchema,
      invoke: (config, context) =>
          transport.request('GET', '/helix/channel_points/custom_rewards', {
            'broadcaster_id': _id(config, context, 'broadcasterId'),
            if (_bool(config['onlyManageable']))
              'only_manageable_rewards': 'true',
          }, {}),
    ),
    ActionSpec<Map<String, dynamic>, Object?>(
      pluginId: PluginId('twitch'),
      actionId: ActionId('createChannelPointReward'),
      displayName: 'Create Channel Point Reward',
      configSchema: _createRewardSchema,
      invoke: (config, context) => transport.request(
        'POST',
        '/helix/channel_points/custom_rewards',
        {'broadcaster_id': _id(config, context, 'broadcasterId')},
        TwitchChannelPointRewardDraft.fromConfig(config).toRequestBody(),
      ),
    ),
    ActionSpec<Map<String, dynamic>, Object?>(
      pluginId: PluginId('twitch'),
      actionId: ActionId('updateChannelPointReward'),
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
    ActionSpec<Map<String, dynamic>, Object?>(
      pluginId: PluginId('twitch'),
      actionId: ActionId('deleteChannelPointReward'),
      displayName: 'Delete Channel Point Reward',
      configSchema: _rewardIdSchema,
      invoke: (config, context) =>
          transport.request('DELETE', '/helix/channel_points/custom_rewards', {
            'broadcaster_id': _id(config, context, 'broadcasterId'),
            'id': _required(config, 'rewardId', fallback: 'twitchId'),
          }, {}),
    ),
    ActionSpec<Map<String, dynamic>, Object?>(
      pluginId: PluginId('twitch'),
      actionId: ActionId('updateChannelPointRedemption'),
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
    ActionSpec<Map<String, dynamic>, Object?>(
      pluginId: PluginId('twitch'),
      actionId: ActionId('timeout'),
      displayName: 'Timeout Viewer',
      configSchema: _timeoutSchema,
      invoke: (config, context) =>
          _ban(transport, config, context, includeDuration: true),
    ),
    ActionSpec<Map<String, dynamic>, Object?>(
      pluginId: PluginId('twitch'),
      actionId: ActionId('ban'),
      displayName: 'Ban Viewer',
      configSchema: _moderationSchema,
      invoke: (config, context) => _ban(transport, config, context),
    ),
    ActionSpec<Map<String, dynamic>, Object?>(
      pluginId: PluginId('twitch'),
      actionId: ActionId('unban'),
      displayName: 'Unban Viewer',
      configSchema: _moderationSchema,
      invoke: (config, context) =>
          transport.request('DELETE', '/helix/moderation/bans', {
            'broadcaster_id': _id(config, context, 'broadcasterId'),
            'moderator_id': _id(config, context, 'moderatorId'),
            'user_id': config['viewerId'],
          }, {}),
    ),
    ActionSpec<Map<String, dynamic>, Object?>(
      pluginId: PluginId('twitch'),
      actionId: ActionId('addViewerToGroup'),
      displayName: 'Add Viewer to Group',
      configSchema: _viewerGroupSchema,
      invoke: (config, context) =>
          _updateViewerGroup(viewerGroupRepository, config, add: true),
    ),
    ActionSpec<Map<String, dynamic>, Object?>(
      pluginId: PluginId('twitch'),
      actionId: ActionId('removeViewerFromGroup'),
      displayName: 'Remove Viewer from Group',
      configSchema: _viewerGroupSchema,
      invoke: (config, context) =>
          _updateViewerGroup(viewerGroupRepository, config, add: false),
    ),
    ActionSpec<Map<String, dynamic>, Object?>(
      pluginId: PluginId('twitch'),
      actionId: ActionId('clearViewerGroup'),
      displayName: 'Clear Viewer Group',
      configSchema: _clearViewerGroupSchema,
      invoke: (config, context) =>
          _clearViewerGroup(viewerGroupRepository, config),
    ),
  ],
  triggers: [
    TriggerSpec<Map<String, dynamic>, Map<String, dynamic>>(
      pluginId: PluginId('twitch'),
      triggerId: TriggerId('chat'),
      displayName: 'Chat Message',
      listen: () => _twitchEventStream(eventHub, 'chat'),
      eventSchema: _chatEventSchema,
    ),
    TriggerSpec<Map<String, dynamic>, Map<String, dynamic>>(
      pluginId: PluginId('twitch'),
      triggerId: TriggerId('ban'),
      displayName: 'Viewer Banned',
      listen: () => _twitchEventStream(eventHub, 'ban'),
      eventSchema: _viewerEventSchema,
    ),
    TriggerSpec<Map<String, dynamic>, Map<String, dynamic>>(
      pluginId: PluginId('twitch'),
      triggerId: TriggerId('timeout'),
      displayName: 'Viewer Timed Out',
      listen: () => _twitchEventStream(eventHub, 'timeout'),
      eventSchema: _viewerEventSchema,
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
      'beforeRaid',
      'walkon',
    ])
      TriggerSpec<Map<String, dynamic>, Map<String, dynamic>>(
        pluginId: PluginId('twitch'),
        triggerId: TriggerId(eventId),
        displayName: eventId,
        listen: () => _twitchEventStream(eventHub, eventId),
        configSchema: eventId == 'redemption' ? _redemptionTriggerSchema : null,
        eventSchema: eventId == 'redemption'
            ? _redemptionEventSchema
            : (_twitchEventSchemas[eventId] ?? _eventTypeSchema),
        matches: eventId == 'redemption' ? _matchesRedemption : null,
      ),
  ],
);

Stream<RuntimeMap> _twitchEventStream(
  DartPluginEventHub? eventHub,
  String eventId,
) => eventHub?.stream(eventId) ?? const Stream<RuntimeMap>.empty();

String _id(RuntimeMap config, EvaluationContext context, String key) =>
    (config[key] ?? context.contextState[key])?.toString() ?? '';

Future<Object?> _updateViewerGroup(
  ResourceRepository? repository,
  RuntimeMap config, {
  required bool add,
}) async {
  final resource = await _loadViewerGroup(repository, config['group']);
  final viewer = config['viewer']?.toString().trim() ?? '';
  if (viewer.isEmpty) throw ArgumentError('viewer is required.');
  final userIds = {
    ...((resource.config['userIds'] as List?) ?? const []).map(
      (value) => value.toString(),
    ),
  };
  if (add) {
    userIds.add(viewer);
  } else {
    userIds.remove(viewer);
  }
  await repository!.save(
    ResourceData(
      id: resource.id,
      config: {...resource.config, 'userIds': userIds.toList()..sort()},
      state: resource.state,
    ),
  );
  return {
    'group': resource.id,
    'viewer': viewer,
    'present': userIds.contains(viewer),
  };
}

Future<Object?> _clearViewerGroup(
  ResourceRepository? repository,
  RuntimeMap config,
) async {
  final resource = await _loadViewerGroup(repository, config['group']);
  await repository!.save(
    ResourceData(
      id: resource.id,
      config: {...resource.config, 'userIds': <String>[]},
      state: resource.state,
    ),
  );
  return {'group': resource.id, 'cleared': true};
}

Future<ResourceData> _loadViewerGroup(
  ResourceRepository? repository,
  Object? value,
) async {
  if (repository == null) {
    throw StateError('Twitch viewer group storage is not configured.');
  }
  final groupId = value is Map ? value['id']?.toString() : value?.toString();
  final normalized = groupId?.trim() ?? '';
  if (normalized.isEmpty ||
      normalized.contains('/') ||
      normalized.contains('\\')) {
    throw ArgumentError('A valid viewer group resource ID is required.');
  }
  final resource = await repository.load(normalized);
  if (resource == null) {
    throw StateError('Twitch viewer group not found: $normalized');
  }
  return resource;
}

bool _bool(Object? value, {bool fallback = false}) {
  if (value is bool) return value;
  return switch (value?.toString().toLowerCase()) {
    'true' => true,
    'false' => false,
    _ => fallback,
  };
}

bool _matchesRedemption(RuntimeMap config, RuntimeMap payload) {
  final rewardId = config['rewardId']?.toString().trim() ?? '';
  if (rewardId.isEmpty) return true;
  final payloadReward =
      payload['rewardId'] ??
      (payload['reward'] is Map ? (payload['reward'] as Map)['id'] : null);
  return rewardId == payloadReward?.toString().trim();
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
