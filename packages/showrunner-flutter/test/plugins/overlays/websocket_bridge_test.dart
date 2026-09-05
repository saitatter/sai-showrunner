import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/persistence/resource_repository.dart';
import 'package:showrunner_flutter/persistence/viewer_data_repository.dart';
import 'package:showrunner_flutter/schema/automation.dart';
import 'package:showrunner_flutter/plugins/http/manifest.dart';
import 'package:showrunner_flutter/plugins/overlays/manifest.dart';
import 'package:showrunner_flutter/plugins/overlays/websocket_bridge.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_bootstrap.dart';
import 'package:showrunner_flutter/plugins/sound/output.dart';
import 'package:showrunner_flutter/services/plugin_event_hub.dart';
import 'package:showrunner_flutter/schema/resource.dart';

void main() {
  test('serves an overlay config and forwards browser RPC events', () async {
    final directory = await Directory.systemTemp.createTemp(
      'showrunner-overlay-',
    );
    final webRoot = Directory('${directory.path}/web');
    await webRoot.create(recursive: true);
    await File('${webRoot.path}/overlay.html').writeAsString('<html />');
    final mediaRoot = Directory('${directory.path}/media');
    await mediaRoot.create(recursive: true);
    final mediaFile = File('${mediaRoot.path}/beep.wav');
    await mediaFile.writeAsBytes([1, 2, 3]);
    final repository = ResourceRepository(
      Directory('${directory.path}/overlays'),
    );
    await repository.save(
      const ResourceData(
        id: 'overlay-1',
        config: {
          'name': 'Test Overlay',
          'width': 1280,
          'height': 720,
          'widgets': [],
        },
      ),
    );
    final eventHub = DartPluginEventHub();
    final registry = createDefaultPluginRegistry(eventHub: eventHub);
    final server = DartHttpEndpointService(port: 0);
    await server.start();
    final bridge = DartOverlayWebSocketService(
      server: server,
      eventHub: eventHub,
      overlayStore: OverlayResourceStore(
        load: repository.load,
        save: repository.save,
      ),
      registry: registry,
      viewerDataRepository: InMemoryViewerDataRepository(),
      mediaRoot: mediaRoot,
      webRoot: webRoot,
    );
    final client = HttpClient();
    WebSocket? socket;
    StreamSubscription<dynamic>? socketSubscription;

    try {
      final configRequest = await client.getUrl(
        Uri.parse(
          'http://127.0.0.1:${server.boundPort}/overlays/overlay-1/config',
        ),
      );
      final configResponse = await configRequest.close();
      final config = jsonDecode(await utf8.decoder.bind(configResponse).join());
      expect(config, {
        'name': 'Test Overlay',
        'size': {'width': 1280, 'height': 720},
        'widgets': [],
      });

      socket = await WebSocket.connect(
        'ws://127.0.0.1:${server.boundPort}/?overlay=overlay-1',
      );
      final configReceived = Completer<JsonMap>();
      final broadcastReceived = Completer<List<dynamic>>();
      final audioReceived = Completer<List<dynamic>>();
      socketSubscription = socket.listen((raw) {
        final message = jsonDecode(raw as String) as Map<String, dynamic>;
        if (message['requestId'] != null) {
          final name = message['name']?.toString();
          final args = message['args'] is List
              ? List<dynamic>.from(message['args'] as List)
              : <dynamic>[];
          if (name == 'overlays_setConfig' && args.single is Map) {
            configReceived.complete(
              Map<String, dynamic>.from(args.single as Map),
            );
          }
          if (name == 'overlays_broadcast') {
            broadcastReceived.complete(args);
          }
          if (name == 'overlays_playAudio') {
            audioReceived.complete(args);
          }
          socket!.add(
            jsonEncode({'responseId': message['requestId'], 'result': null}),
          );
        }
      });

      expect(await configReceived.future, {
        'name': 'Test Overlay',
        'size': {'width': 1280, 'height': 720},
        'widgets': [],
      });
      eventHub.emit(OverlayEventIds.broadcast, {
        'broadcastId': 'showrunner_chat_message',
        'payload': {'message': 'hello'},
      });
      expect(await broadcastReceived.future, [
        'showrunner_chat_message',
        {'message': 'hello'},
      ]);
      expect(
        await bridge
            .playAudio(
              'overlay-1',
              SoundPlayRequest(file: mediaFile.path, volume: 75),
            )
            .timeout(const Duration(seconds: 2)),
        isTrue,
      );
      expect((await audioReceived.future).first, '/media/default/beep.wav');
    } finally {
      await socketSubscription?.cancel();
      await socket?.close();
      client.close(force: true);
      await bridge.dispose();
      await server.stop();
      await registry.close();
      await eventHub.dispose();
      await directory.delete(recursive: true);
    }
  });
}
