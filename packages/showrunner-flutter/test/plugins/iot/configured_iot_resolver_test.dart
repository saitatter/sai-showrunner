import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/persistence/resource_repository.dart';
import 'package:showrunner_flutter/plugins/iot/manifest.dart';
import 'package:showrunner_flutter/plugins/philips_hue/manifest.dart';
import 'package:showrunner_flutter/plugins/registry/configured_iot_resolver.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/plugins/tplink_kasa/manifest.dart';
import 'package:showrunner_flutter/schema/resource.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';

void main() {
  test(
    'executes legacy Kasa resources through the configured resolver',
    () async {
      final root = await Directory.systemTemp.createTemp('showrunner-iot-');
      addTearDown(() => root.delete(recursive: true));

      await ResourceRepository(Directory('${root.path}/iot/plugs')).save(
        const ResourceData(
          id: 'kasa-plug',
          config: {
            'name': 'Desk plug',
            'provider': 'kasa',
            'providerId': 'device-1',
            'host': '192.168.1.50',
          },
        ),
      );

      final requests = <Map<String, dynamic>>[];
      final registry = DartPluginRegistry();
      registry.register(
        createKasaPlugin(
          KasaTransport((request) async {
            requests.add(request);
            return <String, dynamic>{};
          }),
        ),
      );
      registry.register(
        createIotPlugin(
          resolver: createConfiguredIotResolver(
            registry: registry,
            dataService: ShowRunnerDataService(root),
          ),
        ),
      );

      await registry.invokeAction('iot', 'plug', {
        'plug': 'kasa-plug',
        'switch': 'on',
      });

      expect(requests.single['system'], isA<Map>());
      expect((requests.single['system'] as Map)['set_relay_state'], {
        'state': 1,
      });
      registry.dispose();
    },
  );

  test(
    'preserves Philips Hue plug and grouped-light resource semantics',
    () async {
      final root = await Directory.systemTemp.createTemp('showrunner-hue-');
      addTearDown(() => root.delete(recursive: true));

      await ResourceRepository(Directory('${root.path}/iot/plugs')).save(
        const ResourceData(
          id: 'hue-plug',
          config: {
            'name': 'Desk plug',
            'provider': 'philips-hue',
            'providerId': 'plug-1',
            'host': 'hue.local',
            'hubKey': 'resource-key',
          },
        ),
      );
      await ResourceRepository(Directory('${root.path}/iot/lights')).save(
        const ResourceData(
          id: 'hue-group',
          config: {
            'name': 'Studio group',
            'provider': 'philips-hue',
            'providerId': 'group-1',
            'hueType': 'group',
            'host': 'hue.local',
            'hubKey': 'resource-key',
          },
        ),
      );

      final requests = <({String method, String path, dynamic body})>[];
      final registry = DartPluginRegistry();
      registry.register(
        createPhilipsHuePlugin(
          HueTransport((method, path, query, body) async {
            requests.add((method: method, path: path, body: body));
            if (method == 'GET') {
              return {
                'data': [
                  {
                    'on': {'on': false},
                  },
                ],
              };
            }
            return <String, dynamic>{};
          }),
        ),
      );
      registry.register(
        createIotPlugin(
          resolver: createConfiguredIotResolver(
            registry: registry,
            dataService: ShowRunnerDataService(root),
          ),
        ),
      );

      await registry.invokeAction('iot', 'plug', {
        'plug': 'hue-plug',
        'switch': 'toggle',
      });
      await registry.invokeAction('iot', 'light', {
        'light': 'hue-group',
        'on': 'on',
      });

      expect(requests.map((request) => '${request.method} ${request.path}'), [
        'GET /resource/light/plug-1',
        'PUT /resource/light/plug-1',
        'PUT /resource/grouped_light/group-1',
      ]);
      expect(requests[1].body, {
        'on': {'on': true},
      });
      registry.dispose();
    },
  );
}
