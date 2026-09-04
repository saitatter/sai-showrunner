import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/plugins/wyze/manifest.dart';

void main() {
  test('maps Wyze light and plug actions through the transport', () async {
    final calls = <String>[];
    final registry = DartPluginRegistry()
      ..register(
        createWyzePlugin(
          CallbackWyzeTransport(
            loginCallback: (email, password) async =>
                (accessToken: 'access', refreshToken: 'refresh'),
            getDevicesCallback: () async => const [],
            getDeviceStateCallback: (mac, model) async => {'power': true},
            setLightStateCallback: (mac, model, properties) async {
              calls.add('light:$mac:$model:$properties');
              return {'err_code': 0};
            },
            setPlugStateCallback: (mac, model, on) async {
              calls.add('plug:$mac:$model:$on');
              return {'err_code': 0};
            },
          ),
        ),
      );

    await registry.invokeAction('wyze', 'setLightState', {
      'device': 'AA:BB',
      'model': 'MeshLight',
      'state': 'toggle',
      'color': 'hsb(120, 100, 50)',
    });
    await registry.invokeAction('wyze', 'setPlugState', {
      'device': 'CC:DD',
      'model': 'Plug',
      'state': 'toggle',
    });

    expect(calls, [
      'light:AA:BB:MeshLight:{power: false, brightness: 50, color: 008000}',
      'plug:CC:DD:Plug:false',
    ]);
  });

  test('logs in and calls the real Wyze HTTP contract', () async {
    final server = await HttpServer.bind('127.0.0.1', 0);
    final requests = <String>[];
    final subscription = server.listen((request) async {
      requests.add(request.uri.path);
      final body = await utf8.decoder.bind(request).join();
      if (request.uri.path == '/api/user/login') {
        expect(request.headers.value('keyid'), 'key-id');
        expect((jsonDecode(body) as Map)['password'], isNot('password'));
        request.response.write(
          jsonEncode({'access_token': 'access', 'refresh_token': 'refresh'}),
        );
      } else if (request.uri.path == '/app/v2/home_page/get_object_list') {
        request.response.write(
          jsonEncode({
            'data': {
              'device_list': [
                {'mac': 'AA:BB', 'product_model': 'MeshLight'},
              ],
            },
          }),
        );
      } else {
        request.response.write(jsonEncode({'data': {}, 'msg': 'OK'}));
      }
      await request.response.close();
    });
    final transport = WyzeHttpTransport(
      keyId: 'key-id',
      apiKey: 'api-key',
      apiBase: 'http://127.0.0.1:${server.port}',
      authBase: 'http://127.0.0.1:${server.port}',
    );
    try {
      expect(await transport.login('user@example.com', 'password'), (
        accessToken: 'access',
        refreshToken: 'refresh',
      ));
      expect(await transport.getDevices(), [
        {'mac': 'AA:BB', 'product_model': 'MeshLight'},
      ]);
      expect(requests, [
        '/api/user/login',
        '/app/v2/home_page/get_object_list',
      ]);
    } finally {
      await subscription.cancel();
      await server.close();
    }
  });
}
