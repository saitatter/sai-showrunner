import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/plugins/tplink_kasa/manifest.dart';

void main() {
  test(
    'maps Kasa light and plug actions to the native request shape',
    () async {
      final requests = <Map<String, dynamic>>[];
      final registry = DartPluginRegistry()
        ..register(
          createKasaPlugin(
            KasaTransport((request) async {
              requests.add(request);
              if (request.containsKey('system') &&
                  (request['system'] as Map).containsKey('get_sysinfo')) {
                return {
                  'system': {
                    'get_sysinfo': {'relay_state': 1},
                  },
                };
              }
              return {'err_code': 0};
            }),
          ),
        );

      await registry.invokeAction('tplink-kasa', 'setLightState', {
        'state': 'toggle',
        'color': 'hsb(120, 80, 60)',
        'transition': 1.25,
      });
      await registry.invokeAction('tplink-kasa', 'setPlugState', {
        'state': 'toggle',
      });

      expect(requests, [
        {
          'system': {'get_sysinfo': <String, dynamic>{}},
        },
        {
          'smartlife.iot.smartbulb.lightingservice': {
            'transition_light_state': {
              'on_off': 0,
              'transition_period': 1250,
              'brightness': 60,
              'hue': 120,
              'saturation': 80,
              'color_temp': 0,
            },
          },
        },
        {
          'system': {'get_sysinfo': <String, dynamic>{}},
        },
        {
          'system': {
            'set_relay_state': {'state': 0},
          },
        },
      ]);
    },
  );

  test('round-trips an encrypted Kasa TCP frame', () async {
    final server = await ServerSocket.bind('127.0.0.1', 0);
    StreamSubscription<Socket>? subscription;
    final requestCompleter = Completer<Map<String, dynamic>>();
    subscription = server.listen((socket) {
      final bytes = <int>[];
      socket.listen((chunk) {
        bytes.addAll(chunk);
        if (bytes.length < 4) return;
        final length =
            (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
        if (bytes.length < length + 4) return;
        final decoded = jsonDecode(
          decodeKasaPayload(bytes.sublist(4, length + 4)),
        );
        requestCompleter.complete(Map<String, dynamic>.from(decoded as Map));
        socket.add(
          encodeKasaFrame(
            jsonEncode({
              'system': {
                'get_sysinfo': {'relay_state': 1},
              },
            }),
          ),
        );
      });
    });
    final transport = KasaTcpTransport(host: '127.0.0.1', port: server.port);
    try {
      final response = await transport.request({
        'system': {'get_sysinfo': <String, dynamic>{}},
      });
      expect(await requestCompleter.future, {
        'system': {'get_sysinfo': <String, dynamic>{}},
      });
      expect(response['system'], isA<Map>());
      expect((response['system'] as Map)['get_sysinfo'], {'relay_state': 1});
    } finally {
      await subscription.cancel();
      await server.close();
    }
  });
}
