import '../registry/plugin_contract.dart';

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

final List<DartResourceContract> soundResourceContracts = List.unmodifiable([
  _ttsVoiceResource,
  _audioSplitterResource,
  _soundOutputResource,
  _ttsVoiceProviderResource,
]);
