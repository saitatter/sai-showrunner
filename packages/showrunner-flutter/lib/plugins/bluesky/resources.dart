import '../registry/plugin_contract.dart';

final _blueskyAccountResource = ResourceSpec(
  ownerId: const PluginId('bluesky'),
  resourceTypeId: const ResourceTypeId('BlueSkyAccount'),
  displayName: 'BlueSky Account',
  storageDirectory: 'accounts/bluesky',
  defaultConfigFactory: (name) => {
    'name': name,
    'identifier': '',
    'appPassword': '',
  },
);

final List<DartResourceContract> blueskyResourceContracts = List.unmodifiable([
  _blueskyAccountResource,
]);
