import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/plugins/remote/manifest.dart';
import 'package:showrunner_flutter/services/plugin_event_hub.dart';

void main() {
  test('exposes remote button trigger matching', () async {
    final eventHub = DartPluginEventHub();
    final registry = DartPluginRegistry()
      ..register(createRemotePlugin(eventHub: eventHub));
    final trigger = registry.findTrigger('remote', 'button')!;

    expect(trigger.matches!({'name': 'Start'}, {'name': 'Start'}), isTrue);
    expect(trigger.matches!({'name': 'Start'}, {'name': 'Stop'}), isFalse);

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
}
