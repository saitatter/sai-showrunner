import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/overlays/overlay_peer.dart';

final class _Pair {
  _Pair(this.server, this.client, this.peer)
    : messages = StreamIterator(client);
  final HttpServer server;
  final WebSocket client;
  final OverlayPeer peer;
  final StreamIterator<dynamic> messages;
  static Future<_Pair> open({
    Duration timeout = const Duration(seconds: 1),
    int inbound = 16,
    int pending = 64,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final accepted = Completer<OverlayPeer>();
    server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      accepted.complete(
        OverlayPeer(
          socket,
          overlayId: 'fixture',
          requestTimeout: timeout,
          maxInboundRequests: inbound,
          maxPendingRequests: pending,
        ),
      );
    });
    final client = await WebSocket.connect('ws://127.0.0.1:${server.port}/');
    return _Pair(server, client, await accepted.future);
  }

  void request(String id) => client.add(
    jsonEncode({'requestId': id, 'name': 'fixture_read', 'args': []}),
  );
  Future<Map<String, dynamic>> next() async {
    expect(
      await messages.moveNext().timeout(const Duration(seconds: 2)),
      isTrue,
    );
    return jsonDecode(messages.current as String) as Map<String, dynamic>;
  }

  Future<void> closed() async {
    expect(
      await messages.moveNext().timeout(const Duration(seconds: 2)),
      isFalse,
    );
  }

  Future<void> dispose() async {
    await peer.close();
    await messages.cancel();
    await client.close();
    await server.close(force: true);
  }
}

void main() {
  test('closing settles outbound calls and cancels request timers', () async {
    final pair = await _Pair.open();
    addTearDown(pair.dispose);
    final first = pair.peer.call('fixture', []),
        second = pair.peer.call('fixture', []);
    final checked = [
      expectLater(first, throwsStateError),
      expectLater(second, throwsStateError),
    ];
    expect(pair.peer.pendingRequests, 2);
    final closing = pair.peer.close();
    await Future.wait(checked);
    expect(pair.peer.pendingRequests, 0);
    expect(pair.peer.isClosed, isTrue);
    await closing;
    await pair.peer.close();
  });
  test(
    'expired outbound calls release their slot and ignore a late response',
    () async {
      final pair = await _Pair.open(
        timeout: const Duration(milliseconds: 40),
        pending: 1,
      );
      addTearDown(pair.dispose);
      final call = pair.peer.call('fixture', []);
      final checked = expectLater(call, throwsA(isA<TimeoutException>()));
      final request = await pair.next();
      await checked;
      expect(pair.peer.pendingRequests, 0);
      pair.client.add(
        jsonEncode({'responseId': request['requestId'], 'result': 'late'}),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(pair.peer.isClosed, isFalse);
    },
  );
  test('outbound admission is bounded and an ACK releases its slot', () async {
    final pair = await _Pair.open(pending: 1);
    addTearDown(pair.dispose);
    final call = pair.peer.call('fixture', []);
    await expectLater(pair.peer.call('overflow', []), throwsStateError);
    final request = await pair.next();
    pair.client.add(
      jsonEncode({'responseId': request['requestId'], 'result': 42}),
    );
    expect(await call, 42);
    expect(pair.peer.pendingRequests, 0);
  });
  test('late domain results never write after peer closure', () async {
    final pair = await _Pair.open();
    addTearDown(pair.dispose);
    final entered = Completer<void>(), result = Completer<Object?>();
    pair.peer.onRequest = (_, _) {
      entered.complete();
      return result.future;
    };
    pair.request('one');
    await entered.future;
    await pair.peer.close();
    await pair.closed();
    result.complete('late');
    await Future<void>.delayed(Duration.zero);
    expect(pair.peer.activeRequests, 0);
  });
  test('expired inbound work keeps its slot until actual completion', () async {
    final pair = await _Pair.open(
      timeout: const Duration(milliseconds: 40),
      inbound: 1,
    );
    addTearDown(pair.dispose);
    final gate = Completer<Object?>();
    var calls = 0;
    pair.peer.onRequest = (_, _) {
      calls++;
      return gate.future;
    };
    pair.request('one');
    expect(await pair.next(), {'responseId': 'one', 'failed': true});
    expect(pair.peer.activeRequests, 1);
    pair.request('two');
    await pair.closed();
    expect(pair.client.closeCode, WebSocketStatus.policyViolation);
    expect(calls, 1);
    gate.complete(null);
    await Future<void>.delayed(Duration.zero);
    expect(pair.peer.activeRequests, 0);
  });
  test('duplicate request IDs cannot dispatch twice', () async {
    final pair = await _Pair.open();
    addTearDown(pair.dispose);
    var calls = 0;
    pair.peer.onRequest = (_, _) async {
      calls++;
      return null;
    };
    pair.request('one');
    await pair.next();
    pair.request('one');
    await pair.closed();
    expect(pair.client.closeCode, WebSocketStatus.policyViolation);
    expect(calls, 1);
  });
  test('domain errors return a payload-free failure', () async {
    final pair = await _Pair.open();
    addTearDown(pair.dispose);
    pair.peer.onRequest = (_, _) async =>
        throw StateError('private-provider-marker');
    pair.request('one');
    expect(await pair.next(), {'responseId': 'one', 'failed': true});
  });
  for (final value in [
    {'requestId': 42, 'name': 'read', 'args': []},
    {'requestId': '', 'name': 'read', 'args': []},
    {'requestId': 'x' * 129, 'name': 'read', 'args': []},
    {'requestId': 'one', 'name': 'read', 'args': {}},
    {'requestId': 'one', 'name': 'read', 'args': List.filled(33, null)},
    {'requestId': 'one', 'responseId': 'two', 'name': 'read', 'args': []},
  ]) {
    test(
      'invalid request shape is rejected before dispatch: ${value.keys}',
      () async {
        final pair = await _Pair.open();
        addTearDown(pair.dispose);
        var calls = 0;
        pair.peer.onRequest = (_, _) async {
          calls++;
          return null;
        };
        pair.client.add(jsonEncode(value));
        await pair.closed();
        expect(pair.client.closeCode, WebSocketStatus.invalidFramePayloadData);
        expect(calls, 0);
      },
    );
  }
}
