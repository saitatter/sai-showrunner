import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/persistence/resource_repository.dart';
import 'package:showrunner_flutter/persistence/viewer_data_repository.dart';
import 'package:showrunner_flutter/schema/json.dart';
import 'package:showrunner_flutter/plugins/http/manifest.dart';
import 'package:showrunner_flutter/plugins/overlays/manifest.dart';
import 'package:showrunner_flutter/plugins/overlays/overlay_protocol.generated.dart';
import 'package:showrunner_flutter/plugins/overlays/overlay_presence.dart';
import 'package:showrunner_flutter/plugins/overlays/websocket_bridge.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_bootstrap.dart';
import 'package:showrunner_flutter/plugins/sound/output.dart';
import 'package:showrunner_flutter/services/plugin_event_hub.dart';
import 'package:showrunner_flutter/schema/resource.dart';

void main() {
  for (final disposeDuringJoin in [false, true]) {
    test(
      'bounds and drains pending overlay joins: dispose=$disposeDuringJoin',
      () async {
        final started = Completer<void>();
        final loaded = Completer<ResourceData?>();
        var loads = 0;
        final hub = DartPluginEventHub();
        final registry = createDefaultPluginRegistry(eventHub: hub);
        final server = DartHttpEndpointService(port: 0);
        await server.start();
        final bridge = DartOverlayWebSocketService(
          server: server,
          eventHub: hub,
          registry: registry,
          viewerDataRepository: InMemoryViewerDataRepository(),
          maxPeers: 1,
          overlayStore: OverlayResourceStore(
            load: (_) {
              loads++;
              if (!started.isCompleted) started.complete();
              return loaded.future;
            },
            save: (_) async {},
          ),
        );
        final socket = await WebSocket.connect(
          'ws://127.0.0.1:${server.boundPort}/?overlay=probe',
        );
        final messages = StreamIterator<dynamic>(socket);
        try {
          await started.future.timeout(const Duration(seconds: 2));
          if (disposeDuringJoin) {
            var disposed = false;
            final closing = bridge.dispose().then((_) {
              disposed = true;
            });
            await Future<void>.delayed(Duration.zero);
            expect(disposed, isFalse);
            loaded.complete(const ResourceData(id: 'probe', config: {}));
            expect(await messages.moveNext(), isFalse);
            await closing;
            expect(socket.closeCode, WebSocketStatus.normalClosure);
            expect((await bridge.getPresence('probe')).subscribers, 0);
          } else {
            final rejected = await WebSocket.connect(
              'ws://127.0.0.1:${server.boundPort}/?overlay=probe',
            );
            await rejected.drain<void>().timeout(const Duration(seconds: 2));
            expect(rejected.closeCode, WebSocketStatus.policyViolation);
            expect(loads, 1);
            loaded.complete(
              const ResourceData(
                id: 'probe',
                config: {
                  'name': 'Probe',
                  'size': {'width': 100, 'height': 100},
                  'widgets': [],
                },
              ),
            );
            expect(await messages.moveNext(), isTrue);
            final config = decodeOverlayWire(
              jsonDecode(messages.current as String),
              'probe',
            );
            socket.add(
              jsonEncode(
                encodeOverlayWire({
                  'responseId': config['requestId'],
                  'result': null,
                }, 'probe'),
              ),
            );
            expect((await bridge.getPresence('probe')).subscribers, 1);
          }
        } finally {
          if (!loaded.isCompleted) loaded.complete(null);
          await messages.cancel();
          await socket.close();
          await bridge.dispose();
          await server.stop();
          await registry.close();
          await hub.dispose();
        }
      },
    );
  }

  for (final traffic in ['malformed', 'oversized', 'binary', 'silent']) {
    test('closes $traffic overlay peers without unhandled failures', () async {
      final directory = await Directory.systemTemp.createTemp(
        'overlay-boundary-',
      );
      final repository = ResourceRepository(
        Directory('${directory.path}/overlays'),
      );
      await repository.save(
        const ResourceData(
          id: 'probe',
          config: {
            'name': 'Probe',
            'size': {'width': 100, 'height': 100},
            'widgets': [],
          },
        ),
      );
      final hub = DartPluginEventHub();
      final registry = createDefaultPluginRegistry(eventHub: hub);
      final server = DartHttpEndpointService(port: 0);
      await server.start();
      final bridge = DartOverlayWebSocketService(
        server: server,
        eventHub: hub,
        overlayStore: OverlayResourceStore(
          load: repository.load,
          save: repository.save,
        ),
        registry: registry,
        viewerDataRepository: InMemoryViewerDataRepository(),
        requestTimeout: traffic == 'silent'
            ? const Duration(milliseconds: 20)
            : const Duration(seconds: 5),
      );
      final socket = await WebSocket.connect(
        'ws://127.0.0.1:${server.boundPort}/?overlay=probe',
      );
      final closed = Completer<void>();
      final subscription = socket.listen((raw) {
        final message = decodeOverlayWire(jsonDecode(raw as String), 'probe');
        if (traffic == 'silent') return;
        socket.add(
          jsonEncode(
            encodeOverlayWire({
              'responseId': message['requestId'],
              'result': null,
            }, 'probe'),
          ),
        );
        switch (traffic) {
          case 'malformed':
            socket.add('{invalid');
          case 'oversized':
            socket.add('x' * (1024 * 1024 + 1));
          case 'binary':
            socket.add([1, 2, 3]);
        }
      }, onDone: closed.complete);
      try {
        await closed.future.timeout(const Duration(seconds: 6));
        expect(socket.closeCode, switch (traffic) {
          'malformed' => WebSocketStatus.invalidFramePayloadData,
          'oversized' => WebSocketStatus.messageTooBig,
          'binary' => WebSocketStatus.unsupportedData,
          _ => WebSocketStatus.normalClosure,
        });
      } finally {
        await subscription.cancel();
        await socket.close();
        await bridge.dispose();
        await server.stop();
        await registry.close();
        await hub.dispose();
        await directory.delete(recursive: true);
      }
    });
  }

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
          'accessToken': 'fixture-not-public',
          'size': {'width': 1280, 'height': 720},
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
    expect(
      await bridge.getPresence('overlay-1'),
      const OverlayPresence(
        overlayId: 'overlay-1',
        connected: false,
        subscribers: 0,
      ),
    );
    expect(
      bridge.browserSourceUrl('overlay-1'),
      'http://localhost:${server.boundPort}/overlays/overlay-1',
    );
    final client = HttpClient();
    WebSocket? socket;
    StreamSubscription<dynamic>? socketSubscription;

    try {
      final missingRequest = await client.getUrl(
        Uri.parse(
          'http://127.0.0.1:${server.boundPort}/overlays/missing/config',
        ),
      );
      final missingResponse = await missingRequest.close();
      await missingResponse.drain<void>();
      expect(missingResponse.statusCode, HttpStatus.notFound);
      final missingSocket = await WebSocket.connect(
        'ws://127.0.0.1:${server.boundPort}/?overlay=missing',
      );
      expect(
        await missingSocket.toList().timeout(const Duration(seconds: 2)),
        isEmpty,
      );
      await expectLater(
        WebSocket.connect(
          'ws://127.0.0.1:${server.boundPort}/?overlay=overlay-1',
          headers: {'Origin': 'https://untrusted.invalid'},
        ),
        throwsA(isA<WebSocketException>()),
      );
      final configRequest = await client.getUrl(
        Uri.parse(
          'http://127.0.0.1:${server.boundPort}/overlays/overlay-1/config',
        ),
      );
      final configResponse = await configRequest.close();
      final config = jsonDecode(await utf8.decoder.bind(configResponse).join());
      expect(config, {
        'name': 'Test Overlay',
        'schemaVersion': 1,
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
        final message = decodeOverlayWire(
          jsonDecode(raw as String),
          'overlay-1',
        );
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
            jsonEncode(
              encodeOverlayWire({
                'responseId': message['requestId'],
                'result': null,
              }, 'overlay-1'),
            ),
          );
        }
      });

      expect(await configReceived.future, {
        'name': 'Test Overlay',
        'schemaVersion': 1,
        'size': {'width': 1280, 'height': 720},
        'widgets': [],
      });
      expect(
        await bridge.getPresence('overlay-1'),
        const OverlayPresence(
          overlayId: 'overlay-1',
          connected: true,
          subscribers: 1,
        ),
      );
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

      await socket.close();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      socket = null;
      expect(
        await bridge.getPresence('overlay-1'),
        const OverlayPresence(
          overlayId: 'overlay-1',
          connected: false,
          subscribers: 0,
        ),
      );
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
