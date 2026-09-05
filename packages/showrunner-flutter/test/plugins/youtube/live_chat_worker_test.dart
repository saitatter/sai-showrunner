import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/services/plugin_event_hub.dart';
import 'package:showrunner_flutter/plugins/runtime/provider_event_workers.dart';
import 'package:showrunner_flutter/runtime/expression.dart';

void main() {
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
