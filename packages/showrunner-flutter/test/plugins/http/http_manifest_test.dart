import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/http/manifest.dart';
import 'package:showrunner_flutter/runtime/expression.dart';

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

  test(
    'HTTP request appends query values without dropping duplicates',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final received = Completer<Uri>();
      server.listen((request) async {
        if (!received.isCompleted) received.complete(request.uri);
        request.response
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'ok': true}));
        await request.response.close();
      });

      final action = createHttpPlugin().actions.single;
      final result = await action.invoke({
        'url': 'http://127.0.0.1:${server.port}/request?tag=original',
        'query': 'tag=extra&tag=second&empty',
        'method': 'GET',
      }, EvaluationContext());

      expect(result, {'ok': true});
      final uri = await received.future;
      expect(uri.path, '/request');
      expect(uri.queryParametersAll['tag'], ['original', 'extra', 'second']);
      expect(uri.queryParametersAll['empty'], ['']);
    },
  );
}
