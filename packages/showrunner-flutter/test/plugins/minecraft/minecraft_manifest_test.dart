import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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

  test('reuses one authenticated socket for sequential commands', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    var connectionCount = 0;
    final serverTask = () async {
      final socket = await server.first;
      connectionCount++;
      final iterator = StreamIterator<int>(socket.expand((chunk) => chunk));
      try {
        final auth = await _readTestPacket(iterator);
        await _sendTestPacket(socket, auth.id, 2, '');
        final first = await _readTestPacket(iterator);
        await _sendTestPacket(socket, first.id, 0, 'first response');
        final second = await _readTestPacket(iterator);
        await _sendTestPacket(socket, second.id, 0, 'second response');
      } finally {
        await iterator.cancel();
        await socket.close();
      }
    }();
    final transport = PersistentMinecraftRconTransport();
    try {
      expect(
        await transport.request('127.0.0.1', server.port, 'secret', 'list'),
        'first response',
      );
      expect(
        await transport.request(
          '127.0.0.1',
          server.port,
          'secret',
          'say hello',
        ),
        'second response',
      );
      await serverTask;
      expect(connectionCount, 1);
    } finally {
      await transport.close();
      await server.close();
    }
  });

  test('resolves a persisted RCON connection ID', () async {
    String? host;
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
            return 'ok';
          }),
          connectionResolver: (id) async => id == 'server-1'
              ? {'host': 'minecraft.test', 'port': 25575, 'password': 'secret'}
              : null,
        ),
      );

    final result = await registry.invokeAction('minecraft', 'mineCmd', {
      'server': 'server-1',
      'command': 'list',
    });

    expect(result, {'executed': true, 'command': 'list', 'response': 'ok'});
    expect(host, 'minecraft.test');
  });
}

final class _TestPacket {
  const _TestPacket({required this.id, required this.type, required this.body});

  final int id;
  final int type;
  final String body;
}

Future<_TestPacket> _readTestPacket(StreamIterator<int> iterator) async {
  final lengthBytes = await _readTestBytes(iterator, 4);
  final length = ByteData.sublistView(
    Uint8List.fromList(lengthBytes),
  ).getInt32(0, Endian.little);
  final body = await _readTestBytes(iterator, length);
  final data = ByteData.sublistView(Uint8List.fromList(body));
  return _TestPacket(
    id: data.getInt32(0, Endian.little),
    type: data.getInt32(4, Endian.little),
    body: utf8.decode(body.sublist(8, body.length - 2)),
  );
}

Future<List<int>> _readTestBytes(
  StreamIterator<int> iterator,
  int length,
) async {
  final bytes = <int>[];
  while (bytes.length < length) {
    if (!await iterator.moveNext()) {
      throw const SocketException('Test RCON socket closed.');
    }
    bytes.add(iterator.current);
  }
  return bytes;
}

Future<void> _sendTestPacket(
  Socket socket,
  int id,
  int type,
  String body,
) async {
  final payload = utf8.encode(body);
  final packet = ByteData(4 + 4 + 4 + payload.length + 2);
  var offset = 0;
  packet.setInt32(offset, packet.lengthInBytes - 4, Endian.little);
  offset += 4;
  packet.setInt32(offset, id, Endian.little);
  offset += 4;
  packet.setInt32(offset, type, Endian.little);
  offset += 4;
  for (final byte in payload) {
    packet.setUint8(offset++, byte);
  }
  packet.setUint8(offset++, 0);
  packet.setUint8(offset, 0);
  socket.add(packet.buffer.asUint8List());
  await socket.flush();
}
