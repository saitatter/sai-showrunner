import '../../schema/stream_plan.dart';
import 'plugin_contract.dart';

final _overlayResource = ResourceSpec(
  ownerId: const PluginId('overlays'),
  resourceTypeId: const ResourceTypeId('Overlay'),
  displayName: 'Overlay',
  storageDirectory: 'overlays',
  defaultConfigFactory: (name) => {
    'name': name,
    'size': {'width': 1920, 'height': 1080},
    'widgets': <Map<String, dynamic>>[],
  },
);

final _streamPlanResource = ResourceSpec(
  ownerId: const PluginId('stream-plans'),
  resourceTypeId: const ResourceTypeId('StreamPlan'),
  displayName: 'Stream Plan',
  storageDirectory: 'stream-plans',
  defaultConfigFactory: (name) => {
    'name': name,
    'activationAutomation': emptyInlineAutomation(),
    'deactivationAutomation': emptyInlineAutomation(),
    'segments': <Map<String, dynamic>>[],
  },
);

final _variableResource = ResourceSpec(
  ownerId: const PluginId('variables'),
  resourceTypeId: const ResourceTypeId('Variable'),
  displayName: 'Variable',
  storageDirectory: 'variables',
  defaultConfigFactory: (name) => {
    'name': name,
    'type': 'string',
    'defaultValue': '',
    'persistent': true,
  },
);

final _obsConnectionResource = ResourceSpec(
  ownerId: const PluginId('obs'),
  resourceTypeId: const ResourceTypeId('OBSConnection'),
  displayName: 'OBS Connection',
  storageDirectory: 'obs/connections',
  defaultConfigFactory: (name) => {
    'name': name,
    'host': '127.0.0.1',
    'port': 4455,
    'local': true,
  },
);

final _rconConnectionResource = ResourceSpec(
  ownerId: const PluginId('minecraft'),
  resourceTypeId: const ResourceTypeId('RCONConnection'),
  displayName: 'RCON Connection',
  storageDirectory: 'minecraft/connections',
  defaultConfigFactory: (name) => {
    'name': name,
    'host': '127.0.0.1',
    'port': 25575,
  },
);

final _ttsVoiceResource = ResourceSpec(
  ownerId: const PluginId('sound'),
  resourceTypeId: const ResourceTypeId('TTSVoice'),
  displayName: 'TTS Voice',
  storageDirectory: 'sound/tts',
  defaultConfigFactory: (name) => {
    'name': name,
    'voiceProvider': '',
    'providerConfig': <String, dynamic>{},
  },
);

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

final _discordWebhookResource = ResourceSpec(
  ownerId: const PluginId('discord'),
  resourceTypeId: const ResourceTypeId('DiscordWebhook'),
  displayName: 'Discord Webhook',
  storageDirectory: 'discord/webhooks',
  defaultConfigFactory: (name) => {'name': name, 'webhookUrl': ''},
);

final _blueskyAccountResource = ResourceSpec(
  ownerId: const PluginId('bluesky'),
  resourceTypeId: const ResourceTypeId('BlueSkyAccount'),
  displayName: 'BlueSky Account',
  storageDirectory: 'accounts/bluesky',
  defaultConfigFactory: (name) => {
    'name': name,
    'identifier': '',
    'appPassword': '',
  },
);

final _dashboardResource = ResourceSpec(
  ownerId: const PluginId('dashboards'),
  resourceTypeId: const ResourceTypeId('Dashboard'),
  displayName: 'Dashboard',
  storageDirectory: 'dashboards',
  defaultConfigFactory: (name) => {
    'name': name,
    'pages': <Map<String, dynamic>>[],
    'remoteTwitchIds': <String>[],
    'resourceSlots': <Map<String, dynamic>>[],
  },
);

final _spellHookResource = ResourceSpec(
  ownerId: const PluginId('spellcast'),
  resourceTypeId: const ResourceTypeId('SpellHook'),
  displayName: 'Spellcast Spell',
  storageDirectory: 'spellcast/spells',
  defaultConfigFactory: (name) => {
    'name': name,
    'spellId': '',
    'spellData': {
      'enabled': false,
      'description': '',
      'bits': 10,
      'color': '#719ece',
    },
  },
);

final _audioSplitterResource = ResourceSpec(
  ownerId: const PluginId('sound'),
  resourceTypeId: const ResourceTypeId('AudioSplitterOutput'),
  displayName: 'Audio Splitter',
  storageDirectory: 'sound/splitters',
  defaultConfigFactory: (name) => {
    'name': name,
    'type': 'splitter',
    'redirects': <Map<String, dynamic>>[],
  },
);

final _soundOutputResource = ResourceSpec(
  ownerId: const PluginId('sound'),
  resourceTypeId: const ResourceTypeId('SoundOutput'),
  displayName: 'Sound Output',
  storageDirectory: 'sound/outputs',
  defaultConfigFactory: (name) => {
    'name': name,
    'type': 'system',
    'deviceId': '',
    'isDefault': false,
  },
);

final _ttsVoiceProviderResource = ResourceSpec(
  ownerId: const PluginId('sound'),
  resourceTypeId: const ResourceTypeId('TTSVoiceProvider'),
  displayName: 'TTS Voice Provider',
  storageDirectory: 'sound/tts-providers',
  defaultConfigFactory: (name) => {
    'name': name,
    'provider': '',
    'providerId': '',
    'config': <String, dynamic>{},
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

final _lightResource = ResourceSpec(
  ownerId: const PluginId('iot'),
  resourceTypeId: const ResourceTypeId('Light'),
  displayName: 'Smart Light',
  storageDirectory: 'iot/lights',
  defaultConfigFactory: (name) => {
    'name': name,
    'provider': '',
    'providerId': '',
    'host': '',
    'ip': '',
    'hubKey': '',
    'model': '',
    'resourceType': 'light',
    'target': '',
    'rgbAvailable': true,
    'kelvinAvailable': true,
    'dimmingAvailable': true,
    'transitionsAvailable': true,
  },
);

final _plugResource = ResourceSpec(
  ownerId: const PluginId('iot'),
  resourceTypeId: const ResourceTypeId('Plug'),
  displayName: 'Smart Plug',
  storageDirectory: 'iot/plugs',
  defaultConfigFactory: (name) => {
    'name': name,
    'provider': '',
    'providerId': '',
    'host': '',
    'ip': '',
    'model': '',
  },
);

final _gamepadResource = ResourceSpec(
  ownerId: const PluginId('input'),
  resourceTypeId: const ResourceTypeId('Gamepad'),
  displayName: 'Gamepad',
  storageDirectory: 'input/gamepads',
  defaultConfigFactory: (name) => {'name': name, 'id': ''},
);

final _wyzeAccountResource = ResourceSpec(
  ownerId: const PluginId('wyze'),
  resourceTypeId: const ResourceTypeId('WyzeAccount'),
  displayName: 'Wyze Account',
  storageDirectory: 'accounts/wyze',
  defaultConfigFactory: (name) => {
    'name': name,
    'email': '',
    'scopes': <String>[],
  },
);

/// Resource metadata shared by the Flutter-free plugin manifests.
List<DartResourceContract> builtInResourceSpecsFor(PluginId pluginId) =>
    List.unmodifiable(switch (pluginId.value) {
      'overlays' => [_overlayResource],
      'stream-plans' => [_streamPlanResource],
      'variables' => [_variableResource],
      'obs' => [_obsConnectionResource],
      'minecraft' => [_rconConnectionResource],
      'sound' => [
        _ttsVoiceResource,
        _audioSplitterResource,
        _soundOutputResource,
        _ttsVoiceProviderResource,
      ],
      'twitch' => [
        _twitchViewerGroupResource,
        _twitchAccountResource,
        _channelPointRewardResource,
      ],
      'discord' => [_discordWebhookResource],
      'bluesky' => [_blueskyAccountResource],
      'dashboards' => [_dashboardResource],
      'spellcast' => [_spellHookResource],
      'iot' => [_lightResource, _plugResource],
      'input' => [_gamepadResource],
      'wyze' => [_wyzeAccountResource],
      _ => const <DartResourceContract>[],
    });

DartResourceContract builtInResourceSpec(String resourceType) =>
    builtInResourceSpecsFor(const PluginId('overlays'))
        .followedBy(builtInResourceSpecsFor(const PluginId('stream-plans')))
        .followedBy(builtInResourceSpecsFor(const PluginId('variables')))
        .followedBy(builtInResourceSpecsFor(const PluginId('obs')))
        .followedBy(builtInResourceSpecsFor(const PluginId('minecraft')))
        .followedBy(builtInResourceSpecsFor(const PluginId('sound')))
        .followedBy(builtInResourceSpecsFor(const PluginId('twitch')))
        .followedBy(builtInResourceSpecsFor(const PluginId('discord')))
        .followedBy(builtInResourceSpecsFor(const PluginId('bluesky')))
        .followedBy(builtInResourceSpecsFor(const PluginId('dashboards')))
        .followedBy(builtInResourceSpecsFor(const PluginId('spellcast')))
        .followedBy(builtInResourceSpecsFor(const PluginId('iot')))
        .followedBy(builtInResourceSpecsFor(const PluginId('input')))
        .followedBy(builtInResourceSpecsFor(const PluginId('wyze')))
        .firstWhere(
          (resource) => resource.resourceTypeId.value == resourceType,
          orElse: () => throw ArgumentError.value(
            resourceType,
            'resourceType',
            'Unknown built-in resource type.',
          ),
        );
