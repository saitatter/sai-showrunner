part of '../actions.dart';

List<DartActionContract> _obsAudioActions(ObsTransport transport) => [
  ActionSpec<ObsMuteConfig, RuntimeMap>(
    pluginId: PluginId('obs'),
    actionId: ActionId('mute'),
    displayName: 'Mute Source',
    configSchema: _muteConfigSchema,
    configCodec: obsMuteConfigCodec,
    invoke: (config, context) async {
      var muted = config.mode;
      if (muted == ObsToggleMode.toggle) {
        final status = await transport.call('GetInputMute', {
          'inputName': config.source,
        });
        muted = status['inputMuted'] == true
            ? ObsToggleMode.disabled
            : ObsToggleMode.enabled;
      }
      await transport.call('SetInputMute', {
        'inputName': config.source,
        'inputMuted': muted == ObsToggleMode.enabled,
      });
      return {'audioMuted': muted == ObsToggleMode.enabled};
    },
  ),
  ActionSpec<ObsVolumeConfig, RuntimeMap>(
    pluginId: PluginId('obs'),
    actionId: ActionId('changeVolume'),
    displayName: 'Change Volume',
    configSchema: _volumeConfigSchema,
    configCodec: obsVolumeConfigCodec,
    invoke: (config, context) => transport.call('SetInputVolume', {
      'inputName': config.source,
      'inputVolumeDb': _sliderToDb(config.volume),
    }),
  ),
];
