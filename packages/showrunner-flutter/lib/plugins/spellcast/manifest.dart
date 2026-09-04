import '../../components/data_inputs/data_input.dart';
import '../../runtime/expression.dart';
import '../../services/plugin_event_hub.dart';
import '../registry/plugin_registry.dart';
import 'ui/spellcast_workspace.dart';

DartPluginManifest createSpellcastPlugin({DartPluginEventHub? eventHub}) {
  final hub = eventHub ?? DartPluginEventHub();
  return DartPluginManifest(
    id: 'spellcast',
    name: 'Spellcast',
    workspaceBuilder: (context, dataService, providerEvents, registryFuture) =>
        SpellcastWorkspace(
          dataService: dataService,
          eventHub: hub,
          providerEvents: providerEvents,
        ),
    actions: const [
      DartActionDefinition(
        pluginId: 'spellcast',
        actionId: 'castSpell',
        displayName: 'Cast Spell',
        invoke: _castSpell,
      ),
    ],
    triggers: [
      DartTriggerDefinition(
        pluginId: 'spellcast',
        triggerId: 'spellHook',
        displayName: 'Spellcast Spell',
        configSchema: const DartDataInputSchema(
          label: 'Spell resource ID',
          kind: DartDataInputKind.text,
          key: 'spell',
          required: true,
        ),
        listen: () => hub.stream('spellcast'),
        matches: _matchesSpellHook,
      ),
    ],
  );
}

Future<Object?> _castSpell(RuntimeMap config, EvaluationContext context) async {
  final spellId = config['spellId']?.toString() ?? '';
  return {'cast': spellId.isNotEmpty, 'spellId': spellId};
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
