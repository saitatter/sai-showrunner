part of '../actions.dart';

List<ActionSpec<Map<String, dynamic>, Object?>> _twitchRewardActions(
  TwitchTransport transport,
) => [
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
];
