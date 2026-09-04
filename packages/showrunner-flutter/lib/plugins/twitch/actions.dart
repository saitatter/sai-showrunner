import '../../runtime/expression.dart';
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
      invoke: (config, context) async {
        final response = await transport.request(
          'POST',
          '/helix/clips',
          {'broadcaster_id': _id(config, context, 'broadcasterId')},
          {'has_delay': config['createAfterDelay'] ?? true},
        );
        return {'clipId': _clipId(response)};
      },
    ),
    DartActionDefinition(
      pluginId: 'twitch',
      actionId: 'streamMarker',
      displayName: 'Place Stream Marker',
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
      invoke: (config, context) => transport.request('POST', '/helix/raids', {
        'from_broadcaster_id': _id(config, context, 'broadcasterId'),
        'to_broadcaster_id': config['target'] ?? config['targetId'],
      }, {}),
    ),
    DartActionDefinition(
      pluginId: 'twitch',
      actionId: 'cancelRaid',
      displayName: 'Cancel Raid',
      invoke: (config, context) => transport.request('DELETE', '/helix/raids', {
        'broadcaster_id': _id(config, context, 'broadcasterId'),
      }, {}),
    ),
    DartActionDefinition(
      pluginId: 'twitch',
      actionId: 'listChannelPointRewards',
      displayName: 'List Channel Point Rewards',
      invoke: (config, context) =>
          transport.request('GET', '/helix/channel_points/custom_rewards', {
            'broadcaster_id': _id(config, context, 'broadcasterId'),
            if (config['onlyManageable'] == true)
              'only_manageable_rewards': 'true',
          }, {}),
    ),
    DartActionDefinition(
      pluginId: 'twitch',
      actionId: 'createChannelPointReward',
      displayName: 'Create Channel Point Reward',
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
      invoke: (config, context) =>
          _ban(transport, config, context, includeDuration: true),
    ),
    DartActionDefinition(
      pluginId: 'twitch',
      actionId: 'ban',
      displayName: 'Ban Viewer',
      invoke: (config, context) => _ban(transport, config, context),
    ),
    DartActionDefinition(
      pluginId: 'twitch',
      actionId: 'unban',
      displayName: 'Unban Viewer',
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
