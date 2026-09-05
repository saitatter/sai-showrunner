import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/http/manifest.dart';

void main() {
  test(
    'HTTP endpoint trigger exposes route params, query, and JSON body',
    () async {
      final service = DartHttpEndpointService(port: 0);
      await service.start();
      final events = <Map<String, dynamic>>[];
      final subscription = service
          .register(const {'method': 'POST', 'route': '/hooks/:id'})
          .listen(events.add);
      final client = HttpClient();

      try {
        final request = await client.postUrl(
          Uri.parse(
            'http://127.0.0.1:${service.boundPort}/plugins/endpoints/hooks/42'
            '?source=test',
          ),
        );
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode({'message': 'hello'}));
        final response = await request.close();
        await response.drain<void>();

        expect(response.statusCode, HttpStatus.created);
        expect(events, hasLength(1));
        expect(events.single, {
          'method': 'POST',
          'route': '/hooks/:id',
          'params': {'id': '42'},
          'query': {'source': 'test'},
          'body': {'message': 'hello'},
        });
      } finally {
        client.close(force: true);
        await subscription.cancel();
        await service.stop();
      }
    },
  );

  test('unregistered HTTP endpoint returns not found', () async {
    final service = DartHttpEndpointService(port: 0);
    await service.start();
    final client = HttpClient();

    try {
      final request = await client.getUrl(
        Uri.parse(
          'http://127.0.0.1:${service.boundPort}/plugins/endpoints/missing',
        ),
      );
      final response = await request.close();
      await response.drain<void>();
      expect(response.statusCode, HttpStatus.notFound);
    } finally {
      client.close(force: true);
      await service.stop();
    }
  });
}
