part of '../actions.dart';

List<ActionSpec<Map<String, dynamic>, Object?>> _obsStreamingActions(
  ObsTransport transport,
) => [
  ActionSpec<Map<String, dynamic>, Object?>(
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
    invoke: (config, context) =>
        transport.call('TriggerHotkeyByName', {'hotkeyName': config['hotkey']}),
  ),
  ActionSpec<Map<String, dynamic>, Object?>(
    pluginId: PluginId('obs'),
    actionId: ActionId('streamStartStop'),
    displayName: 'Stream Start/Stop',
    configSchema: _streamConfigSchema,
    invoke: (config, context) async => _toggle(
      transport,
      _toggleValue(config['streaming']),
      'ToggleStream',
      'StartStream',
      'StopStream',
    ),
  ),
  ActionSpec<Map<String, dynamic>, Object?>(
    pluginId: PluginId('obs'),
    actionId: ActionId('virtualCamStartStop'),
    displayName: 'Virtual Cam Start/Stop',
    configSchema: _virtualCamConfigSchema,
    invoke: (config, context) async => _toggle(
      transport,
      _toggleValue(config['virtualCam']),
      'ToggleVirtualCam',
      'StartVirtualCam',
      'StopVirtualCam',
    ),
  ),
  ActionSpec<Map<String, dynamic>, Object?>(
    pluginId: PluginId('obs'),
    actionId: ActionId('toggleStudioMode'),
    displayName: 'Toggle Studio Mode',
    configSchema: _studioModeConfigSchema,
    invoke: (config, context) async {
      var enabled = _toggleValue(config['studioMode']);
      if (enabled == 'toggle') {
        enabled = !(config['studioModeEnabled'] == true);
      }
      return transport.call('SetStudioModeEnabled', {
        'studioModeEnabled': enabled == true,
      });
    },
  ),
  ActionSpec<Map<String, dynamic>, Object?>(
    pluginId: PluginId('obs'),
    actionId: ActionId('triggerStudioModeTransition'),
    displayName: 'Trigger Studio Mode Transition',
    configSchema: _emptyConfigSchema,
    invoke: (config, context) =>
        transport.call('TriggerStudioModeTransition', {}),
  ),
];
