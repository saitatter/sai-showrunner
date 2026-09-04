import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/plugins/twinkly/manifest.dart';

void main() {
  test('maps Twinkly info, color, mode, movie, and power operations', () async {
    final requests = <({String method, String path, dynamic body})>[];
    final registry = DartPluginRegistry()
      ..register(
        createTwinklyPlugin(
          TwinklyTransport((ip, method, path, query, body) async {
            requests.add((method: method, path: path, body: body));
            return <String, dynamic>{};
          }),
        ),
      );

    final config = {'ip': '192.168.1.50'};
    await registry.invokeAction('twinkly', 'getInfo', config);
    await registry.invokeAction('twinkly', 'getMode', config);
    await registry.invokeAction('twinkly', 'getColor', config);
    await registry.invokeAction('twinkly', 'setColor', {
      ...config,
      'color': 'hsb(120, 50, 80)',
    });
    await registry.invokeAction('twinkly', 'turnOff', config);
    await registry.invokeAction('twinkly', 'setMovie', {
      ...config,
      'movieId': 'movie-1',
    });

    expect(requests.map((request) => '${request.method} ${request.path}'), [
      'GET /gestalt',
      'GET /led/mode',
      'GET /led/color',
      'POST /led/color',
      'POST /led/mode',
      'POST /led/mode',
      'POST /movies/current',
      'POST /led/mode',
    ]);
    expect(requests[3].body, {'hue': 120, 'saturation': 128, 'value': 204});
    expect(requests[6].body, {'id': 'movie-1'});
  });

  test('rejects unsupported Kelvin colors for Twinkly RGB mode', () async {
    final registry = DartPluginRegistry()
      ..register(
        createTwinklyPlugin(
          TwinklyTransport((ip, method, path, query, body) async => {}),
        ),
      );

    await expectLater(
      registry.invokeAction('twinkly', 'setColor', {
        'ip': '192.168.1.50',
        'color': 'kb(3000, 50)',
      }),
      throwsArgumentError,
    );
  });
}
