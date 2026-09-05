import '../../schema/data_input.dart';
import '../../runtime/expression.dart';
import '../../services/plugin_event_hub.dart';
import '../registry/plugin_contract.dart';
import '../registry/plugin_ui.dart';
import 'ui/spellcast_workspace.dart';

DartPluginManifest createSpellcastPlugin({DartPluginEventHub? eventHub}) {
  final hub = eventHub ?? DartPluginEventHub();
  return DartPluginManifest(
    id: 'spellcast',
    name: 'Spellcast',
    ui: DartFlutterPluginUiContribution(
      builder: (context, dataService, providerEvents, registryFuture) =>
          SpellcastWorkspace(
            dataService: dataService,
            eventHub: hub,
            providerEvents: providerEvents,
          ),
    ),
    actions: [
      DartActionDefinition(
        pluginId: 'spellcast',
        actionId: 'castSpell',
        displayName: 'Cast Spell',
        invoke: (config, context) => _castSpell(hub, config),
      ),
    ],
    triggers: [
      DartTriggerDefinition(
        pluginId: 'spellcast',
        triggerId: 'spellHook',
        displayName: 'Spellcast Spell',
        configSchema: const DartDataInputSchema(
          label: 'Spell resource',
          kind: DartDataInputKind.resource,
          key: 'spell',
          resourceType: 'SpellHook',
          required: true,
        ),
        listen: () => hub.stream('spellcast'),
        matches: _matchesSpellHook,
      ),
    ],
  );
}

Future<Object?> _castSpell(
  DartPluginEventHub eventHub,
  RuntimeMap config,
) async {
  final spellId = _resourceId(config['spellId'] ?? config['spell']);
  if (spellId.isEmpty) return {'cast': false, 'spellId': spellId};
  eventHub.emit('spellcastCommand', {'spellId': spellId});
  return {'cast': true, 'spellId': spellId};
}

bool _matchesSpellHook(RuntimeMap config, RuntimeMap payload) {
  final configuredSpell = _resourceId(config['spell']);
  final eventSpell = _resourceId(payload['spell'] ?? payload['spellId']);
  return configuredSpell.isNotEmpty && configuredSpell == eventSpell;
}

String _resourceId(Object? value) {
  if (value is Map) {
    return value['id']?.toString() ?? value['resourceId']?.toString() ?? '';
  }
  return value?.toString().trim() ?? '';
}
