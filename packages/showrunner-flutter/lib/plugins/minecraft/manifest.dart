import '../../schema/data_input.dart';
import '../../runtime/expression.dart';
import '../registry/plugin_contract.dart';
import 'rcon.dart';

typedef RconConnectionResolver = Future<RuntimeMap?> Function(String id);

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

DartPluginManifest createMinecraftPlugin({
  MinecraftTransport? transport,
  RconConnectionResolver? connectionResolver,
}) {
  final persistentTransport = transport == null
      ? PersistentMinecraftRconTransport()
      : null;
  final effectiveTransport =
      transport ?? MinecraftTransport(persistentTransport!.request);
  return DartPluginManifest(
    id: 'minecraft',
    name: 'Minecraft',
    actions: [
      DartActionDefinition(
        pluginId: 'minecraft',
        actionId: 'mineCmd',
        displayName: 'Minecraft RCON Command',
        configSchema: _commandSchema,
        invoke: (config, context) => _sendRconCommand(
          effectiveTransport,
          config,
          connectionResolver: connectionResolver,
        ),
      ),
    ],
  );
}

Future<Object?> _sendRconCommand(
  MinecraftTransport transport,
  RuntimeMap config, {
  RconConnectionResolver? connectionResolver,
}) async {
  final command = config['command']?.toString() ?? '';
  if (command.trim().isEmpty) {
    return {
      'executed': false,
      'command': command,
      'reason': 'Command is empty',
    };
  }

  final serverReference = config['server'];
  final server = serverReference is String && connectionResolver != null
      ? await connectionResolver(serverReference)
      : serverReference;
  final values = server is Map && server['config'] is Map
      ? server['config'] as Map
      : server is Map
      ? server
      : config;
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
