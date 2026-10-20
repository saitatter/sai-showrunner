import '../registry/plugin_contract.dart';

final _overlayResource = ResourceSpec(
  ownerId: const PluginId('overlays'),
  resourceTypeId: const ResourceTypeId('Overlay'),
  displayName: 'Overlay',
  storageDirectory: 'overlays',
  defaultConfigFactory: (name) => {
    'name': name,
    'size': {'width': 1920, 'height': 1080},
    'widgets': <Map<String, dynamic>>[],
  },
);

final List<DartResourceContract> overlaysResourceContracts = List.unmodifiable([
  _overlayResource,
]);
