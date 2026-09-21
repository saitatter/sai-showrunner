part of '../actions.dart';

List<DartActionContract> _obsSourceActions(ObsTransport transport) => [
  ActionSpec<ObsSourceVisibilityConfig, RuntimeMap>(
    pluginId: PluginId('obs'),
    actionId: ActionId('source'),
    displayName: 'Source Visibility',
    configSchema: _sourceVisibilityConfigSchema,
    configCodec: obsSourceVisibilityConfigCodec,
    invoke: (config, context) async {
      var enabled = config.mode;
      if (enabled == ObsToggleMode.toggle) {
        final response = await transport.call('GetSceneItemEnabled', {
          'sceneName': config.scene,
          'sceneItemId': config.source,
        });
        enabled = response['sceneItemEnabled'] == true
            ? ObsToggleMode.disabled
            : ObsToggleMode.enabled;
      }
      await transport.call('SetSceneItemEnabled', {
        'sceneName': config.scene,
        'sceneItemId': config.source,
        'sceneItemEnabled': enabled == ObsToggleMode.enabled,
      });
      return {'sourceEnabled': enabled == ObsToggleMode.enabled};
    },
  ),
  ActionSpec<ObsSourceNameConfig, RuntimeMap>(
    pluginId: PluginId('obs'),
    actionId: ActionId('getInputSettings'),
    displayName: 'Get Input Settings',
    configSchema: const DartDataInputSchema(
      label: 'Input settings query',
      kind: DartDataInputKind.object,
      fields: [
        DartDataInputSchema(
          label: 'Source name',
          key: 'sourceName',
          kind: DartDataInputKind.text,
          required: true,
        ),
      ],
    ),
    configCodec: obsSourceNameConfigCodec,
    invoke: (config, context) =>
        transport.call('GetInputSettings', {'inputName': config.sourceName}),
  ),
  ActionSpec<ObsInputSettingsConfig, RuntimeMap>(
    pluginId: PluginId('obs'),
    actionId: ActionId('setInputSettings'),
    displayName: 'Set Input Settings',
    configSchema: const DartDataInputSchema(
      label: 'Input settings',
      kind: DartDataInputKind.object,
      fields: [
        DartDataInputSchema(
          label: 'Source name',
          key: 'sourceName',
          kind: DartDataInputKind.text,
          required: true,
        ),
        DartDataInputSchema(
          label: 'Input settings',
          key: 'inputSettings',
          kind: DartDataInputKind.object,
          required: true,
        ),
      ],
    ),
    configCodec: obsInputSettingsConfigCodec,
    invoke: (config, context) => transport.call('SetInputSettings', {
      'inputName': config.sourceName,
      'inputSettings': config.inputSettings,
    }),
  ),
  ActionSpec<ObsFilterConfig, RuntimeMap>(
    pluginId: PluginId('obs'),
    actionId: ActionId('filter'),
    displayName: 'Filter Visibility',
    configSchema: _filterConfigSchema,
    configCodec: obsFilterConfigCodec,
    invoke: (config, context) async {
      var enabled = config.mode;
      if (enabled == ObsToggleMode.toggle) {
        final response = await transport.call('GetSourceFilter', {
          'sourceName': config.sourceName,
          'filterName': config.filterName,
        });
        enabled = response['filterEnabled'] == true
            ? ObsToggleMode.disabled
            : ObsToggleMode.enabled;
      }
      await transport.call('SetSourceFilterEnabled', {
        'sourceName': config.sourceName,
        'filterName': config.filterName,
        'filterEnabled': enabled == ObsToggleMode.enabled,
      });
      return {'filterEnabled': enabled == ObsToggleMode.enabled};
    },
  ),
  ActionSpec<ObsTextConfig, RuntimeMap>(
    pluginId: PluginId('obs'),
    actionId: ActionId('text'),
    displayName: 'Set Source Text',
    configSchema: _textConfigSchema,
    configCodec: obsTextConfigCodec,
    invoke: (config, context) => transport.call('SetInputSettings', {
      'inputName': config.sourceName,
      'inputSettings': {'text': config.text},
    }),
  ),
  ActionSpec<ObsMediaActionConfig, RuntimeMap>(
    pluginId: PluginId('obs'),
    actionId: ActionId('mediaAction'),
    displayName: 'Media Controls',
    configSchema: _mediaActionConfigSchema,
    configCodec: obsMediaActionConfigCodec,
    invoke: (config, context) => transport.call('TriggerMediaInputAction', {
      'inputName': config.source,
      'mediaAction': _mediaAction(config.action),
    }),
  ),
  ActionSpec<ObsPlayMediaConfig, Object?>(
    pluginId: PluginId('obs'),
    actionId: ActionId('playMedia'),
    displayName: 'Play Media',
    configSchema: _playMediaConfigSchema,
    configCodec: obsPlayMediaConfigCodec,
    invoke: (config, context) async {
      final sceneName = config.scene;
      final sceneItemId = config.source;
      if (sceneName == null || sceneItemId == null) return null;
      final enabled = await transport.call('GetSceneItemEnabled', {
        'sceneName': sceneName,
        'sceneItemId': sceneItemId,
      });
      if (enabled['sceneItemEnabled'] != true) {
        await transport.call('SetSceneItemEnabled', {
          'sceneName': sceneName,
          'sceneItemId': sceneItemId,
          'sceneItemEnabled': true,
        });
      }
      await transport.call('TriggerMediaInputAction', {
        'inputName': config.sourceName ?? config.source,
        'mediaAction': 'OBS_WEBSOCKET_MEDIA_INPUT_ACTION_RESTART',
      });
      return {'playing': true};
    },
  ),
  ActionSpec<ObsImageConfig, RuntimeMap>(
    pluginId: PluginId('obs'),
    actionId: ActionId('setImage'),
    displayName: 'Set Image Source',
    configSchema: _setImageConfigSchema,
    configCodec: obsImageConfigCodec,
    invoke: (config, context) => transport.call('SetInputSettings', {
      'inputName': config.sourceName,
      'inputSettings': {'file': config.image},
    }),
  ),
  ActionSpec<ObsTransformConfig, RuntimeMap>(
    pluginId: PluginId('obs'),
    actionId: ActionId('transform'),
    displayName: 'Source Transform',
    configSchema: _transformConfigSchema,
    configCodec: obsTransformConfigCodec,
    invoke: (config, context) => transport.call('SetSceneItemTransform', {
      'sceneName': config.scene,
      'sceneItemId': config.source,
      'sceneItemTransform': obsTransformToWebSocket(config.transform),
    }),
  ),
];
