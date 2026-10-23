import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/overlays/overlay_peer.dart';
import 'package:showrunner_flutter/plugins/overlays/overlay_protocol.generated.dart';
import 'package:showrunner_flutter/plugins/overlays/overlay_rpc_dispatcher.dart';
import 'package:showrunner_flutter/plugins/overlays/manifest.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/persistence/viewer_data_repository.dart';
import 'package:showrunner_flutter/schema/resource.dart';
import 'package:showrunner_flutter/schema/viewer_data.dart';
import 'package:showrunner_flutter/services/plugin_event_hub.dart';

final class _ViewerProbe implements ViewerDataRepository {
  int reads = 0;
  @override
  Future<List<ViewerDataRow>> queryViewers(
    String provider, {
    int start = 0,
    int? end,
    String sortBy = 'id',
    bool descending = false,
  }) async {
    reads++;
    return [
      for (var index = 0; index < 150; index++)
        ViewerDataRow(
          provider: provider,
          viewer: ViewerIdentity(id: '$index', displayName: 'Viewer $index'),
          values: const {},
        ),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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

  void request(
    String id, [
    String name = 'fixture_read',
    List<dynamic> args = const [],
  ]) => client.add(
    jsonEncode(
      encodeOverlayWire({
        'requestId': id,
        'name': name,
        'args': args,
      }, 'fixture'),
    ),
  );
  Future<Map<String, dynamic>> next() async {
    expect(
      await messages.moveNext().timeout(const Duration(seconds: 2)),
      isTrue,
    );
    return decodeOverlayWire(jsonDecode(messages.current as String), 'fixture');
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
  test(
    'RPC validation rejects invalid pages before reads and foreign widgets before events',
    () async {
      final pair = await _Pair.open();
      addTearDown(pair.dispose);
      final registry = DartPluginRegistry();
      final hub = DartPluginEventHub();
      addTearDown(registry.close);
      addTearDown(hub.dispose);
      final repository = _ViewerProbe();
      var resourceReads = 0;
      var events = 0;
      final subscription = hub.stream(OverlayEventIds.widgetRpc).listen((_) {
        events++;
      });
      addTearDown(subscription.cancel);
      final dispatcher = OverlayRpcDispatcher(
        registry: registry,
        eventHub: hub,
        viewerDataRepository: repository,
        overlayStore: OverlayResourceStore(
          load: (_) async {
            resourceReads++;
            return const ResourceData(
              id: 'fixture',
              config: {
                'widgets': [
                  {'id': 'owned'},
                ],
              },
            );
          },
          save: (_) async {},
        ),
        send: (_, _, _) async {},
      );
      pair.peer.onRequest = (name, args) =>
          dispatcher.handle(pair.peer, name, args);
      var next = 0;
      for (final args in <List<dynamic>>[
        [-1, 10],
        [0.5, 10],
        ['0', 10],
        [0, 101],
        [10001, 10002],
        [10, 9],
        [0, 10, {}],
        [0, 10, 'id', 0],
        [0, 10, 'id', 1, 'extra'],
      ]) {
        final id = 'query-${next++}';
        pair.request(id, 'overlays_queryViewerData', args);
        expect(await pair.next(), {'responseId': id, 'failed': true});
      }
      expect(repository.reads, 0);
      pair.request('valid', 'overlays_queryViewerData', [0, 100]);
      expect((await pair.next())['result'], hasLength(100));
      expect(repository.reads, 2);
      pair.request('wrong-widget', 'overlays_widgetRPC', ['click', 'foreign']);
      expect(await pair.next(), {'responseId': 'wrong-widget', 'failed': true});
      expect(events, 0);
      expect(resourceReads, 1);
      pair.request('owned-widget', 'overlays_widgetRPC', ['click', 'owned']);
      expect(await pair.next(), {'responseId': 'owned-widget', 'result': null});
      expect(events, 1);
      pair.request('unknown-state', 'overlays_acquireState', [
        'unknown',
        'state',
      ]);
      expect(await pair.next(), {
        'responseId': 'unknown-state',
        'failed': true,
      });
      expect(pair.peer.acquiredStates, isEmpty);
      registry.register(
        DartPluginManifest(
          id: const PluginId('probe'),
          name: 'Probe',
          states: [
            for (var index = 0; index < 65; index++)
              StateSpec<int>(
                id: StateId('state$index'),
                displayName: 'State $index',
                initialValue: index,
              ),
          ],
        ),
      );
      for (var index = 0; index < 64; index++) {
        pair.request('acquire-$index', 'overlays_acquireState', [
          'probe',
          'state$index',
        ]);
        expect(await pair.next(), {
          'responseId': 'acquire-$index',
          'result': null,
        });
      }
      pair.request('overflow', 'overlays_acquireState', ['probe', 'state64']);
      expect(await pair.next(), {'responseId': 'overflow', 'failed': true});
      expect(pair.peer.acquiredStates, hasLength(64));
      pair.request('release', 'overlays_freeState', ['probe', 'state0']);
      await pair.next();
      pair.request('replacement', 'overlays_acquireState', [
        'probe',
        'state64',
      ]);
      expect(await pair.next(), {'responseId': 'replacement', 'result': null});
      expect(pair.peer.acquiredStates, hasLength(64));
    },
  );

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
        jsonEncode(
          encodeOverlayWire({
            'responseId': request['requestId'],
            'result': 'late',
          }, 'fixture'),
        ),
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
      jsonEncode(
        encodeOverlayWire({
          'responseId': request['requestId'],
          'result': 42,
        }, 'fixture'),
      ),
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
        pair.client.add(
          jsonEncode({
            'protocolVersion': 1,
            'type': 'request',
            'resourceId': 'fixture',
            'requestId': value['requestId'],
            'payload': {
              for (final entry in value.entries)
                if (entry.key != 'requestId') entry.key: entry.value,
            },
          }),
        );
        await pair.closed();
        expect(pair.client.closeCode, WebSocketStatus.invalidFramePayloadData);
        expect(calls, 0);
      },
    );
  }
}
