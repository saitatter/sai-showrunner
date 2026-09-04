import '../../runtime/expression.dart';
import '../registry/plugin_registry.dart';

DartPluginManifest createMinecraftPlugin() => const DartPluginManifest(
  id: 'minecraft',
  name: 'Minecraft',
  actions: [
    DartActionDefinition(
      pluginId: 'minecraft',
      actionId: 'mineCmd',
      displayName: 'Minecraft RCON Command',
      invoke: _sendRconCommand,
    ),
  ],
);

Future<Object?> _sendRconCommand(
  RuntimeMap config,
  EvaluationContext context,
) async {
  final command = config['command']?.toString() ?? '';
  return {'executed': command.isNotEmpty, 'command': command};
}
