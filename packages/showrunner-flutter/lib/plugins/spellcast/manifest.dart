import '../../runtime/expression.dart';
import '../registry/plugin_registry.dart';

DartPluginManifest createSpellcastPlugin() => const DartPluginManifest(
  id: 'spellcast',
  name: 'Spellcast',
  actions: [
    DartActionDefinition(
      pluginId: 'spellcast',
      actionId: 'castSpell',
      displayName: 'Cast Spell',
      invoke: _castSpell,
    ),
  ],
);

Future<Object?> _castSpell(RuntimeMap config, EvaluationContext context) async {
  final spellId = config['spellId']?.toString() ?? '';
  return {'cast': spellId.isNotEmpty, 'spellId': spellId};
}
