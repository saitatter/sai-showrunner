import '../registry/plugin_contract.dart';

final _variableResource = ResourceSpec(
  ownerId: const PluginId('variables'),
  resourceTypeId: const ResourceTypeId('Variable'),
  displayName: 'Variable',
  storageDirectory: 'variables',
  defaultConfigFactory: (name) => {
    'name': name,
    'type': 'string',
    'defaultValue': '',
    'persistent': true,
  },
);

final List<DartResourceContract> variablesResourceContracts = List.unmodifiable(
  [_variableResource],
);
