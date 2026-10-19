part of '../actions.dart';

List<DartActionContract> _obsBrowserActions(ObsTransport transport) => [
  ActionSpec<ObsSourceUrlConfig, Object?>(
    pluginId: PluginId('obs'),
    actionId: ActionId('browserUrl'),
    displayName: 'Set Browser Source URL',
    configSchema: _browserUrlConfigSchema,
    configCodec: obsSourceUrlConfigCodec,
    invoke: (config, context) async {
      await transport.call('SetInputSettings', {
        'inputName': config.source,
        'inputSettings': {'url': config.url},
        'overlay': true,
      });
      return null;
    },
  ),
  ActionSpec<ObsSourceNameConfig, Object?>(
    pluginId: PluginId('obs'),
    actionId: ActionId('browserRefresh'),
    displayName: 'Refresh Browser Source',
    configSchema: _browserRefreshConfigSchema,
    configCodec: obsSourceNameConfigCodec,
    invoke: (config, context) async {
      await transport.call('PressInputPropertiesButton', {
        'inputName': config.sourceName,
        'propertyName': 'refreshnocache',
      });
      return null;
    },
  ),
  ActionSpec<ObsSourceNameConfig, RuntimeMap>(
    pluginId: PluginId('obs'),
    actionId: ActionId('refreshBrowser'),
    displayName: 'Refresh Browser',
    configSchema: _refreshBrowserConfigSchema,
    configCodec: obsSourceNameConfigCodec,
    invoke: (config, context) => transport.call('PressInputPropertiesButton', {
      'inputName': config.sourceName,
      'propertyName': 'refreshnocache',
    }),
  ),
  ActionSpec<ObsNamedUrlConfig, RuntimeMap>(
    pluginId: PluginId('obs'),
    actionId: ActionId('setBrowserURL'),
    displayName: 'Set Browser URL',
    configSchema: _setBrowserUrlConfigSchema,
    configCodec: obsNamedUrlConfigCodec,
    invoke: (config, context) => transport.call('SetInputSettings', {
      'inputName': config.sourceName,
      'inputSettings': {'url': config.url},
    }),
  ),
];
