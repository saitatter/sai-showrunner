import '../registry/plugin_contract.dart';

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

final List<DartResourceContract> iotResourceContracts = List.unmodifiable([
  _lightResource,
  _plugResource,
]);
