import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/plugins/voicemod/manifest.dart';
import 'package:showrunner_flutter/runtime/expression.dart';

void main() {
  test('selects a voice through the VoiceMod transport', () async {
    String? selected;
    final registry = DartPluginRegistry()
      ..register(
        createVoiceModPlugin(
          CallbackVoiceModTransport(
            getVoicesCallback: () async => [
              {'id': 'nofx', 'friendlyName': 'Noize FX', 'isEnabled': true},
            ],
            selectVoiceCallback: (voiceId) async {
              selected = voiceId;
              return {'voiceID': voiceId};
            },
          ),
        ),
      );

    final voices = await registry.invokeAction('voicemod', 'getVoices', {});
    final result = await registry.invokeAction('voicemod', 'selectVoice', {
      'voice': 'nofx',
    });

    expect(voices, [
      {'id': 'nofx', 'friendlyName': 'Noize FX', 'isEnabled': true},
    ]);
    expect(selected, 'nofx');
    expect(result, {'selected': true, 'voice': 'nofx', 'voiceID': 'nofx'});
  });

  test('speaks the VoiceMod WebSocket RPC protocol', () async {
    final server = await HttpServer.bind('127.0.0.1', 0);
    StreamSubscription<HttpRequest>? serverSubscription;
    final received = <RuntimeMap>[];
    serverSubscription = server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      socket.listen((data) {
        final message = Map<String, dynamic>.from(jsonDecode(data.toString()));
        received.add(message);
        final action = message['action'];
        if (action == 'registerClient') {
          socket.add(
            jsonEncode({
              'id': message['id'],
              'payload': {'registered': true},
            }),
          );
        } else if (action == 'getVoices') {
          socket.add(
            jsonEncode({
              'id': message['id'],
              'payload': {
                'voices': [
                  {'id': 'nofx', 'friendlyName': 'Noize FX', 'isEnabled': true},
                ],
              },
            }),
          );
        }
      });
    });

    final transport = VoiceModWebSocketTransport(
      host: '127.0.0.1',
      port: server.port,
    );
    try {
      expect(await transport.getVoices(), [
        {'id': 'nofx', 'friendlyName': 'Noize FX', 'isEnabled': true},
      ]);
      expect(await transport.selectVoice('nofx'), {
        'selected': true,
        'voiceID': 'nofx',
      });
      for (var attempt = 0; attempt < 20 && received.length < 3; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      expect(received.map((message) => message['action']), [
        'registerClient',
        'getVoices',
        'selectVoice',
      ]);
      expect(received.last['payload'], {'voiceID': 'nofx'});
    } finally {
      await transport.close();
      await serverSubscription.cancel();
      await server.close(force: true);
    }
  });
}
