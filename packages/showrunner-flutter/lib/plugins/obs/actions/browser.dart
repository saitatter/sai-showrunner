part of '../actions.dart';

List<ActionSpec<Map<String, dynamic>, Object?>> _obsBrowserActions(
  ObsTransport transport,
) => [
  ActionSpec<Map<String, dynamic>, Object?>(
    pluginId: PluginId('obs'),
    actionId: ActionId('browserUrl'),
    displayName: 'Set Browser Source URL',
    configSchema: _browserUrlConfigSchema,
    invoke: (config, context) async {
      await transport.call('SetInputSettings', {
        'inputName': config['source'],
        'inputSettings': {'url': config['url']},
        'overlay': true,
      });
      return null;
    },
  ),
  ActionSpec<Map<String, dynamic>, Object?>(
    pluginId: PluginId('obs'),
    actionId: ActionId('browserRefresh'),
    displayName: 'Refresh Browser Source',
    configSchema: _browserRefreshConfigSchema,
    invoke: (config, context) async {
      await transport.call('PressInputPropertiesButton', {
        'inputName': config['source'],
        'propertyName': 'refreshnocache',
      });
      return null;
    },
  ),
  ActionSpec<Map<String, dynamic>, Object?>(
    pluginId: PluginId('obs'),
    actionId: ActionId('refreshBrowser'),
    displayName: 'Refresh Browser',
    configSchema: _refreshBrowserConfigSchema,
    invoke: (config, context) => transport.call('PressInputPropertiesButton', {
      'inputName': config['sourceName'],
      'propertyName': 'refreshnocache',
    }),
  ),
  ActionSpec<Map<String, dynamic>, Object?>(
    pluginId: PluginId('obs'),
    actionId: ActionId('setBrowserURL'),
    displayName: 'Set Browser URL',
    configSchema: _setBrowserUrlConfigSchema,
    invoke: (config, context) => transport.call('SetInputSettings', {
      'inputName': config['sourceName'],
      'inputSettings': {'url': config['url']},
    }),
  ),
];
