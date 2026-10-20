import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/elgato/manifest.dart';
import 'package:showrunner_flutter/plugins/lifx/manifest.dart';
import 'package:showrunner_flutter/plugins/wyze/manifest.dart';
import 'package:showrunner_flutter/plugins/tplink_kasa/manifest.dart';
import 'package:showrunner_flutter/plugins/runtime/provider_operation_policy.dart';
import 'package:showrunner_flutter/services/http_provider_transports.dart';

void main() {
  test(
    'scope cancels a pending retry timer without waiting for its deadline',
    () async {
      final scope = ProviderOperationScope();
      final pending = expectLater(
        scope.delay(const Duration(minutes: 1)),
        throwsStateError,
      );
      await scope.close();
      await pending.timeout(const Duration(seconds: 1));
    },
  );

  test(
    'Wyze shutdown waits for rotated token persistence already started',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        request.response.write(
          '{"access_token":"new-token","refresh_token":"new-refresh"}',
        );
        await request.response.close();
      });
      final saving = Completer<void>();
      final saved = Completer<void>();
      final transport = WyzeHttpTransport(
        keyId: 'test',
        apiKey: 'test',
        authBase: 'http://127.0.0.1:${server.port}',
        onTokens: (tokens) {
          saving.complete();
          return saved.future;
        },
      );
      final login = transport.login('test@example.invalid', 'test');
      await saving.future.timeout(const Duration(seconds: 3));
      var closed = false;
      final closing = transport.close().then((_) => closed = true);
      await Future<void>.delayed(Duration.zero);
      expect(closed, isFalse);
      saved.complete();
      await login;
      await closing;
      expect(closed, isTrue);
    },
  );
  test('backoff saturates without overflow and only reads can retry', () {
    expect(
      ProviderOperationPolicy.backoff(
        const Duration(microseconds: 3),
        2,
        maximum: const Duration(microseconds: 13),
      ),
      const Duration(microseconds: 12),
    );
    expect(
      ProviderOperationPolicy.backoff(
        const Duration(seconds: 2),
        10000,
        maximum: const Duration(minutes: 2),
      ),
      const Duration(minutes: 2),
    );
    expect(
      ProviderOperationPolicy.backoff(
        Duration.zero,
        10000,
        maximum: const Duration(minutes: 2),
      ),
      Duration.zero,
    );
    expect(
      () => ProviderOperationPolicy.backoff(
        Duration.zero,
        -1,
        maximum: Duration.zero,
      ),
      throwsArgumentError,
    );
    for (final method in ['GET', 'head']) {
      expect(ProviderOperationPolicy.canRetryHttpMethod(method), isTrue);
    }
    for (final method in ['POST', 'PUT', 'DELETE', 'PATCH']) {
      expect(ProviderOperationPolicy.canRetryHttpMethod(method), isFalse);
    }
  });

  test(
    'scope aborts once in reverse order despite errors and reentrancy',
    () async {
      final scope = ProviderOperationScope();
      final calls = <int>[];
      final release = scope.track(() => calls.add(0));
      release();
      scope.track(() => calls.add(1));
      scope.track(() {
        calls.add(2);
        throw StateError('abort failure');
      });
      scope.track(() {
        calls.add(3);
        scope.close();
      });
      final closing = scope.close();
      expect(identical(closing, scope.close()), isTrue);
      await expectLater(closing, throwsStateError);
      expect(calls, [3, 2, 1]);
      expect(() => scope.track(() {}), throwsStateError);
    },
  );

  test('device HTTP enforces a body limit and redacts error bodies', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.statusCode = 500;
      request.response.write('private-response-value');
      await request.response.close();
    });
    final limited = ElgatoHttpTransport(
      host: '127.0.0.1',
      port: server.port,
      policy: const ProviderOperationPolicy(maxResponseBytes: 4),
    );
    addTearDown(limited.close);
    await expectLater(
      limited.request('GET', '/lights', null),
      throwsA(isA<Exception>()),
    );
    final normal = ElgatoHttpTransport(host: '127.0.0.1', port: server.port);
    addTearDown(normal.close);
    await expectLater(
      normal.request('GET', '/lights', null),
      throwsA(
        isA<HttpException>().having(
          (e) => e.message,
          'safe message',
          allOf(contains('500'), isNot(contains('private-response-value'))),
        ),
      ),
    );
  });

  test('device HTTP timeout does not retry writes', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var writes = 0;
    server.listen((request) {
      writes++;
    });
    final transport = ElgatoHttpTransport(
      host: '127.0.0.1',
      port: server.port,
      policy: const ProviderOperationPolicy(
        requestTimeout: Duration(milliseconds: 200),
      ),
    );
    addTearDown(transport.close);
    await expectLater(
      transport.request('PUT', '/lights', {'on': 1}),
      throwsA(isA<TimeoutException>()),
    );
    expect(writes, 1);
  });

  test(
    'shared scope interrupts device clients and rejects new requests',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final received = Completer<void>();
      var count = 0;
      server.listen((request) {
        if (++count == 2) received.complete();
      });
      final scope = ProviderOperationScope();
      final first = ElgatoHttpTransport(
        host: '127.0.0.1',
        port: server.port,
        scope: scope,
      );
      final second = ElgatoHttpTransport(
        host: '127.0.0.1',
        port: server.port,
        scope: scope,
      );
      final expected = [first, second]
          .map(
            (transport) => expectLater(
              transport.request('GET', '/lights', null),
              throwsA(isNot(isA<TimeoutException>())),
            ),
          )
          .toList();
      await received.future.timeout(const Duration(seconds: 3));
      await scope.close();
      await Future.wait(expected).timeout(const Duration(seconds: 2));
      await expectLater(
        first.request('GET', '/lights', null),
        throwsStateError,
      );
      expect(count, 2);
    },
  );

  test('cancelling JSON request preserves a borrowed HTTP client', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final received = Completer<void>();
    server.listen((request) async {
      if (request.uri.path == '/wait') {
        received.complete();
        return;
      }
      request.response.write('{}');
      await request.response.close();
    });
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final scope = ProviderOperationScope();
    final transport = JsonHttpTransport(
      baseUrl: 'http://127.0.0.1:${server.port}',
      client: client,
      operationScope: scope,
    );
    final pending = expectLater(
      transport.request('GET', '/wait', {}, null),
      throwsA(isNot(isA<TimeoutException>())),
    );
    await received.future.timeout(const Duration(seconds: 3));
    await scope.close();
    await pending.timeout(const Duration(seconds: 2));
    final response = await (await client.getUrl(
      Uri.parse('http://127.0.0.1:${server.port}/ok'),
    )).close();
    expect(response.statusCode, 200);
    await response.drain<void>();
  });

  test('Kasa shutdown interrupts an outstanding TCP reply', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    final received = Completer<void>();
    server.listen((socket) {
      addTearDown(socket.destroy);
      socket.listen((_) {
        if (!received.isCompleted) received.complete();
      });
    });
    final transport = KasaTcpTransport(host: '127.0.0.1', port: server.port);
    final pending = expectLater(
      transport.request({'system': {}}),
      throwsA(isNot(isA<TimeoutException>())),
    );
    await received.future.timeout(const Duration(seconds: 3));
    await transport.close();
    await pending.timeout(const Duration(seconds: 2));
    await expectLater(transport.request({}), throwsStateError);
  });

  test('LIFX shutdown interrupts an outstanding UDP reply', () async {
    final server = await RawDatagramSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    addTearDown(server.close);
    final received = Completer<void>();
    server.listen((event) {
      if (event == RawSocketEvent.read &&
          server.receive() != null &&
          !received.isCompleted) {
        received.complete();
      }
    });
    final transport = LifxUdpTransport(host: '127.0.0.1', port: server.port);
    final pending = expectLater(transport.getState(), throwsStateError);
    await received.future.timeout(const Duration(seconds: 3));
    await transport.close();
    await pending.timeout(const Duration(seconds: 1));
    await expectLater(transport.getState(), throwsStateError);
  });
}
