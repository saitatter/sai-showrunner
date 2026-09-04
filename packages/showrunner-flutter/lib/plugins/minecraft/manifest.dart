import '../../components/data_inputs/data_input.dart';
import '../../runtime/expression.dart';
import '../registry/plugin_registry.dart';
import 'rcon.dart';

const _commandSchema = DartDataInputSchema(
  label: 'Minecraft command',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'Server',
      key: 'server',
      kind: DartDataInputKind.resource,
      resourceType: 'RCONConnection',
      required: true,
    ),
    DartDataInputSchema(
      label: 'Command',
      key: 'command',
      kind: DartDataInputKind.multilineText,
      required: true,
    ),
  ],
);

DartPluginManifest createMinecraftPlugin({MinecraftTransport? transport}) =>
    DartPluginManifest(
      id: 'minecraft',
      name: 'Minecraft',
      actions: [
        DartActionDefinition(
          pluginId: 'minecraft',
          actionId: 'mineCmd',
          displayName: 'Minecraft RCON Command',
          configSchema: _commandSchema,
          invoke: (config, context) => _sendRconCommand(
            transport ??
                MinecraftTransport(SocketMinecraftRconTransport().request),
            config,
          ),
        ),
      ],
    );

Future<Object?> _sendRconCommand(
  MinecraftTransport transport,
  RuntimeMap config,
) async {
  final command = config['command']?.toString() ?? '';
  if (command.trim().isEmpty) {
    return {
      'executed': false,
      'command': command,
      'reason': 'Command is empty',
    };
  }

  final server = config['server'];
  final values = server is Map ? server : config;
  final host = values['host']?.toString().trim() ?? '';
  final port = _asInt(values['port']) ?? 25575;
  final password = values['password']?.toString() ?? '';
  if (host.isEmpty || password.isEmpty || port < 1 || port > 65535) {
    return {
      'executed': false,
      'command': command,
      'reason': 'RCON connection is unconfigured',
    };
  }

  final response = await transport.request(host, port, password, command);
  return {'executed': true, 'command': command, 'response': response};
}

int? _asInt(Object? value) => switch (value) {
  int value => value,
  num value => value.toInt(),
  String value => int.tryParse(value),
  _ => null,
};
