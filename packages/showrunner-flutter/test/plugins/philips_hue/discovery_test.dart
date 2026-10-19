import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/philips_hue/discovery.dart';

void main() {
  test(
    'discovers a bridge and retries pairing until the button is pressed',
    () async {
      final calls = <({String method, Uri uri, Map<String, dynamic>? body})>[];
      var pairAttempts = 0;
      final service = PhilipsHueDiscoveryService(
        request: (method, uri, body) async {
          calls.add((method: method, uri: uri, body: body));
          if (uri.host == 'discovery.meethue.com') {
            return [
              {'internalipaddress': '192.168.1.25'},
            ];
          }
          if (uri.path == '/api/0/config') {
            return {'name': 'Bridge', 'bridgeid': 'ABC'};
          }
          pairAttempts++;
          if (pairAttempts == 1) {
            return [
              {
                'error': {'type': 101},
              },
            ];
          }
          return [
            {
              'success': {'username': 'hue-key'},
            },
          ];
        },
        delay: (_) async {},
      );

      final pairing = await service.findAndPair();

      expect(pairing?.host, '192.168.1.25');
      expect(pairing?.applicationKey, 'hue-key');
      expect(pairAttempts, 2);
      expect(calls.map((call) => '${call.method} ${call.uri.path}'), [
        'GET /',
        'GET /api/0/config',
        'POST /api',
        'POST /api',
      ]);
      expect(calls[2].body?['devicetype'], startsWith('ShowRunner#'));
    },
  );

  test(
    'returns no pairing when the discovery response contains no bridge',
    () async {
      final service = PhilipsHueDiscoveryService(
        request: (method, uri, body) async => const [],
      );
      expect(await service.findAndPair(), isNull);
    },
  );
}
