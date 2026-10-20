import '../registry/plugin_contract.dart';

final _twitchViewerGroupResource = ResourceSpec(
  ownerId: const PluginId('twitch'),
  resourceTypeId: const ResourceTypeId('CustomTwitchViewerGroup'),
  displayName: 'Twitch Viewer Group',
  storageDirectory: 'twitch/groups',
  defaultConfigFactory: (name) => {'name': name, 'userIds': <String>[]},
);

final _twitchAccountResource = ResourceSpec(
  ownerId: const PluginId('twitch'),
  resourceTypeId: const ResourceTypeId('TwitchAccount'),
  displayName: 'Twitch Account',
  storageDirectory: 'accounts/twitch',
  defaultConfigFactory: (name) => {
    'name': name,
    'twitchId': '',
    'isAffiliate': false,
    'isPartner': false,
    'email': '',
  },
);

final _channelPointRewardResource = ResourceSpec(
  ownerId: const PluginId('twitch'),
  resourceTypeId: const ResourceTypeId('ChannelPointReward'),
  displayName: 'Twitch Channel Point Reward',
  storageDirectory: 'twitch/channelpoints',
  defaultConfigFactory: (name) => {
    'name': name,
    'twitchId': '',
    'controllable': true,
    'transient': false,
    'allowEnable': true,
    'rewardData': {
      'prompt': '',
      'backgroundColor': '#9147ff',
      'userInputRequired': false,
      'cost': 100,
      'cooldown': null,
      'maxRedemptionsPerStream': null,
      'maxRedemptionsPerUserPerStream': null,
      'skipQueue': false,
    },
  },
);

final List<DartResourceContract> twitchResourceContracts = List.unmodifiable([
  _twitchViewerGroupResource,
  _twitchAccountResource,
  _channelPointRewardResource,
]);
