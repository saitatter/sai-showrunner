import '../registry/plugin_contract.dart';

final _wyzeAccountResource = ResourceSpec(
  ownerId: const PluginId('wyze'),
  resourceTypeId: const ResourceTypeId('WyzeAccount'),
  displayName: 'Wyze Account',
  storageDirectory: 'accounts/wyze',
  defaultConfigFactory: (name) => {
    'name': name,
    'email': '',
    'scopes': <String>[],
  },
);

final List<DartResourceContract> wyzeResourceContracts = List.unmodifiable([
  _wyzeAccountResource,
]);
