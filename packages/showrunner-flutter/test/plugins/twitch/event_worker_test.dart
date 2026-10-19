import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/services/plugin_event_hub.dart';
import 'package:showrunner_flutter/plugins/twitch/actions.dart';
import 'package:showrunner_flutter/plugins/twitch/event_worker.dart';
import 'package:showrunner_flutter/plugins/runtime/provider_worker_status.dart';

void main() {
  test(
    'stop cancels an unfinished welcome without resurrecting the worker',
    () async {
      final hub = DartPluginEventHub();
      final socket = _FakeEventSubSocket();
      final ready = Completer<void>();
      final worker = TwitchEventSubWorker(
        accessToken: 'token',
        clientId: 'client',
        broadcasterId: 'broadcaster',
        eventHub: hub,
        request: (method, path, query, body) async => {},
        socketFactory: (_) async {
          ready.complete();
          return socket;
        },
      );
      final start = worker.start();
      await ready.future;
      await Future<void>.delayed(Duration.zero);
      await worker.stop();
      await start.timeout(const Duration(seconds: 1));
      expect(worker.state, ProviderWorkerState.stopped);
      expect(socket.closed, true);
      await hub.dispose();
    },
  );
  test('deduplicates burst delivery and ignores malformed frames', () async {
    final hub = DartPluginEventHub();
    final socket = _FakeEventSubSocket();
    final worker = _workerWithSocket(socket, hub);
    final events = <Map>[];
    final listener = hub.stream('ban').listen(events.add);
    await worker.start();
    socket.add('{bad json');
    for (var i = 0; i < 100; i++) {
      final frame = jsonEncode({
        'metadata': {'message_type': 'notification', 'message_id': '$i'},
        'payload': {
          'subscription': {'type': 'channel.ban'},
          'event': {'user_id': '$i', 'is_permanent': true},
        },
      });
      socket.add(frame);
      socket.add(frame);
    }
    await _waitFor(() => events.length == 100);
    expect(
      events.map((event) => event['viewerId']),
      List.generate(100, (i) => '$i'),
    );
    await worker.stop();
    await listener.cancel();
    await hub.dispose();
  });

  test(
    'planned reconnect transfers subscriptions and closes the old socket',
    () async {
      final hub = DartPluginEventHub();
      final sockets = <_FakeEventSubSocket>[];
      final urls = <Uri>[];
      var requests = 0;
      final worker = TwitchEventSubWorker(
        accessToken: 'token',
        clientId: 'client',
        broadcasterId: 'broadcaster',
        eventHub: hub,
        subscriptionTypes: const ['channel.chat.message'],
        request: (method, path, query, body) async {
          requests++;
          return {};
        },
        socketFactory: (uri) async {
          urls.add(uri);
          final socket = _FakeEventSubSocket();
          sockets.add(socket);
          if (sockets.length == 1) {
            scheduleMicrotask(
              () => socket.add(
                jsonEncode({
                  'payload': {
                    'session': {'id': 'session-${sockets.length}'},
                  },
                }),
              ),
            );
          }
          return socket;
        },
      );
      await worker.start();
      sockets.first.add(
        jsonEncode({
          'metadata': {'message_type': 'session_reconnect'},
          'payload': {
            'session': {
              'reconnect_url': 'wss://eventsub.wss.twitch.tv/ws?reconnect=test',
            },
          },
        }),
      );
      await _waitFor(() => urls.length == 2);
      final duringHandover = hub.stream('chat').first;
      sockets.first.add(
        jsonEncode({
          'metadata': {'message_type': 'notification', 'message_id': 'overlap'},
          'payload': {
            'subscription': {'type': 'channel.chat.message'},
            'event': {
              'message': {'text': 'still connected'},
            },
          },
        }),
      );
      expect((await duringHandover)['message'], 'still connected');
      expect(sockets.first.closed, false);
      sockets.last.add(
        jsonEncode({
          'payload': {
            'session': {'id': 'transferred'},
          },
        }),
      );
      await _waitFor(() => worker.isRunning);
      expect(urls.last.query, 'reconnect=test');
      expect(requests, 1);
      expect(sockets.first.closed, isTrue);
      await worker.stop();
      await hub.dispose();
    },
  );

  test('welcome timeout disposes the failed connection', () async {
    final hub = DartPluginEventHub();
    final socket = _FakeEventSubSocket();
    final worker = TwitchEventSubWorker(
      accessToken: 'token',
      clientId: 'client',
      broadcasterId: 'broadcaster',
      eventHub: hub,
      request: (method, path, query, body) async => {},
      socketFactory: (_) async => socket,
      welcomeTimeout: const Duration(milliseconds: 20),
    );
    await expectLater(worker.start(), throwsA(isA<TimeoutException>()));
    expect(socket.closed, isTrue);
    expect(worker.state, ProviderWorkerState.error);
    await worker.stop();
    await hub.dispose();
  });

  test(
    'silent connections reconnect when the keepalive deadline passes',
    () async {
      final hub = DartPluginEventHub();
      var connections = 0;
      final reconnected = Completer<void>();
      Duration? keepaliveDeadline;
      late final TwitchEventSubWorker worker;
      worker = TwitchEventSubWorker(
        accessToken: 'token',
        clientId: 'client',
        broadcasterId: 'broadcaster',
        eventHub: hub,
        subscriptionTypes: const [],
        reconnectDelay: Duration.zero,
        onStatusChanged: () {
          final error = worker.lastError;
          if (worker.isReconnecting && error is TimeoutException) {
            keepaliveDeadline = error.duration;
          }
          if (connections == 2 &&
              worker.isRunning &&
              !reconnected.isCompleted) {
            reconnected.complete();
          }
        },
        request: (method, path, query, body) async => {},
        socketFactory: (_) async {
          connections++;
          final socket = _FakeEventSubSocket();
          scheduleMicrotask(
            () => socket.add(
              jsonEncode({
                'payload': {
                  'session': {
                    'id': '$connections',
                    'keepalive_timeout_seconds': 0.02,
                  },
                },
              }),
            ),
          );
          return socket;
        },
      );
      try {
        await worker.start();
        await reconnected.future.timeout(const Duration(seconds: 1));
        expect(keepaliveDeadline, const Duration(milliseconds: 20));
        expect(connections, 2);
        expect(worker.isRunning, isTrue);
      } finally {
        await worker.stop();
        await hub.dispose();
      }
      expect(worker.state, ProviderWorkerState.stopped);
    },
  );
  test('routes platform trigger events through a Dart event hub', () async {
    final hub = DartPluginEventHub();
    final twitch = createTwitchPlugin(
      TwitchTransport((method, path, query, body) async => {}),
      eventHub: hub,
    );
    final trigger = twitch.triggers.firstWhere(
      (item) => item.triggerId.value == 'chat',
    );
    final runtimeEventFuture = trigger.listenFromRuntime().first;
    hub.emit('chat', {'viewerId': 'viewer-1', 'message': 'hello'});

    expect(await runtimeEventFuture, {
      'viewerId': 'viewer-1',
      'message': 'hello',
    });
    await hub.dispose();
  });

  test('normalizes EventSub chat payloads to typed graph fields', () async {
    final hub = DartPluginEventHub();
    final socket = _FakeEventSubSocket();
    final worker = TwitchEventSubWorker(
      accessToken: 'token',
      clientId: 'client',
      broadcasterId: 'broadcaster',
      eventHub: hub,
      subscriptionTypes: const ['channel.chat.message'],
      request: (method, path, query, body) async => {},
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
    final eventFuture = hub.stream('chat').first;
    socket.add(
      jsonEncode({
        'metadata': {'message_type': 'notification'},
        'payload': {
          'subscription': {'type': 'channel.chat.message'},
          'event': {
            'chatter_user_id': 'viewer-1',
            'chatter_user_name': 'Viewer',
            'message_id': 'message-1',
            'message': {'text': 'hello', 'fragments': []},
            'badges': [
              {'set_id': 'subscriber'},
            ],
          },
        },
      }),
    );

    expect(await eventFuture, {
      'chatter_user_id': 'viewer-1',
      'chatter_user_name': 'Viewer',
      'message_id': 'message-1',
      'message': 'hello',
      'eventType': 'chat',
      'platform': 'twitch',
      'viewerId': 'viewer-1',
      'viewerName': 'Viewer',
      'messageId': 'message-1',
      'badges': 'subscriber',
    });

    await worker.stop();
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
    final types = requests.map((request) => request['type']);
    expect(types, isNot(contains('channel.ad_break.end')));
    expect(types, isNot(contains('channel.ad_schedule')));
    expect(
      requests.firstWhere((item) => item['type'] == 'channel.ban')['condition'],
      {'broadcaster_user_id': 'broadcaster'},
    );
    expect(
      requests.firstWhere(
        (item) => item['type'] == 'channel.shoutout.receive',
      )['condition'],
      {
        'broadcaster_user_id': 'broadcaster',
        'moderator_user_id': 'broadcaster',
      },
    );
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

  test(
    'routes temporary and permanent bans using real EventSub fields',
    () async {
      final hub = DartPluginEventHub();
      final socket = _FakeEventSubSocket();
      final worker = _workerWithSocket(socket, hub);
      await worker.start();
      for (final permanent in [false, true]) {
        final result = hub.stream(permanent ? 'ban' : 'timeout').first;
        socket.add(
          jsonEncode({
            'metadata': {'message_type': 'notification'},
            'payload': {
              'subscription': {'type': 'channel.ban'},
              'event': {
                'user_id': 'viewer',
                'is_permanent': permanent,
                'ends_at': permanent ? null : '2026-10-16T12:00:00Z',
              },
            },
          }),
        );
        expect((await result)['eventType'], permanent ? 'ban' : 'timeout');
      }
      await worker.stop();
      await hub.dispose();
    },
  );

  test(
    'reads ad schedules over Helix and derives ad end from the deadline',
    () async {
      final hub = DartPluginEventHub();
      final socket = _FakeEventSubSocket();
      final scheduleFuture = hub.stream('adSchedule').first;
      final worker = _workerWithSocket(socket, hub, adSchedule: true);
      await worker.start();
      expect((await scheduleFuture)['next_ad_at'], '123');
      final ended = hub.stream('adEnded').first;
      socket.add(
        jsonEncode({
          'metadata': {'message_type': 'notification'},
          'payload': {
            'subscription': {'type': 'channel.ad_break.begin'},
            'event': {
              'duration_seconds': 1,
              'started_at': DateTime.now()
                  .subtract(const Duration(seconds: 2))
                  .toUtc()
                  .toIso8601String(),
            },
          },
        }),
      );
      expect(
        (await ended.timeout(const Duration(seconds: 2)))['eventType'],
        'adEnded',
      );
      await worker.stop();
      await hub.dispose();
    },
  );
}

TwitchEventSubWorker _workerWithSocket(
  _FakeEventSubSocket socket,
  DartPluginEventHub hub, {
  bool adSchedule = false,
}) => TwitchEventSubWorker(
  accessToken: 'token',
  clientId: 'client',
  broadcasterId: 'broadcaster',
  eventHub: hub,
  subscriptionTypes: [adSchedule ? 'channel.ad_break.begin' : 'channel.ban'],
  request: (method, path, query, body) async => method == 'GET'
      ? {
          'data': [
            {'next_ad_at': '123'},
          ],
        }
      : {},
  socketFactory: (_) async {
    scheduleMicrotask(
      () => socket.add(
        jsonEncode({
          'payload': {
            'session': {'id': 'session'},
          },
        }),
      ),
    );
    return socket;
  },
);

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 20 && !condition(); attempt++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(condition(), isTrue);
}

final class _FakeEventSubSocket implements EventSubSocket {
  bool get closed => _controller.isClosed;
  final StreamController<dynamic> _controller = StreamController<dynamic>();

  @override
  Stream<dynamic> get messages => _controller.stream;

  void add(dynamic message) => _controller.add(message);

  Future<void> closeFromPeer() => _controller.close();

  @override
  Future<void> close([int? code, String? reason]) => _controller.close();
}
