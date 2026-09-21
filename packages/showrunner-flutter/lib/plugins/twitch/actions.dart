import '../../runtime/expression.dart';
import '../../schema/data_input.dart';
import '../../persistence/resource_repository.dart';
import '../../schema/resource.dart';
import '../../services/plugin_event_hub.dart';
import '../registry/plugin_contract.dart';
import 'channel_points.dart';
import 'contracts.dart';

part 'actions/chat.dart';
part 'actions/moderation.dart';
part 'actions/stream.dart';
part 'actions/rewards.dart';
part 'actions/ads.dart';

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
}) {
  final chatActions = _twitchChatActions(transport);
  final moderationActions = _twitchModerationActions(
    transport,
    viewerGroupRepository,
  );
  final streamActions = _twitchStreamActions(transport);
  final rewardActions = _twitchRewardActions(transport);
  final adActions = _twitchAdActions(transport);
  return DartPluginManifest(
    id: PluginId('twitch'),
    name: 'Twitch',
    states: const [
      StateSpec(
        id: StateId('connection'),
        displayName: 'Connection',
        initialValue: 'unconfigured',
      ),
      StateSpec(
        id: StateId('adSnoozeRefresh'),
        displayName: 'Ad Snooze Refresh',
      ),
      StateSpec(id: StateId('adSnoozes'), displayName: 'Ad Snoozes'),
      StateSpec(id: StateId('adTimer'), displayName: 'Ad Timer'),
      StateSpec(id: StateId('category'), displayName: 'Category'),
      StateSpec(id: StateId('followers'), displayName: 'Followers'),
      StateSpec(
        id: StateId('hypeTrainExists'),
        displayName: 'Hype Train Exists',
      ),
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
      StateSpec(
        id: StateId('predictionTitle'),
        displayName: 'Prediction Title',
      ),
      StateSpec(
        id: StateId('predictionTotal'),
        displayName: 'Prediction Total',
      ),
      StateSpec(
        id: StateId('prerollFreeTime'),
        displayName: 'Preroll Free Time',
      ),
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
      SettingSpec(
        id: SettingId('broadcasterId'),
        displayName: 'Broadcaster ID',
      ),
      SettingSpec(id: SettingId('moderatorId'), displayName: 'Moderator ID'),
      SettingSpec(
        id: SettingId('refreshToken'),
        displayName: 'Refresh Token',
        secret: true,
      ),
    ],
    actions: [
      _twitchAction(adActions, 'createClip'),
      _twitchAction(streamActions, 'streamMarker'),
      _twitchAction(adActions, 'runAd'),
      _twitchAction(adActions, 'snoozeAds'),
      _twitchAction(streamActions, 'createPrediction'),
      _twitchAction(chatActions, 'chat'),
      _twitchAction(chatActions, 'annoucement'),
      _twitchAction(chatActions, 'announcement'),
      _twitchAction(chatActions, 'shoutout'),
      _twitchAction(streamActions, 'setStreamInfo'),
      _twitchAction(streamActions, 'createPoll'),
      _twitchAction(streamActions, 'startRaid'),
      _twitchAction(streamActions, 'cancelRaid'),
      _twitchAction(rewardActions, 'listChannelPointRewards'),
      _twitchAction(rewardActions, 'createChannelPointReward'),
      _twitchAction(rewardActions, 'updateChannelPointReward'),
      _twitchAction(rewardActions, 'deleteChannelPointReward'),
      _twitchAction(rewardActions, 'updateChannelPointRedemption'),
      _twitchAction(moderationActions, 'timeout'),
      _twitchAction(moderationActions, 'ban'),
      _twitchAction(moderationActions, 'unban'),
      _twitchAction(moderationActions, 'addViewerToGroup'),
      _twitchAction(moderationActions, 'removeViewerFromGroup'),
      _twitchAction(moderationActions, 'clearViewerGroup'),
    ],
    triggers: [
      for (final eventId in const [
        'chat',
        'ban',
        'timeout',
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
        _twitchTrigger(eventId, eventHub),
    ],
  );
}

DartTriggerContract _twitchTrigger(
  String eventId,
  DartPluginEventHub? eventHub,
) {
  switch (eventId) {
    case 'chat':
      return _emptyTwitchTrigger(
        eventId,
        'Chat Message',
        eventHub,
        _chatEventSchema,
        TwitchChatMessageEvent.fromRuntime,
      );
    case 'firstTimeChat':
      return _emptyTwitchTrigger(
        eventId,
        eventId,
        eventHub,
        _chatEventSchema,
        TwitchChatMessageEvent.fromRuntime,
      );
    case 'ban':
      return _emptyTwitchTrigger(
        eventId,
        'Viewer Banned',
        eventHub,
        _viewerEventSchema,
        TwitchViewerEvent.fromRuntime,
      );
    case 'timeout':
      return _emptyTwitchTrigger(
        eventId,
        'Viewer Timed Out',
        eventHub,
        _viewerEventSchema,
        TwitchViewerEvent.fromRuntime,
      );
    case 'bits':
      return _emptyTwitchTrigger(
        eventId,
        eventId,
        eventHub,
        _bitsEventSchema,
        TwitchBitsEvent.fromRuntime,
      );
    case 'subscription':
      return _emptyTwitchTrigger(
        eventId,
        eventId,
        eventHub,
        _subscriptionEventSchema,
        TwitchSubscriptionEvent.fromRuntime,
      );
    case 'giftedSub':
      return _emptyTwitchTrigger(
        eventId,
        eventId,
        eventHub,
        _giftedSubscriptionEventSchema,
        TwitchGiftedSubscriptionEvent.fromRuntime,
      );
    case 'follow':
      return _emptyTwitchTrigger(
        eventId,
        eventId,
        eventHub,
        _viewerEventSchema,
        TwitchViewerEvent.fromRuntime,
      );
    case 'redemption':
      return TriggerSpec<TwitchRedemptionTriggerConfig, TwitchRedemptionEvent>(
        pluginId: PluginId('twitch'),
        triggerId: TriggerId(eventId),
        displayName: eventId,
        listen: () => _twitchEventStream(
          eventHub,
          eventId,
          TwitchRedemptionEvent.fromRuntime,
        ),
        configSchema: _redemptionTriggerSchema,
        eventSchema: _redemptionEventSchema,
        eventDecoder: TwitchRedemptionEvent.fromRuntime,
        eventEncoder: (event) => _encodeTwitchEvent(event),
        configCodec: twitchRedemptionTriggerConfigCodec,
        matches: _matchesRedemption,
      );
    case 'predictionStarted':
    case 'predictionLocked':
    case 'predictionSettled':
      return _emptyTwitchTrigger(
        eventId,
        eventId,
        eventHub,
        _predictionEventSchema,
        TwitchPredictionEvent.fromRuntime,
      );
    case 'pollStarted':
    case 'pollEnded':
      return _emptyTwitchTrigger(
        eventId,
        eventId,
        eventHub,
        _pollEventSchema,
        TwitchPollEvent.fromRuntime,
      );
    case 'raid':
    case 'raidOut':
      return _emptyTwitchTrigger(
        eventId,
        eventId,
        eventHub,
        _raidEventSchema,
        TwitchRaidEvent.fromRuntime,
      );
    case 'raidStarted':
    case 'raidCanceled':
      return _emptyTwitchTrigger(
        eventId,
        eventId,
        eventHub,
        _eventTypeSchema,
        TwitchEventTypeEvent.fromRuntime,
      );
    case 'shoutoutSent':
    case 'shoutoutReceived':
      return _emptyTwitchTrigger(
        eventId,
        eventId,
        eventHub,
        _viewerEventSchema,
        TwitchViewerEvent.fromRuntime,
      );
    default:
      return _emptyTwitchTrigger(
        eventId,
        eventId,
        eventHub,
        _twitchEventSchemas[eventId] ?? _eventTypeSchema,
        TwitchEventTypeEvent.fromRuntime,
      );
  }
}

TriggerSpec<TwitchEmptyConfig, T> _emptyTwitchTrigger<T>(
  String eventId,
  String displayName,
  DartPluginEventHub? eventHub,
  DartDataInputSchema schema,
  T Function(RuntimeMap) decode,
) => TriggerSpec<TwitchEmptyConfig, T>(
  pluginId: PluginId('twitch'),
  triggerId: TriggerId(eventId),
  displayName: displayName,
  listen: () => _twitchEventStream(eventHub, eventId, decode),
  eventSchema: schema,
  eventDecoder: decode,
  eventEncoder: (event) => _encodeTwitchEvent(event),
  configCodec: twitchEmptyConfigCodec,
);

RuntimeMap _encodeTwitchEvent(Object? event) => switch (event) {
  TwitchChatMessageEvent value => {
    'viewerId': value.viewerId,
    if (value.viewerName != null) 'viewerName': value.viewerName,
    if (value.platform != null) 'platform': value.platform,
    if (value.message != null) 'message': value.message,
    if (value.messageId != null) 'messageId': value.messageId,
    if (value.badges != null) 'badges': value.badges,
  },
  TwitchBitsEvent value => {
    'viewerId': value.viewerId,
    if (value.viewerName != null) 'viewerName': value.viewerName,
    if (value.bits != null) 'bits': value.bits,
    if (value.message != null) 'message': value.message,
  },
  TwitchSubscriptionEvent value => {
    'viewerId': value.viewerId,
    if (value.viewerName != null) 'viewerName': value.viewerName,
    if (value.tier != null) 'tier': value.tier,
    if (value.totalMonths != null) 'totalMonths': value.totalMonths,
    if (value.streakMonths != null) 'streakMonths': value.streakMonths,
    if (value.message != null) 'message': value.message,
  },
  TwitchGiftedSubscriptionEvent value => {
    'gifterId': value.gifterId,
    if (value.gifterName != null) 'gifterName': value.gifterName,
    if (value.tier != null) 'tier': value.tier,
    if (value.subs != null) 'subs': value.subs,
  },
  TwitchRedemptionEvent value => {
    'viewerId': value.viewerId,
    if (value.viewerName != null) 'viewerName': value.viewerName,
    if (value.rewardId != null) 'rewardId': value.rewardId,
    if (value.rewardName != null) 'rewardName': value.rewardName,
    if (value.userInput != null) 'userInput': value.userInput,
    if (value.redemptionId != null) 'redemptionId': value.redemptionId,
  },
  TwitchViewerEvent value => {
    'viewerId': value.viewerId,
    if (value.viewerName != null) 'viewerName': value.viewerName,
  },
  TwitchPredictionEvent value => {
    if (value.predictionId != null) 'predictionId': value.predictionId,
    if (value.title != null) 'title': value.title,
    if (value.status != null) 'status': value.status,
  },
  TwitchPollEvent value => {
    if (value.pollId != null) 'pollId': value.pollId,
    if (value.title != null) 'title': value.title,
    if (value.status != null) 'status': value.status,
  },
  TwitchRaidEvent value => {
    if (value.viewerId != null) 'viewerId': value.viewerId,
    if (value.viewerName != null) 'viewerName': value.viewerName,
    if (value.targetBroadcasterId != null)
      'targetBroadcasterId': value.targetBroadcasterId,
    if (value.viewers != null) 'viewers': value.viewers,
  },
  TwitchEventTypeEvent value => {
    if (value.eventType != null) 'eventType': value.eventType,
  },
  _ => throw StateError('Unsupported Twitch event type: ${event.runtimeType}'),
};

DartActionContract _twitchAction(List<DartActionContract> actions, String id) =>
    actions.firstWhere((action) => action.actionId.value == id);

Stream<T> _twitchEventStream<T>(
  DartPluginEventHub? eventHub,
  String eventId,
  T Function(RuntimeMap) decode,
) => eventHub?.stream(eventId).map(decode) ?? const Stream.empty();

String _idValue(String? value, EvaluationContext context, String key) =>
    (value ?? context.contextState[key])?.toString() ?? '';

Future<Object?> _updateViewerGroup(
  ResourceRepository? repository,
  TwitchViewerGroupConfig config, {
  required bool add,
}) async {
  final resource = await _loadViewerGroup(repository, config.group);
  final viewer = config.viewer?.trim() ?? '';
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
  TwitchClearViewerGroupConfig config,
) async {
  final resource = await _loadViewerGroup(repository, config.group);
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

bool _matchesRedemption(
  TwitchRedemptionTriggerConfig config,
  TwitchRedemptionEvent payload,
) {
  final rewardId = config.rewardId?.trim() ?? '';
  if (rewardId.isEmpty) return true;
  return rewardId == payload.rewardId?.trim();
}

dynamic _clipId(RuntimeMap response) {
  if (response['id'] != null) return response['id'];
  final data = response['data'];
  if (data is List && data.isNotEmpty && data.first is Map) {
    return (data.first as Map)['id'];
  }
  return null;
}

String _requiredValue(String? value, String key) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) throw ArgumentError('$key is required.');
  return text;
}

Future<RuntimeMap> _ban(
  TwitchTransport transport,
  TwitchModerationConfig config,
  EvaluationContext context, {
  num? duration,
}) {
  final body = <String, dynamic>{'user_id': config.viewerId ?? config.viewer};
  if (config.reason != null) body['reason'] = config.reason;
  if (duration != null) body['duration'] = duration;
  return transport.request('POST', '/helix/moderation/bans', {
    'broadcaster_id': _idValue(config.broadcasterId, context, 'broadcasterId'),
    'moderator_id': _idValue(config.moderatorId, context, 'moderatorId'),
  }, body);
}
