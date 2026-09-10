import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:showrunner_flutter/domain/errors/showrunner_error.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/plugins/runtime/provider_worker_status.dart';
import 'package:showrunner_flutter/plugins/twitch/event_worker.dart';
import 'package:showrunner_flutter/services/plugin_event_hub.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test(
    'plugin disable and re-enable changes action execution immediately',
    () async {
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
        );
      addTearDown(registry.close);

      expect(await registry.invokeAction('integration', 'ping', const {}), {
        'ok': true,
      });
      registry.setPluginEnabled('integration', false);
      expect(
        () => registry.invokeAction('integration', 'ping', const {}),
        throwsA(isA<PluginConfigurationError>()),
      );
      registry.setPluginEnabled('integration', true);
      expect(await registry.invokeAction('integration', 'ping', const {}), {
        'ok': true,
      });
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
