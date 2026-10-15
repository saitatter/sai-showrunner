import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/services/http_provider_transports.dart';
import 'package:showrunner_flutter/services/http_policy.dart';

void main() {
  test(
    'rate limits retry reads once but never repeat provider mutations',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      var gets = 0;
      var posts = 0;
      server.listen((request) async {
        if (request.method == 'GET') {
          gets++;
          request.response.statusCode = gets == 1 ? 429 : 200;
        } else {
          posts++;
          request.response.statusCode = 429;
        }
        request.response.headers.set('retry-after', '0');
        request.response.write('{}');
        await request.response.close();
      });
      final transport = JsonHttpTransport(
        baseUrl: 'http://127.0.0.1:${server.port}',
      );
      await transport.request('GET', '/', {}, null);
      expect(gets, 2);
      await expectLater(
        transport.request('POST', '/', {}, {}),
        throwsA(isA<ProviderRateLimitException>()),
      );
      expect(posts, 1);
    },
  );
  test('response limits fail without closing a caller owned client', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final client = HttpClient();
    addTearDown(() async {
      client.close(force: true);
      await server.close(force: true);
    });
    server.listen((request) async {
      request.response.write(
        request.uri.path == '/large' ? '0123456789' : '{}',
      );
      await request.response.close();
    });
    final transport = JsonHttpTransport(
      baseUrl: 'http://127.0.0.1:${server.port}',
      client: client,
      maxResponseBytes: 5,
    );
    await expectLater(
      transport.request('GET', '/large', {}, null),
      throwsA(isA<HttpBodyLimitException>()),
    );
    expect(await transport.request('GET', '/small', {}, null), isEmpty);
  });
  test('provider deadlines also cover stalled response bodies', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.write('{');
      await request.response.flush();
    });
    final transport = JsonHttpTransport(
      baseUrl: 'http://127.0.0.1:${server.port}',
      timeout: const Duration(milliseconds: 50),
    );
    await expectLater(
      transport.request('GET', '/', {}, null),
      throwsA(isA<TimeoutException>()),
    );
  });

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
