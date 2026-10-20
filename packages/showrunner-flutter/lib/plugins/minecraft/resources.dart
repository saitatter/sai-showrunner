import '../registry/plugin_contract.dart';

final _rconConnectionResource = ResourceSpec(
  ownerId: const PluginId('minecraft'),
  resourceTypeId: const ResourceTypeId('RCONConnection'),
  displayName: 'RCON Connection',
  storageDirectory: 'minecraft/connections',
  defaultConfigFactory: (name) => {
    'name': name,
    'host': '127.0.0.1',
    'port': 25575,
  },
);

final List<DartResourceContract> minecraftResourceContracts = List.unmodifiable(
  [_rconConnectionResource],
);
