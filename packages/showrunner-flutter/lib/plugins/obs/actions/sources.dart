part of '../actions.dart';

List<ActionSpec<Map<String, dynamic>, Object?>> _obsSourceActions(
  ObsTransport transport,
) => [
  ActionSpec<Map<String, dynamic>, Object?>(
    pluginId: PluginId('obs'),
    actionId: ActionId('source'),
    displayName: 'Source Visibility',
    configSchema: _sourceVisibilityConfigSchema,
    invoke: (config, context) async {
      var enabled = _toggleValue(config['enabled']);
      if (enabled == 'toggle') {
        final response = await transport.call('GetSceneItemEnabled', {
          'sceneName': config['scene'],
          'sceneItemId': config['source'],
        });
        enabled = !(response['sceneItemEnabled'] == true);
      }
      await transport.call('SetSceneItemEnabled', {
        'sceneName': config['scene'],
        'sceneItemId': config['source'],
        'sceneItemEnabled': enabled == true,
      });
      return {'sourceEnabled': enabled == true};
    },
  ),
  ActionSpec<Map<String, dynamic>, Object?>(
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
    invoke: (config, context) =>
        transport.call('GetInputSettings', {'inputName': config['sourceName']}),
  ),
  ActionSpec<Map<String, dynamic>, Object?>(
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
    invoke: (config, context) => transport.call('SetInputSettings', {
      'inputName': config['sourceName'],
      'inputSettings': config['inputSettings'],
    }),
  ),
  ActionSpec<Map<String, dynamic>, Object?>(
    pluginId: PluginId('obs'),
    actionId: ActionId('filter'),
    displayName: 'Filter Visibility',
    configSchema: _filterConfigSchema,
    invoke: (config, context) async {
      var enabled = _toggleValue(config['filterEnabled']);
      if (enabled == 'toggle') {
        final response = await transport.call('GetSourceFilter', {
          'sourceName': config['sourceName'],
          'filterName': config['filterName'],
        });
        enabled = !(response['filterEnabled'] == true);
      }
      await transport.call('SetSourceFilterEnabled', {
        'sourceName': config['sourceName'],
        'filterName': config['filterName'],
        'filterEnabled': enabled == true,
      });
      return {'filterEnabled': enabled == true};
    },
  ),
  ActionSpec<Map<String, dynamic>, Object?>(
    pluginId: PluginId('obs'),
    actionId: ActionId('text'),
    displayName: 'Set Source Text',
    configSchema: _textConfigSchema,
    invoke: (config, context) => transport.call('SetInputSettings', {
      'inputName': config['sourceName'],
      'inputSettings': {'text': config['text']},
    }),
  ),
  ActionSpec<Map<String, dynamic>, Object?>(
    pluginId: PluginId('obs'),
    actionId: ActionId('mediaAction'),
    displayName: 'Media Controls',
    configSchema: _mediaActionConfigSchema,
    invoke: (config, context) => transport.call('TriggerMediaInputAction', {
      'inputName': config['source'],
      'mediaAction': _mediaAction(config['action']),
    }),
  ),
  ActionSpec<Map<String, dynamic>, Object?>(
    pluginId: PluginId('obs'),
    actionId: ActionId('playMedia'),
    displayName: 'Play Media',
    configSchema: _playMediaConfigSchema,
    invoke: (config, context) async {
      final sceneName = config['scene'];
      final sceneItemId = config['source'];
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
        'inputName': config['sourceName'] ?? config['source'],
        'mediaAction': 'OBS_WEBSOCKET_MEDIA_INPUT_ACTION_RESTART',
      });
      return {'playing': true};
    },
  ),
  ActionSpec<Map<String, dynamic>, Object?>(
    pluginId: PluginId('obs'),
    actionId: ActionId('setImage'),
    displayName: 'Set Image Source',
    configSchema: _setImageConfigSchema,
    invoke: (config, context) => transport.call('SetInputSettings', {
      'inputName': config['sourceName'],
      'inputSettings': {'file': config['image']},
    }),
  ),
  ActionSpec<Map<String, dynamic>, Object?>(
    pluginId: PluginId('obs'),
    actionId: ActionId('transform'),
    displayName: 'Source Transform',
    configSchema: _transformConfigSchema,
    invoke: (config, context) => transport.call('SetSceneItemTransform', {
      'sceneName': config['scene'],
      'sceneItemId': config['source'],
      'sceneItemTransform': obsTransformToWebSocket(config['transform']),
    }),
  ),
];
