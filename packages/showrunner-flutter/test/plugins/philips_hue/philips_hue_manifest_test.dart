import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/philips_hue/manifest.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';

void main() {
  test('exposes Hue discovery, state, scene, and light controls', () async {
    final requests = <({String method, String path, dynamic body})>[];
    final registry = DartPluginRegistry()
      ..register(
        createPhilipsHuePlugin(
          HueTransport((method, path, query, body) async {
            requests.add((method: method, path: path, body: body));
            if (method == 'GET' && path.contains('/resource/light/')) {
              return {
                'data': [
                  {
                    'on': {'on': true},
                  },
                ],
              };
            }
            return <String, dynamic>{};
          }),
        ),
      );

    await registry.invokeAction('philips-hue', 'listLights', {});
    await registry.invokeAction('philips-hue', 'listGroups', {});
    await registry.invokeAction('philips-hue', 'listScenes', {});
    await registry.invokeAction('philips-hue', 'setLightState', {
      'lightId': 'light-1',
      'resourceType': 'light',
      'state': 'toggle',
      'color': 'hsb(0, 100, 100)',
      'transition': 1,
    });
    await registry.invokeAction('philips-hue', 'recallScene', {
      'sceneId': 'scene-1',
    });

    expect(requests.map((request) => '${request.method} ${request.path}'), [
      'GET /resource/light',
      'GET /resource/grouped_light',
      'GET /resource/scene',
      'GET /resource/light/light-1',
      'PUT /resource/light/light-1',
      'PUT /resource/scene/scene-1',
    ]);
    expect(requests[4].body, {
      'on': {'on': false},
      'dynamics': {'duration': 1000},
      'dimming': {'brightness': 100},
      'color': {'xy': isA<Map<String, double>>()},
    });
    expect(requests[5].body, {
      'recall': {'action': 'active'},
    });
  });

  test('maps a Kelvin color to Hue mirek and clamps transition', () async {
    dynamic body;
    final registry = DartPluginRegistry()
      ..register(
        createPhilipsHuePlugin(
          HueTransport((method, path, query, requestBody) async {
            body = requestBody;
            return <String, dynamic>{};
          }),
        ),
      );

    await registry.invokeAction('philips-hue', 'setLightState', {
      'lightId': 'light-1',
      'state': 'on',
      'color': 'kb(4000, 75)',
      'transition': -1,
    });

    expect(body, {
      'on': {'on': true},
      'dynamics': {'duration': 0},
      'dimming': {'brightness': 75},
      'color_temperature': {'mirek': 250},
    });
  });

  test('routes light actions through a resource-specific bridge', () async {
    var resolved = false;
    final registry = DartPluginRegistry()
      ..register(
        createPhilipsHuePlugin(
          HueTransport((method, path, query, body) async {
            throw StateError('base transport');
          }),
          transportResolver: (config) {
            expect(config['host'], 'hue.local');
            expect(config['hubKey'], 'resource-key');
            resolved = true;
            return HueTransport((method, path, query, body) async {
              return <String, dynamic>{};
            });
          },
        ),
      );

    await registry.invokeAction('philips-hue', 'setLightState', {
      'host': 'hue.local',
      'hubKey': 'resource-key',
      'lightId': 'light-1',
      'state': 'on',
    });

    expect(resolved, isTrue);
  });
}
