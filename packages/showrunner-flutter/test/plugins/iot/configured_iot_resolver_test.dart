import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/persistence/resource_repository.dart';
import 'package:showrunner_flutter/plugins/iot/manifest.dart';
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
}
