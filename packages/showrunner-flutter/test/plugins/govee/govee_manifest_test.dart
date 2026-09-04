import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/govee/manifest.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';

void main() {
  test(
    'maps Govee cloud discovery and controls through the API contract',
    () async {
      final requests = <({String method, String path, dynamic body})>[];
      final registry = DartPluginRegistry()
        ..register(
          createGoveePlugin(
            GoveeTransport((method, path, query, body) async {
              requests.add((method: method, path: path, body: body));
              if (path == '/v1/devices/state') {
                return {
                  'data': {
                    'properties': [
                      {'powerState': 'on'},
                    ],
                  },
                };
              }
              return {'code': 200};
            }),
          ),
        );

      await registry.invokeAction('govee', 'listDevices', {});
      await registry.invokeAction('govee', 'getDeviceState', {
        'device': 'AA:BB',
        'model': 'H6001',
      });
      await registry.invokeAction('govee', 'setPower', {
        'device': 'AA:BB',
        'model': 'H6001',
        'state': 'toggle',
      });
      await registry.invokeAction('govee', 'setColor', {
        'device': 'AA:BB',
        'model': 'H6001',
        'color': 'hsb(0, 100, 100)',
      });
      await registry.invokeAction('govee', 'setBrightness', {
        'device': 'AA:BB',
        'model': 'H6001',
        'brightness': 120,
      });

      expect(requests.map((request) => '${request.method} ${request.path}'), [
        'GET /v1/devices',
        'GET /v1/devices/state',
        'GET /v1/devices/state',
        'PUT /v1/devices/control',
        'PUT /v1/devices/control',
        'PUT /v1/devices/control',
        'PUT /v1/devices/control',
      ]);
      expect(requests[3].body, {
        'device': 'AA:BB',
        'model': 'H6001',
        'cmd': {'name': 'turn', 'value': 'off'},
      });
      expect(requests[4].body['cmd'], {
        'name': 'color',
        'value': {'r': 255, 'g': 0, 'b': 0},
      });
      expect(requests[5].body['cmd'], {'name': 'brightness', 'value': 100});
      expect(requests[6].body['cmd'], {'name': 'brightness', 'value': 100});
    },
  );

  test(
    'supports Kelvin colors by sending temperature and brightness commands',
    () async {
      final commands = <Map<String, dynamic>>[];
      final registry = DartPluginRegistry()
        ..register(
          createGoveePlugin(
            GoveeTransport((method, path, query, body) async {
              if (body is Map && body['cmd'] is Map) {
                commands.add(Map<String, dynamic>.from(body['cmd'] as Map));
              }
              return <String, dynamic>{};
            }),
          ),
        );

      await registry.invokeAction('govee', 'setColor', {
        'device': 'AA:BB',
        'model': 'H6001',
        'color': 'kb(3000, 40)',
      });

      expect(commands, [
        {'name': 'colorTem', 'value': 3000},
        {'name': 'brightness', 'value': 40},
      ]);
    },
  );
}
