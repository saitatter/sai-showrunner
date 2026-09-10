part of '../actions.dart';

List<ActionSpec<Map<String, dynamic>, Object?>> _obsAudioActions(
  ObsTransport transport,
) => [
  ActionSpec<Map<String, dynamic>, Object?>(
    pluginId: PluginId('obs'),
    actionId: ActionId('mute'),
    displayName: 'Mute Source',
    configSchema: _muteConfigSchema,
    invoke: (config, context) async {
      var muted = _toggleValue(config['muted']);
      if (muted == 'toggle') {
        final status = await transport.call('GetInputMute', {
          'inputName': config['source'],
        });
        muted = !(status['inputMuted'] == true);
      }
      await transport.call('SetInputMute', {
        'inputName': config['source'],
        'inputMuted': muted == true,
      });
      return {'audioMuted': muted == true};
    },
  ),
  ActionSpec<Map<String, dynamic>, Object?>(
    pluginId: PluginId('obs'),
    actionId: ActionId('changeVolume'),
    displayName: 'Change Volume',
    configSchema: _volumeConfigSchema,
    invoke: (config, context) => transport.call('SetInputVolume', {
      'inputName': config['source'],
      'inputVolumeDb': _sliderToDb(config['volume']),
    }),
  ),
];
