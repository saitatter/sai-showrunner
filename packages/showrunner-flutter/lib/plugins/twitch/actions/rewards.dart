part of '../actions.dart';

List<DartActionContract> _twitchRewardActions(TwitchTransport transport) => [
  ActionSpec<TwitchListChannelPointRewardsConfig, RuntimeMap>(
    pluginId: PluginId('twitch'),
    actionId: ActionId('listChannelPointRewards'),
    displayName: 'List Channel Point Rewards',
    configSchema: _listRewardsSchema,
    configCodec: twitchListChannelPointRewardsConfigCodec,
    invoke: (config, context) =>
        transport.request('GET', '/helix/channel_points/custom_rewards', {
          'broadcaster_id': _idValue(
            config.broadcasterId,
            context,
            'broadcasterId',
          ),
          if (config.onlyManageable) 'only_manageable_rewards': 'true',
        }, {}),
  ),
  ActionSpec<TwitchChannelPointRewardConfig, RuntimeMap>(
    pluginId: PluginId('twitch'),
    actionId: ActionId('createChannelPointReward'),
    displayName: 'Create Channel Point Reward',
    configSchema: _createRewardSchema,
    configCodec: twitchChannelPointRewardConfigCodec,
    invoke: (config, context) => transport.request(
      'POST',
      '/helix/channel_points/custom_rewards',
      {
        'broadcaster_id': _idValue(
          config.broadcasterId,
          context,
          'broadcasterId',
        ),
      },
      _rewardDraft(config).toRequestBody(),
    ),
  ),
  ActionSpec<TwitchChannelPointRewardConfig, RuntimeMap>(
    pluginId: PluginId('twitch'),
    actionId: ActionId('updateChannelPointReward'),
    displayName: 'Update Channel Point Reward',
    configSchema: _updateRewardSchema,
    configCodec: twitchChannelPointRewardConfigCodec,
    invoke: (config, context) => transport.request(
      'PATCH',
      '/helix/channel_points/custom_rewards',
      {
        'broadcaster_id': _idValue(
          config.broadcasterId,
          context,
          'broadcasterId',
        ),
        'id': _requiredValue(config.rewardId, 'rewardId'),
      },
      _rewardDraft(config).toRequestBody(),
    ),
  ),
  ActionSpec<TwitchRewardIdConfig, RuntimeMap>(
    pluginId: PluginId('twitch'),
    actionId: ActionId('deleteChannelPointReward'),
    displayName: 'Delete Channel Point Reward',
    configSchema: _rewardIdSchema,
    configCodec: twitchRewardIdConfigCodec,
    invoke: (config, context) =>
        transport.request('DELETE', '/helix/channel_points/custom_rewards', {
          'broadcaster_id': _idValue(
            config.broadcasterId,
            context,
            'broadcasterId',
          ),
          'id': _requiredValue(config.rewardId, 'rewardId'),
        }, {}),
  ),
  ActionSpec<TwitchRedemptionUpdateConfig, RuntimeMap>(
    pluginId: PluginId('twitch'),
    actionId: ActionId('updateChannelPointRedemption'),
    displayName: 'Update Channel Point Redemption',
    configSchema: _redemptionSchema,
    configCodec: twitchRedemptionUpdateConfigCodec,
    invoke: (config, context) => transport.request(
      'PATCH',
      '/helix/channel_points/custom_rewards/redemptions',
      {
        'broadcaster_id': _idValue(
          config.broadcasterId,
          context,
          'broadcasterId',
        ),
        'reward_id': _requiredValue(config.rewardId, 'rewardId'),
        'id': _requiredValue(config.redemptionId, 'redemptionId'),
      },
      {'status': config.status},
    ),
  ),
];

TwitchChannelPointRewardDraft _rewardDraft(
  TwitchChannelPointRewardConfig config,
) => TwitchChannelPointRewardDraft(
  title: config.title ?? '',
  prompt: config.prompt ?? '',
  backgroundColor: config.backgroundColor ?? '#9147ff',
  cost: (config.cost ?? 1).clamp(1, 1000000),
  userInputRequired: config.userInputRequired,
  skipQueue: config.skipQueue,
  isEnabled: config.isEnabled,
  maxRedemptionsPerStream: _positiveInt(config.maxRedemptionsPerStream),
  maxRedemptionsPerUserPerStream: _positiveInt(
    config.maxRedemptionsPerUserPerStream,
  ),
  cooldown: _positiveInt(config.cooldown),
);

int? _positiveInt(int? value) => value == null || value < 1 ? null : value;
