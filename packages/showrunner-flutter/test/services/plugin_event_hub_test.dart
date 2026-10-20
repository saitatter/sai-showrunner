import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/runtime/provider_event.dart';
import 'package:showrunner_flutter/runtime/expression.dart';
import 'package:showrunner_flutter/services/bounded_event_stream.dart';
import 'package:showrunner_flutter/services/plugin_event_hub.dart';

ProviderEventEnvelope envelope(
  String id, {
  bool private = false,
  RuntimeMap? payload,
}) => ProviderEventEnvelope(
  platform: ProviderPlatform.twitch,
  eventType: 'chat',
  providerEventId: id,
  accountId: 'account',
  channelId: 'channel',
  occurredAt: DateTime.utc(2026),
  visibility: private
      ? ProviderEventVisibility.private
      : ProviderEventVisibility.public,
  payload: payload ?? {'messageId': id},
);

Future<void> deliver() => Future<void>.delayed(Duration.zero);

void main() {
  test(
    'paused subscribers are bounded and overflow rejects publication to every subscriber',
    () async {
      final hub = DartPluginEventHub(pendingCapacity: 2);
      final slow = <RuntimeMap>[], fast = <RuntimeMap>[];
      final paused = hub.stream('event').listen(slow.add)..pause();
      final active = hub.stream('event').listen(fast.add);
      hub.emit('event', {'id': 1});
      hub.emit('event', {'id': 2});
      await deliver();
      expect(fast.map((event) => event['id']), [1, 2]);
      expect(slow, isEmpty);
      expect(
        () => hub.emit('event', {'id': 3}),
        throwsA(isA<EventBackpressureException>()),
      );
      expect(hub.rejectedEvents, 1);
      expect(hub.lastBackpressureError?.channel, 'event');
      await deliver();
      expect(fast, hasLength(2));
      paused.resume();
      await deliver();
      hub.emit('event', {'id': 3});
      await deliver();
      expect(slow.map((event) => event['id']), [1, 2, 3]);
      expect(fast.map((event) => event['id']), [1, 2, 3]);
      await paused.cancel();
      await active.cancel();
      await hub.dispose();
    },
  );

  test(
    'an unpaused burst is bounded before asynchronous delivery begins',
    () async {
      final hub = DartPluginEventHub(pendingCapacity: 2);
      final values = <RuntimeMap>[];
      final subscription = hub.stream('event').listen(values.add);
      hub.emit('event', {'id': 1});
      hub.emit('event', {'id': 2});
      expect(values, isEmpty);
      expect(
        () => hub.emit('event', {'id': 3}),
        throwsA(isA<EventBackpressureException>()),
      );
      await deliver();
      expect(values.map((event) => event['id']), [1, 2]);
      await subscription.cancel();
      await hub.dispose();
    },
  );

  test(
    'nested pause and cancellation retain bounds and release the channel',
    () async {
      final hub = DartPluginEventHub(pendingCapacity: 1);
      final values = <RuntimeMap>[];
      final subscription = hub.stream('event').listen(values.add)
        ..pause()
        ..pause();
      hub.emit('event', {'id': 1});
      subscription.resume();
      await deliver();
      expect(values, isEmpty);
      expect(
        () => hub.emit('event', {'id': 2}),
        throwsA(isA<EventBackpressureException>()),
      );
      subscription.resume();
      await deliver();
      expect(values.single['id'], 1);
      subscription.pause();
      hub.emit('event', {'id': 2});
      await subscription.cancel();
      hub.emit('event', {'id': 3});
      await hub.dispose();
    },
  );

  test(
    'shutdown cancels a paused consumer and rejects later publications',
    () async {
      final hub = DartPluginEventHub();
      hub
          .stream('event')
          .listen((_) => fail('Shutdown must cancel pending delivery'))
          .pause();
      hub.emit('event', {'id': 1});
      await Future.wait([hub.dispose(), hub.dispose()]);
      expect(() => hub.emit('event', {}), throwsStateError);
      expect(() => hub.stream('new'), throwsStateError);
    },
  );

  test('active subscribers receive done at shutdown', () async {
    final hub = DartPluginEventHub();
    final done = Completer<void>();
    hub.stream('event').listen((_) {}, onDone: done.complete);
    await hub.dispose();
    await done.future;
  });

  test(
    'typed and graph payload publication is atomic under backpressure',
    () async {
      final hub = DartPluginEventHub(pendingCapacity: 1);
      final typed = <ProviderEventEnvelope>[], graph = <RuntimeMap>[];
      final paused = hub.providerEvents.listen(typed.add)..pause();
      hub.stream('chat').listen(graph.add);
      hub.emitProviderEvent(envelope('first'));
      await deliver();
      expect(graph, hasLength(1));
      expect(
        () => hub.emitProviderEvent(envelope('rejected')),
        throwsA(isA<EventBackpressureException>()),
      );
      paused.resume();
      await deliver();
      expect(typed.map((event) => event.providerEventId), ['first']);
      expect(graph.map((event) => event['messageId']), ['first']);
      await hub.dispose();
    },
  );

  test('public provider events never buffer private whispers', () async {
    final hub = DartPluginEventHub(pendingCapacity: 1);
    final public = <ProviderEventEnvelope>[];
    final subscription = hub.publicProviderEvents.listen(public.add)..pause();
    hub.emitProviderEvent(envelope('public'));
    for (var index = 0; index < 10; index++) {
      hub.emitProviderEvent(envelope('private-$index', private: true));
    }
    subscription.resume();
    await deliver();
    expect(public.map((event) => event.providerEventId), ['public']);
    await hub.dispose();
  });

  test(
    'domain payloads are deeply immutable and redact credentials without changing message text',
    () {
      final event = envelope(
        'safe',
        payload: {
          'message': 'access_token is just text here',
          'access_token': 'secret',
          'nested': {'Client-Secret': 'secret', 'value': 42},
          'items': [
            {'password': 'secret', 'label': 'Visible'},
          ],
        },
      );
      expect(event.safePayload, {
        'message': 'access_token is just text here',
        'nested': {'value': 42},
        'items': [
          {'label': 'Visible'},
        ],
      });
      expect(
        () => event.safePayload['message'] = 'changed',
        throwsUnsupportedError,
      );
      expect(
        () => (event.safePayload['nested'] as Map)['value'] = 0,
        throwsUnsupportedError,
      );
      expect(
        () => (event.safePayload['items'] as List).clear(),
        throwsUnsupportedError,
      );
    },
  );

  test(
    'channel count and queue limits reject unsupported allocation',
    () async {
      expect(() => DartPluginEventHub(pendingCapacity: 0), throwsArgumentError);
      final hub = DartPluginEventHub(maxChannels: 1);
      hub.stream('allowed');
      expect(() => hub.stream('other'), throwsStateError);
      await hub.dispose();
    },
  );
}
