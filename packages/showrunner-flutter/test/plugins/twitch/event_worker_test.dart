import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/services/plugin_event_hub.dart';
import 'package:showrunner_flutter/plugins/twitch/actions.dart';
import 'package:showrunner_flutter/plugins/twitch/event_worker.dart';
import 'package:showrunner_flutter/plugins/runtime/provider_worker_status.dart';

void main() {
  test('routes platform trigger events through a Dart event hub', () async {
    final hub = DartPluginEventHub();
    final twitch = createTwitchPlugin(
      TwitchTransport((method, path, query, body) async => {}),
      eventHub: hub,
    );
    final trigger = twitch.triggers.firstWhere(
      (item) => item.triggerId == 'chat',
    );
    final eventFuture = trigger.listen().first;
    hub.emit('chat', {'viewerId': 'viewer-1', 'message': 'hello'});

    expect(await eventFuture, {'viewerId': 'viewer-1', 'message': 'hello'});
    await hub.dispose();
  });

  test('reports lifecycle and failed reconnect states', () async {
    final hub = DartPluginEventHub();
    final sockets = <_FakeEventSubSocket>[];
    var factoryCalls = 0;
    late TwitchEventSubWorker worker;
    final states = <ProviderWorkerState>[];

    worker = TwitchEventSubWorker(
      accessToken: 'token',
      clientId: 'client',
      broadcasterId: 'broadcaster',
      eventHub: hub,
      request: (method, path, query, body) async => {},
      reconnectDelay: Duration.zero,
      maxReconnectAttempts: 1,
      socketFactory: (uri) async {
        factoryCalls++;
        if (factoryCalls > 1) {
          throw StateError('reconnect failed');
        }
        final socket = _FakeEventSubSocket();
        sockets.add(socket);
        scheduleMicrotask(
          () => socket.add(
            jsonEncode({
              'payload': {
                'session': {'id': 'session-1'},
              },
            }),
          ),
        );
        return socket;
      },
      onStatusChanged: () => states.add(worker.state),
    );

    await worker.start();
    expect(worker.state, ProviderWorkerState.running);
    expect(states, [ProviderWorkerState.starting, ProviderWorkerState.running]);

    await sockets.single.closeFromPeer();
    await _waitFor(() => worker.state == ProviderWorkerState.error);

    expect(states, contains(ProviderWorkerState.reconnecting));
    expect(worker.reconnectAttempts, 1);
    expect(worker.lastError, isA<StateError>());

    await worker.stop();
    expect(worker.state, ProviderWorkerState.stopped);
    expect(states.last, ProviderWorkerState.stopped);
    await hub.dispose();
  });

  test('registers versioned subscriptions for exposed Twitch events', () async {
    final hub = DartPluginEventHub();
    final requests = <Map<String, dynamic>>[];
    final socket = _FakeEventSubSocket();
    final worker = TwitchEventSubWorker(
      accessToken: 'token',
      clientId: 'client',
      broadcasterId: 'broadcaster',
      eventHub: hub,
      request: (method, path, query, body) async {
        requests.add(Map<String, dynamic>.from(body as Map));
        return {};
      },
      socketFactory: (uri) async {
        scheduleMicrotask(
          () => socket.add(
            jsonEncode({
              'payload': {
                'session': {'id': 'session-1'},
              },
            }),
          ),
        );
        return socket;
      },
    );

    await worker.start();

    expect(
      requests.map((request) => request['type']),
      contains('channel.follow'),
    );
    expect(
      requests.map((request) => request['type']),
      contains('channel.raid'),
    );
    final follow = requests.firstWhere(
      (request) => request['type'] == 'channel.follow',
    );
    expect(follow['version'], '2');
    expect(follow['condition'], {
      'broadcaster_user_id': 'broadcaster',
      'moderator_user_id': 'broadcaster',
    });
    final incomingRaid = requests.firstWhere(
      (request) =>
          request['type'] == 'channel.raid' &&
          (request['condition'] as Map)['to_broadcaster_user_id'] != null,
    );
    expect(incomingRaid['condition'], {
      'to_broadcaster_user_id': 'broadcaster',
    });
    expect(worker.state, ProviderWorkerState.running);

    await worker.stop();
    await hub.dispose();
  });

  test(
    'keeps the worker running when an optional subscription lacks scope',
    () async {
      final hub = DartPluginEventHub();
      final socket = _FakeEventSubSocket();
      final worker = TwitchEventSubWorker(
        accessToken: 'token',
        clientId: 'client',
        broadcasterId: 'broadcaster',
        eventHub: hub,
        request: (method, path, query, body) async {
          if ((body as Map)['type'] == 'channel.follow') {
            throw StateError('missing moderator:read:followers scope');
          }
          return {};
        },
        socketFactory: (uri) async {
          scheduleMicrotask(
            () => socket.add(
              jsonEncode({
                'payload': {
                  'session': {'id': 'session-1'},
                },
              }),
            ),
          );
          return socket;
        },
      );

      await worker.start();

      expect(worker.state, ProviderWorkerState.running);
      expect(worker.subscriptionErrors.single, contains('channel.follow'));
      await worker.stop();
      await hub.dispose();
    },
  );
}

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 20 && !condition(); attempt++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(condition(), isTrue);
}

final class _FakeEventSubSocket implements EventSubSocket {
  final StreamController<dynamic> _controller = StreamController<dynamic>();

  @override
  Stream<dynamic> get messages => _controller.stream;

  void add(dynamic message) => _controller.add(message);

  Future<void> closeFromPeer() => _controller.close();

  @override
  Future<void> close([int? code, String? reason]) => _controller.close();
}
