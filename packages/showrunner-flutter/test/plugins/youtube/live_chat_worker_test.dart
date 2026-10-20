import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/services/plugin_event_hub.dart';
import 'package:showrunner_flutter/plugins/runtime/provider_event_workers.dart';
import 'package:showrunner_flutter/runtime/expression.dart';

void main() {
  test(
    'a previous generation cannot clear a restarted poll or report it healthy',
    () async {
      final hub = DartPluginEventHub();
      final oldResponse = Completer<RuntimeMap>(),
          newResponse = Completer<RuntimeMap>();
      var requests = 0;
      final worker = YouTubeLiveChatWorker(
        liveChatId: 'isolated',
        eventHub: hub,
        interval: const Duration(hours: 1),
        request: (_, _, _, _) =>
            ++requests == 1 ? oldResponse.future : newResponse.future,
      );
      final oldPoll = worker.pollOnce();
      await worker.stop();
      worker.start();
      final currentPoll = worker.pollOnce();
      expect(worker.state, ProviderWorkerState.starting);
      oldResponse.complete({'items': []});
      await oldPoll;
      expect(identical(worker.pollOnce(), currentPoll), isTrue);
      expect(worker.state, ProviderWorkerState.starting);
      newResponse.complete({'items': []});
      await currentPoll;
      expect(worker.state, ProviderWorkerState.running);
      expect(requests, 2);
      await worker.stop();
      await hub.dispose();
    },
  );

  test(
    'concurrent polls share one request and late success is ignored after stop',
    () async {
      final hub = DartPluginEventHub();
      final response = Completer<RuntimeMap>();
      var requests = 0;
      final messages = <RuntimeMap>[];
      final subscription = hub.stream('chatMessage').listen(messages.add);
      final worker = YouTubeLiveChatWorker(
        liveChatId: 'isolated',
        eventHub: hub,
        request: (_, _, _, _) {
          requests++;
          return response.future;
        },
      );
      final first = worker.pollOnce(), second = worker.pollOnce();
      expect(identical(first, second), isTrue);
      expect(requests, 1);
      await worker.stop();
      response.complete({
        'items': [
          {
            'snippet': {'type': 'textMessageEvent'},
          },
        ],
      });
      await Future.wait([first, second]);
      await Future<void>.delayed(Duration.zero);
      expect(messages, isEmpty);
      expect(worker.state, ProviderWorkerState.stopped);
      expect(worker.lastSuccessAt, isNull);
      await worker.pollOnce();
      expect(requests, 1);
      await subscription.cancel();
      await hub.dispose();
    },
  );

  test('late request failure cannot revive diagnostics after stop', () async {
    final hub = DartPluginEventHub();
    final response = Completer<RuntimeMap>();
    var errors = 0;
    final worker = YouTubeLiveChatWorker(
      liveChatId: 'isolated',
      eventHub: hub,
      onError: (_) => errors++,
      request: (_, _, _, _) => response.future,
    );
    final polling = worker.pollOnce();
    await worker.stop();
    response.completeError(StateError('Request completed after shutdown'));
    await polling;
    expect(worker.state, ProviderWorkerState.stopped);
    expect(worker.failureCount, 0);
    expect(errors, 0);
    await hub.dispose();
  });

  test(
    'polls YouTube live chat and emits typed events with the next page token',
    () async {
      final hub = DartPluginEventHub();
      final messages = <RuntimeMap>[];
      final memberships = <RuntimeMap>[];
      final stickers = <RuntimeMap>[];
      final messageSubscription = hub
          .stream('chatMessage')
          .listen(messages.add);
      final membershipSubscription = hub
          .stream('membership')
          .listen(memberships.add);
      final stickerSubscription = hub
          .stream('superSticker')
          .listen(stickers.add);
      var requestCount = 0;
      final worker = YouTubeLiveChatWorker(
        liveChatId: 'chat-1',
        eventHub: hub,
        request: (method, path, query, body) async {
          requestCount++;
          expect(query['liveChatId'], 'chat-1');
          if (requestCount == 2) expect(query['pageToken'], 'page-2');
          return {
            'nextPageToken': 'page-2',
            'items': [
              {
                'snippet': {
                  'type': requestCount == 1
                      ? 'textMessageEvent'
                      : 'superStickerEvent',
                },
              },
            ],
          };
        },
      );

      await worker.pollOnce();
      await worker.pollOnce();
      await Future<void>.delayed(Duration.zero);

      expect(messages, hasLength(1));
      expect(memberships, isEmpty);
      expect(stickers, hasLength(1));
      await messageSubscription.cancel();
      await membershipSubscription.cancel();
      await stickerSubscription.cancel();
      await hub.dispose();
    },
  );

  test('reports polling failures through worker diagnostics', () async {
    final hub = DartPluginEventHub();
    var statusChanges = 0;
    final worker = YouTubeLiveChatWorker(
      liveChatId: 'chat-1',
      eventHub: hub,
      onStatusChanged: () => statusChanges++,
      request: (method, path, query, body) async {
        throw StateError('YouTube is offline');
      },
    );

    await worker.pollOnce();

    expect(worker.state, ProviderWorkerState.error);
    expect(worker.failureCount, 1);
    expect(worker.lastError, isA<StateError>());
    expect(statusChanges, greaterThan(0));
    await worker.stop();
    expect(worker.state, ProviderWorkerState.stopped);
    await hub.dispose();
  });
}
