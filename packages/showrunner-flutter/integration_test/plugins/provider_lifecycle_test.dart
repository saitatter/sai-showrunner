import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:showrunner_flutter/domain/errors/showrunner_error.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_lifecycle.dart';
import 'package:showrunner_flutter/plugins/runtime/provider_worker_status.dart';
import 'package:showrunner_flutter/plugins/twitch/event_worker.dart';
import 'package:showrunner_flutter/services/plugin_event_hub.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test(
    'plugin disable and re-enable changes action execution immediately',
    () async {
      var starts = 0, stops = 0;
      final registry = DartPluginRegistry()
        ..register(
          DartPluginManifest(
            id: PluginId('integration'),
            name: 'Integration',
            actions: [
              ActionSpec<Map<String, dynamic>, Object?>(
                pluginId: PluginId('integration'),
                actionId: ActionId('ping'),
                invoke: (config, context) async => {'ok': true},
              ),
            ],
          ),
          onStart: () async => starts++,
          onStop: () async => stops++,
        );
      addTearDown(registry.close);
      await registry.initialize();
      await registry.start();

      expect(await registry.invokeAction('integration', 'ping', const {}), {
        'ok': true,
      });
      final policyWrites = <bool>[];
      Future<void> persist(bool enabled) async => policyWrites.add(enabled);
      await registry.setEnabled(
        const PluginId('integration'),
        false,
        persist: persist,
      );
      expect(
        registry.lifecycleOf(const PluginId('integration')),
        PluginLifecycleState.running,
      );
      expect(stops, 0);
      expect(
        () => registry.invokeAction('integration', 'ping', const {}),
        throwsA(isA<PluginConfigurationError>()),
      );
      await registry.setEnabled(
        const PluginId('integration'),
        true,
        persist: persist,
      );
      expect(await registry.invokeAction('integration', 'ping', const {}), {
        'ok': true,
      });
      expect(policyWrites, [false, true]);
      expect(starts, 1);
      await registry.close();
      expect(stops, 1);
    },
  );

  test('Twitch provider reconnects after the EventSub socket closes', () async {
    final hub = DartPluginEventHub();
    addTearDown(hub.dispose);
    final sockets = <_FakeEventSubSocket>[];
    final states = <ProviderWorkerState>[];
    late final TwitchEventSubWorker worker;
    worker = TwitchEventSubWorker(
      accessToken: 'token',
      clientId: 'client',
      broadcasterId: 'broadcaster',
      request: (method, path, query, body) async => <String, dynamic>{},
      eventHub: hub,
      subscriptions: const [],
      reconnectDelay: const Duration(milliseconds: 2),
      maxReconnectAttempts: 2,
      onStatusChanged: () => states.add(worker.state),
      socketFactory: (_) async {
        final socket = _FakeEventSubSocket();
        sockets.add(socket);
        scheduleMicrotask(
          () => socket.add(
            jsonEncode({
              'payload': {
                'session': {'id': 'session-${sockets.length}'},
              },
            }),
          ),
        );
        return socket;
      },
    );

    await worker.start();
    expect(worker.state, ProviderWorkerState.running);
    await sockets.first.disconnect();
    for (var attempt = 0; attempt < 20; attempt++) {
      if (sockets.length == 2 && worker.isRunning) break;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }

    expect(sockets, hasLength(2));
    expect(worker.state, ProviderWorkerState.running);
    expect(worker.reconnectAttempts, greaterThanOrEqualTo(1));
    expect(states, contains(ProviderWorkerState.reconnecting));
    await worker.stop();
    expect(worker.state, ProviderWorkerState.stopped);
  });

  test(
    'Twitch provider remains stable through repeated reconnect cycles',
    () async {
      final hub = DartPluginEventHub();
      addTearDown(hub.dispose);
      final sockets = <_FakeEventSubSocket>[];
      late final TwitchEventSubWorker worker;
      worker = TwitchEventSubWorker(
        accessToken: 'token',
        clientId: 'client',
        broadcasterId: 'broadcaster',
        request: (method, path, query, body) async => <String, dynamic>{},
        eventHub: hub,
        subscriptions: const [],
        reconnectDelay: const Duration(milliseconds: 1),
        maxReconnectAttempts: 2,
        socketFactory: (_) async {
          final socket = _FakeEventSubSocket();
          sockets.add(socket);
          scheduleMicrotask(
            () => socket.add(
              jsonEncode({
                'payload': {
                  'session': {'id': 'soak-session-${sockets.length}'},
                },
              }),
            ),
          );
          return socket;
        },
      );

      await worker.start();
      for (var cycle = 0; cycle < 12; cycle++) {
        final socketCountBeforeDisconnect = sockets.length;
        await sockets.last.disconnect();
        for (var attempt = 0; attempt < 40; attempt++) {
          if (sockets.length > socketCountBeforeDisconnect &&
              worker.isRunning) {
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 2));
        }
        expect(sockets.length, socketCountBeforeDisconnect + 1);
        expect(worker.state, ProviderWorkerState.running);
        expect(worker.reconnectAttempts, greaterThanOrEqualTo(1));
      }

      await worker.stop();
      expect(worker.state, ProviderWorkerState.stopped);
      expect(sockets, hasLength(13));
    },
  );
}

final class _FakeEventSubSocket implements EventSubSocket {
  final StreamController<dynamic> _messages = StreamController<dynamic>();

  @override
  Stream<dynamic> get messages => _messages.stream;

  void add(dynamic message) => _messages.add(message);

  Future<void> disconnect() => _messages.close();

  @override
  Future<void> close([int? code, String? reason]) => _messages.close();
}
