import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/services/http_provider_transports.dart';

void main() {
  test('JSON provider transport sends auth and decodes the response', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requestReceived = Completer<void>();
    server.listen((request) async {
      expect(
        request.headers.value(HttpHeaders.authorizationHeader),
        'Bearer token',
      );
      expect(request.headers.value('x-provider'), 'test');
      expect(await utf8.decoder.bind(request).join(), '{"enabled":true}');
      requestReceived.complete();
      request.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'ok': true}));
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));

    final transport = JsonHttpTransport(
      baseUrl: 'http://127.0.0.1:${server.port}',
      accessTokenProvider: () async => 'token',
      headers: {'x-provider': 'test'},
    );

    final result = await transport.request(
      'POST',
      '/provider',
      const <String, dynamic>{},
      const <String, dynamic>{'enabled': true},
    );

    await requestReceived.future;
    expect(result, {'ok': true});
  });

  test('JSON provider transport reports non-success responses', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response
        ..statusCode = HttpStatus.badRequest
        ..write('bad request');
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));

    final transport = JsonHttpTransport(
      baseUrl: 'http://127.0.0.1:${server.port}',
    );

    await expectLater(
      transport.requestValue('GET', '/provider', const {}, null),
      throwsA(
        isA<HttpException>().having(
          (error) => error.message,
          'message',
          contains('400'),
        ),
      ),
    );
  });
}
