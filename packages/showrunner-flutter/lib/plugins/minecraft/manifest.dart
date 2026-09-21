import '../../schema/data_input.dart';
import '../../runtime/expression.dart';
import '../registry/builtin_resource_specs.dart';
import '../registry/plugin_contract.dart';
import 'contracts.dart';
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
      resourceType: ResourceTypeId('RCONConnection'),
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
    id: PluginId('minecraft'),
    name: 'Minecraft',
    resources: builtInResourceSpecsFor(const PluginId('minecraft')),
    actions: [
      ActionSpec<MinecraftCommandConfig, RuntimeMap>(
        pluginId: PluginId('minecraft'),
        actionId: ActionId('mineCmd'),
        displayName: 'Minecraft RCON Command',
        configSchema: _commandSchema,
        configCodec: minecraftCommandConfigCodec,
        invoke: (config, context) => _sendRconCommand(
          effectiveTransport,
          config,
          connectionResolver: connectionResolver,
        ),
      ),
    ],
  );
}

Future<RuntimeMap> _sendRconCommand(
  MinecraftTransport transport,
  MinecraftCommandConfig config, {
  RconConnectionResolver? connectionResolver,
}) async {
  final command = config.command;
  if (command.trim().isEmpty) {
    return {
      'executed': false,
      'command': command,
      'reason': 'Command is empty',
    };
  }

  final reference = config.server;
  final resolved = reference?.id != null && connectionResolver != null
      ? await connectionResolver(reference!.id!)
      : null;
  final settings = resolved == null
      ? reference?.settings
      : MinecraftConnectionSettings.fromRuntime(
          resolved['config'] is Map ? resolved['config'] : resolved,
        );
  final host = settings?.host ?? '';
  final port = settings?.port ?? 25575;
  final password = settings?.password ?? '';
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
