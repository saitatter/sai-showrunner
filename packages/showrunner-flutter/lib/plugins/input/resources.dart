import '../registry/plugin_contract.dart';

final _gamepadResource = ResourceSpec(
  ownerId: const PluginId('input'),
  resourceTypeId: const ResourceTypeId('Gamepad'),
  displayName: 'Gamepad',
  storageDirectory: 'input/gamepads',
  defaultConfigFactory: (name) => {'name': name, 'id': ''},
);

final List<DartResourceContract> inputResourceContracts = List.unmodifiable([
  _gamepadResource,
]);
