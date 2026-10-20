import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/plugins/remote/contracts.dart';
import 'package:showrunner_flutter/plugins/remote/manifest.dart';
import 'package:showrunner_flutter/services/plugin_event_hub.dart';

void main() {
  for (final forgedHost in [false, true]) {
    test(
      'rejects browser remote-button requests with ${forgedHost ? 'forged Host' : 'foreign Origin'}',
      () async {
        final hub = DartPluginEventHub();
        final runtime = RemoteButtonRuntime(eventHub: hub, port: 0);
        final events = <dynamic>[];
        final subscription = hub.stream('remoteButton').listen(events.add);
        final client = HttpClient();
        await runtime.start();
        try {
          final request = await client.postUrl(
            Uri.parse(
              'http://127.0.0.1:${runtime.boundPort}/buttons/press?button=Start',
            ),
          );
          if (forgedHost) {
            request.headers.set(
              'Host',
              'untrusted.invalid:${runtime.boundPort}',
            );
          }
          request.headers.set(
            'Origin',
            'http://untrusted.invalid:${runtime.boundPort}',
          );
          final response = await request.close();
          await response.drain<void>();
          await Future<void>.delayed(Duration.zero);
          expect(response.statusCode, HttpStatus.forbidden);
          expect(events, isEmpty);
        } finally {
          client.close(force: true);
          await subscription.cancel();
          await runtime.stop();
          await hub.dispose();
        }
      },
    );
  }

  test('exposes remote button trigger matching', () async {
    final eventHub = DartPluginEventHub();
    final registry = DartPluginRegistry()
      ..register(createRemotePlugin(eventHub: eventHub));
    final trigger = registry.findTrigger('remote', 'button')!;
    expect(
      trigger.decodeConfig({'name': 'Start'}),
      isA<RemoteButtonTriggerConfig>(),
    );

    expect(
      trigger.matchesRuntime({'name': 'Start'}, {'name': 'Start'}),
      isTrue,
    );
    expect(
      trigger.matchesRuntime({'name': 'Start'}, {'name': 'Stop'}),
      isFalse,
    );

    await eventHub.dispose();
  });

  test('presses a remote button over the Dart HTTP server', () async {
    final eventHub = DartPluginEventHub();
    final runtime = RemoteButtonRuntime(
      eventHub: eventHub,
      host: '127.0.0.1',
      port: 0,
    );
    final events = <dynamic>[];
    final subscription = eventHub.stream('remoteButton').listen(events.add);
    await runtime.start();

    final client = HttpClient();
    final request = await client.postUrl(
      Uri.parse(
        'http://127.0.0.1:${runtime.boundPort}/buttons/press?button=Start',
      ),
    );
    final response = await request.close();
    await response.drain<void>();
    await Future<void>.delayed(Duration.zero);

    expect(response.statusCode, HttpStatus.noContent);
    expect(events, [
      {'name': 'Start'},
    ]);

    client.close(force: true);
    await subscription.cancel();
    await runtime.stop();
    await eventHub.dispose();
  });

  test('lists configured remote buttons over the Dart HTTP server', () async {
    final eventHub = DartPluginEventHub();
    final runtime = RemoteButtonRuntime(
      eventHub: eventHub,
      host: '127.0.0.1',
      port: 0,
      loadButtonNames: () async => ['Start', 'Stop'],
    );
    await runtime.start();

    final client = HttpClient();
    final request = await client.getUrl(
      Uri.parse('http://127.0.0.1:${runtime.boundPort}/buttons'),
    );
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();

    expect(response.statusCode, HttpStatus.ok);
    expect(jsonDecode(body), {
      'buttons': ['Start', 'Stop'],
    });

    client.close(force: true);
    await runtime.stop();
    await eventHub.dispose();
  });

  test('reports the remote HTTP server lifecycle', () async {
    final eventHub = DartPluginEventHub();
    final states = <String>[];
    final runtime = RemoteButtonRuntime(
      eventHub: eventHub,
      host: '127.0.0.1',
      port: 0,
      onStateChanged: states.add,
    );

    await runtime.start();
    await runtime.stop();

    expect(states, ['running', 'stopped']);
    await eventHub.dispose();
  });
}
