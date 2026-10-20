import '../registry/plugin_contract.dart';

final _obsConnectionResource = ResourceSpec(
  ownerId: const PluginId('obs'),
  resourceTypeId: const ResourceTypeId('OBSConnection'),
  displayName: 'OBS Connection',
  storageDirectory: 'obs/connections',
  defaultConfigFactory: (name) => {
    'name': name,
    'host': '127.0.0.1',
    'port': 4455,
    'local': true,
  },
);

final List<DartResourceContract> obsResourceContracts = List.unmodifiable([
  _obsConnectionResource,
]);
