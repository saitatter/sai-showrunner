part of '../actions.dart';

List<DartActionContract> _obsStreamingActions(ObsTransport transport) => [
  ActionSpec<ObsHotkeyConfig, RuntimeMap>(
    pluginId: PluginId('obs'),
    actionId: ActionId('hotkey'),
    displayName: 'Hotkey',
    configSchema: const DartDataInputSchema(
      label: 'Hotkey configuration',
      kind: DartDataInputKind.object,
      fields: [
        DartDataInputSchema(
          label: 'hotkey',
          kind: DartDataInputKind.text,
          required: true,
        ),
      ],
    ),
    configCodec: obsHotkeyConfigCodec,
    invoke: (config, context) =>
        transport.call('TriggerHotkeyByName', {'hotkeyName': config.hotkey}),
  ),
  ActionSpec<ObsToggleConfig, RuntimeMap>(
    pluginId: PluginId('obs'),
    actionId: ActionId('streamStartStop'),
    displayName: 'Stream Start/Stop',
    configSchema: _streamConfigSchema,
    configCodec: obsToggleConfigCodec('streaming'),
    invoke: (config, context) async => _toggle(
      transport,
      config.mode,
      'ToggleStream',
      'StartStream',
      'StopStream',
    ),
  ),
  ActionSpec<ObsToggleConfig, RuntimeMap>(
    pluginId: PluginId('obs'),
    actionId: ActionId('virtualCamStartStop'),
    displayName: 'Virtual Cam Start/Stop',
    configSchema: _virtualCamConfigSchema,
    configCodec: obsToggleConfigCodec('virtualCam'),
    invoke: (config, context) async => _toggle(
      transport,
      config.mode,
      'ToggleVirtualCam',
      'StartVirtualCam',
      'StopVirtualCam',
    ),
  ),
  ActionSpec<ObsStudioModeConfig, RuntimeMap>(
    pluginId: PluginId('obs'),
    actionId: ActionId('toggleStudioMode'),
    displayName: 'Toggle Studio Mode',
    configSchema: _studioModeConfigSchema,
    configCodec: obsStudioModeConfigCodec,
    invoke: (config, context) async {
      var enabled = config.mode;
      if (enabled == ObsToggleMode.toggle) {
        enabled = config.studioModeEnabled == true
            ? ObsToggleMode.disabled
            : ObsToggleMode.enabled;
      }
      return transport.call('SetStudioModeEnabled', {
        'studioModeEnabled': enabled == ObsToggleMode.enabled,
      });
    },
  ),
  ActionSpec<ObsEmptyConfig, RuntimeMap>(
    pluginId: PluginId('obs'),
    actionId: ActionId('triggerStudioModeTransition'),
    displayName: 'Trigger Studio Mode Transition',
    configSchema: _emptyConfigSchema,
    configCodec: obsEmptyConfigCodec,
    invoke: (config, context) =>
        transport.call('TriggerStudioModeTransition', {}),
  ),
];
