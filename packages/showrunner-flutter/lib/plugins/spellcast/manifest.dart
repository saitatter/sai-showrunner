import '../../schema/data_input.dart';
import '../../runtime/expression.dart';
import '../../services/plugin_event_hub.dart';
import '../registry/plugin_contract.dart';
import 'contracts.dart';

DartPluginManifest createSpellcastPlugin({DartPluginEventHub? eventHub}) {
  final hub = eventHub ?? DartPluginEventHub();
  return DartPluginManifest(
    id: PluginId('spellcast'),
    name: 'Spellcast',
    actions: [
      ActionSpec<SpellcastCastConfig, RuntimeMap>(
        pluginId: PluginId('spellcast'),
        actionId: ActionId('castSpell'),
        displayName: 'Cast Spell',
        configSchema: const DartDataInputSchema(
          label: 'Spell resource',
          kind: DartDataInputKind.resource,
          key: 'spell',
          resourceType: 'SpellHook',
          required: true,
        ),
        configCodec: spellcastCastConfigCodec,
        invoke: (config, context) => _castSpell(hub, config),
      ),
    ],
    triggers: [
      TriggerSpec<SpellcastHookConfig, SpellcastHookEvent>(
        pluginId: PluginId('spellcast'),
        triggerId: TriggerId('spellHook'),
        displayName: 'Spellcast Spell',
        configSchema: const DartDataInputSchema(
          label: 'Spell resource',
          kind: DartDataInputKind.resource,
          key: 'spell',
          resourceType: 'SpellHook',
          required: true,
        ),
        listen: () => hub
            .stream('spellcast')
            .map<SpellcastHookEvent>(
              (event) => SpellcastHookEvent.fromRuntime(event),
            ),
        eventDecoder: SpellcastHookEvent.fromRuntime,
        eventEncoder: (event) => event.toRuntime(),
        matches: _matchesSpellHook,
        configCodec: spellcastHookConfigCodec,
      ),
    ],
  );
}

Future<RuntimeMap> _castSpell(
  DartPluginEventHub eventHub,
  SpellcastCastConfig config,
) async {
  final spellId = config.spell?.id ?? '';
  if (spellId.isEmpty) return {'cast': false, 'spellId': spellId};
  eventHub.emit('spellcastCommand', {'spellId': spellId});
  return {'cast': true, 'spellId': spellId};
}

bool _matchesSpellHook(SpellcastHookConfig config, SpellcastHookEvent event) =>
    config.spell.isValid && config.spell.id == event.spell.id;
