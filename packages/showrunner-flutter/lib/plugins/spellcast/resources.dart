import '../registry/plugin_contract.dart';

final _spellHookResource = ResourceSpec(
  ownerId: const PluginId('spellcast'),
  resourceTypeId: const ResourceTypeId('SpellHook'),
  displayName: 'Spellcast Spell',
  storageDirectory: 'spellcast/spells',
  defaultConfigFactory: (name) => {
    'name': name,
    'spellId': '',
    'spellData': {
      'enabled': false,
      'description': '',
      'bits': 10,
      'color': '#719ece',
    },
  },
);

final List<DartResourceContract> spellcastResourceContracts = List.unmodifiable(
  [_spellHookResource],
);
