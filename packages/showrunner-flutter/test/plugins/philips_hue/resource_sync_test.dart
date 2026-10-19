import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/persistence/resource_repository.dart';
import 'package:showrunner_flutter/plugins/philips_hue/manifest.dart';
import 'package:showrunner_flutter/plugins/philips_hue/resource_sync.dart';

void main() {
  test(
    'persists Hue lights, plugs, and room groups using stable resource ids',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'showrunner-hue-sync-',
      );
      addTearDown(() => root.delete(recursive: true));
      final requests = <String>[];
      final synchronizer = PhilipsHueResourceSynchronizer(
        lightDirectory: Directory('${root.path}/iot/lights'),
        plugDirectory: Directory('${root.path}/iot/plugs'),
      );

      await synchronizer.sync(
        HueTransport((method, path, query, body) async {
          requests.add('$method $path');
          switch (path) {
            case '/resource/light':
              return {
                'data': [
                  {
                    'id': 'light-1',
                    'metadata': {'name': 'Key Light'},
                    'color': {},
                    'dimming': {},
                    'color_temperature': {
                      'mirek': 250,
                      'mirek_schema': {
                        'mirek_minimum': 153,
                        'mirek_maximum': 500,
                      },
                    },
                    'on': {'on': true},
                  },
                  {
                    'id': 'plug-1',
                    'metadata': {'name': 'Desk Plug'},
                    'on': {'on': false},
                  },
                ],
              };
            case '/resource/room':
              return {
                'data': [
                  {
                    'id': 'room-1',
                    'metadata': {'name': 'Studio'},
                    'children': [
                      {'rid': 'device-1', 'rtype': 'device'},
                    ],
                    'services': [
                      {'rid': 'group-1', 'rtype': 'grouped_light'},
                    ],
                  },
                ],
              };
            case '/resource/grouped_light/group-1':
              return {
                'data': [
                  {
                    'on': {'on': true},
                    'dimming': {'brightness': 70},
                    'color_temperature': {'mirek': 250},
                  },
                ],
              };
            case '/resource/device/device-1':
              return {
                'data': [
                  {
                    'services': [
                      {'rid': 'light-1', 'rtype': 'light'},
                    ],
                  },
                ],
              };
            default:
              return <String, dynamic>{};
          }
        }),
      );

      final light = await ResourceRepository(
        Directory('${root.path}/iot/lights'),
      ).load('philips-hue.light-1');
      final plug = await ResourceRepository(
        Directory('${root.path}/iot/plugs'),
      ).load('philips-hue.plug-1');
      final group = await ResourceRepository(
        Directory('${root.path}/iot/lights'),
      ).load('philips-hue.group-1');

      expect(light?.config['name'], 'Key Light');
      expect(light?.config['providerId'], 'light-1');
      expect(light?.config['rgb'], {'available': true});
      expect(light?.state['on'], true);
      expect(light?.state['color'], 'kb(4000, 100)');
      expect(plug?.config, {
        'name': 'Desk Plug',
        'provider': 'philips-hue',
        'providerId': 'plug-1',
      });
      expect(plug?.state['on'], false);
      expect(group?.config['name'], 'Studio');
      expect(group?.config['hueType'], 'group');
      expect(group?.config['lightIds'], ['light-1']);
      expect(group?.state, {'on': true, 'color': 'kb(4000, 70)'});
      expect(requests, [
        'GET /resource/light',
        'GET /resource/room',
        'GET /resource/grouped_light/group-1',
        'GET /resource/device/device-1',
      ]);
    },
  );
}
