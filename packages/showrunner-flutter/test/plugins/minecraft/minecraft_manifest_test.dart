import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/minecraft/manifest.dart';
import 'package:showrunner_flutter/plugins/minecraft/rcon.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';

void main() {
  test(
    'executes a Minecraft command through authenticated RCON transport',
    () async {
      String? host;
      int? port;
      String? password;
      String? command;
      final registry = DartPluginRegistry()
        ..register(
          createMinecraftPlugin(
            transport: MinecraftTransport((
              requestHost,
              requestPort,
              requestPassword,
              requestCommand,
            ) async {
              host = requestHost;
              port = requestPort;
              password = requestPassword;
              command = requestCommand;
              return 'Executed successfully';
            }),
          ),
        );

      final result = await registry.invokeAction('minecraft', 'mineCmd', {
        'server': {
          'host': 'minecraft.test',
          'port': '25575',
          'password': 'secret',
        },
        'command': 'say Hello from Flutter',
      });

      expect(host, 'minecraft.test');
      expect(port, 25575);
      expect(password, 'secret');
      expect(command, 'say Hello from Flutter');
      expect(result, {
        'executed': true,
        'command': 'say Hello from Flutter',
        'response': 'Executed successfully',
      });
    },
  );

  test(
    'does not call RCON for an empty command or incomplete connection',
    () async {
      var requests = 0;
      final registry = DartPluginRegistry()
        ..register(
          createMinecraftPlugin(
            transport: MinecraftTransport((
              host,
              port,
              password,
              command,
            ) async {
              requests++;
              return 'unexpected';
            }),
          ),
        );

      final emptyCommand = await registry.invokeAction('minecraft', 'mineCmd', {
        'command': '  ',
      });
      final incompleteConnection = await registry.invokeAction(
        'minecraft',
        'mineCmd',
        {
          'server': {'host': '127.0.0.1'},
          'command': 'list',
        },
      );

      expect(emptyCommand, {
        'executed': false,
        'command': '  ',
        'reason': 'Command is empty',
      });
      expect(incompleteConnection, {
        'executed': false,
        'command': 'list',
        'reason': 'RCON connection is unconfigured',
      });
      expect(requests, 0);
    },
  );
}
