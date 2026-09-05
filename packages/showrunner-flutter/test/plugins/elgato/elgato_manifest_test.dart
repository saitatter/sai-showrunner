import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/elgato/manifest.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';

void main() {
  test('reads and updates an Elgato light through its transport', () async {
    final requests = <({String method, String path, dynamic body})>[];
    final registry = DartPluginRegistry()
      ..register(
        createElgatoPlugin(
          ElgatoTransport((method, path, body) async {
            requests.add((method: method, path: path, body: body));
            if (method == 'GET') {
              return {
                'lights': [
                  {'on': true, 'brightness': 80, 'temperature': 200},
                ],
              };
            }
            return {'ok': true};
          }),
          numberOfLights: 1,
        ),
      );

    final result = await registry.invokeAction('elgato', 'setLightState', {
      'state': 'toggle',
      'color': 'kb(4000, 55)',
      'numberOfLights': 2,
    });

    expect(requests.first, (method: 'GET', path: '/lights', body: null));
    expect(requests.last.method, 'PUT');
    expect(requests.last.path, '/lights');
    expect(requests.last.body, {
      'numberOfLights': 2,
      'lights': [
        {'on': false, 'brightness': 55, 'temperature': 290},
        {'on': false, 'brightness': 55, 'temperature': 290},
      ],
    });
    expect(result, {
      'updated': true,
      'state': {'on': false, 'brightness': 55, 'temperature': 290},
      'ok': true,
    });
  });

  test('blocks RGB commands for a Key Light profile', () async {
    var puts = 0;
    final registry = DartPluginRegistry()
      ..register(
        createElgatoPlugin(
          ElgatoTransport((method, path, body) async {
            if (method == 'PUT') puts++;
            return {
              'lights': [
                {'on': true, 'brightness': 80, 'temperature': 200},
              ],
            };
          }),
        ),
      );

    final result = await registry.invokeAction('elgato', 'setLightState', {
      'color': 'hsb(120, 100, 50)',
    });

    expect(result, {
      'updated': false,
      'reason': 'RGB is not enabled for this Elgato accessory.',
    });
    expect(puts, 0);
  });

  test('routes resource actions through the configured device host', () async {
    var resolved = false;
    final registry = DartPluginRegistry()
      ..register(
        createElgatoPlugin(
          ElgatoTransport((method, path, body) async {
            throw StateError('base transport');
          }),
          transportResolver: (config) {
            expect(config['host'], 'elgato.local');
            expect(config['port'], 9124);
            resolved = true;
            return ElgatoTransport((method, path, body) async {
              if (method == 'GET') {
                return {
                  'lights': [
                    {'on': true, 'brightness': 80, 'temperature': 200},
                  ],
                };
              }
              return {'ok': true};
            });
          },
        ),
      );

    await registry.invokeAction('elgato', 'setLightState', {
      'host': 'elgato.local',
      'port': 9124,
      'state': 'on',
      'color': 'kb(4000, 55)',
    });

    expect(resolved, isTrue);
  });
}
