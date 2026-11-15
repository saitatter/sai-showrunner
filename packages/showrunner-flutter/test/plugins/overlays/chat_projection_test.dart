import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/persistence/viewer_data_repository.dart';
import 'package:showrunner_flutter/plugins/http/manifest.dart';
import 'package:showrunner_flutter/plugins/overlays/chat_projection.dart';
import 'package:showrunner_flutter/plugins/overlays/manifest.dart';
import 'package:showrunner_flutter/plugins/overlays/websocket_bridge.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_bootstrap.dart';
import 'package:showrunner_flutter/schema/resource.dart';
import 'package:showrunner_flutter/services/plugin_event_hub.dart';

ResourceData overlay([Map<String, Object?> config = const {}]) => ResourceData(
  id: 'overlay',
  config: {
    'widgets': [
      {
        'id': 'feed',
        'plugin': 'overlays',
        'widget': 'chatFeed',
        'config': {'source': 'unifiedChat', ...config},
      },
    ],
  },
);

void main() {
  final now = DateTime.utc(2026, 11, 15);
  OverlayChatEntry row(String id, {String platform = 'twitch', int age = 0}) =>
      OverlayChatEntry(
        id: id,
        platform: platform,
        displayName: 'Viewer',
        message: 'hello',
        receivedAt: now.subtract(Duration(seconds: age)),
        badges: ['moderator'],
      );

  test(
    'chat projection scopes platform, count, expiry and optional fields',
    () {
      final policy = OverlayChatProjection.fromResource(
        overlay({
          'maxMessages': 2,
          'fadeTime': 10,
          'platform': 'twitch',
          'showBadges': false,
        }),
        'feed',
      );
      final payload = policy.project([
        row('expired', age: 11),
        row('first'),
        row('second', platform: 'youtube'),
        row('last'),
      ], now);
      expect(payload, {
        'version': 1,
        'messages': [
          {
            'id': 'last',
            'platform': 'twitch',
            'displayName': 'Viewer',
            'message': 'hello',
            'expiresInMs': 10000,
          },
          {
            'id': 'first',
            'platform': 'twitch',
            'displayName': 'Viewer',
            'message': 'hello',
            'expiresInMs': 10000,
          },
        ],
      });
      final persistent = OverlayChatProjection.fromResource(
        overlay({'fadeTime': 0}),
        'feed',
      ).project([row('old', age: 10000)], now);
      expect(
        (persistent['messages'] as List).single,
        isNot(contains('expiresInMs')),
      );
    },
  );

  test('only a configured unified Chat Feed can expose chat history', () {
    expect(
      () => OverlayChatProjection.fromResource(
        overlay({'source': 'automation'}),
        'feed',
      ),
      throwsA(isA<OverlayChatNotEnabled>()),
    );
    expect(
      () => OverlayChatProjection.fromResource(overlay(), 'other'),
      throwsA(isA<OverlayChatNotEnabled>()),
    );
    for (final config in [
      <String, Object?>{'maxMessages': 201},
      {'maxMessages': 0},
      {'maxMessages': 1.5},
      {'fadeTime': -1},
      {'fadeTime': double.infinity},
      {'platform': 'unknown'},
      {'showBadges': 'true'},
    ]) {
      expect(
        () => OverlayChatProjection.fromResource(overlay(config), 'feed'),
        throwsFormatException,
      );
    }
    final policy = OverlayChatProjection.fromResource(
      overlay({'fadeTime': 0}),
      'feed',
    );
    expect(
      (policy.project([row('same'), row('same')], now)['messages'] as List),
      hasLength(1),
    );
  });

  test(
    'real HTTP chat reads require the overlay capability and recheck source revocation',
    () async {
      final hub = DartPluginEventHub();
      final registry = createDefaultPluginRegistry(eventHub: hub);
      final server = DartHttpEndpointService(port: 0);
      await server.start();
      ResourceData resource = overlay({'fadeTime': 0});
      Completer<List<OverlayChatEntry>>? pendingRead;
      Completer<void>? readStarted;
      var reads = 0;
      final bridge = DartOverlayWebSocketService(
        server: server,
        eventHub: hub,
        overlayStore: OverlayResourceStore(
          load: (id) async => id == 'overlay' ? resource : null,
          save: (_) async {},
        ),
        registry: registry,
        viewerDataRepository: InMemoryViewerDataRepository(),
        readChat: () async {
          reads++;
          readStarted?.complete();
          return pendingRead?.future ?? [row('message')];
        },
      );
      final client = HttpClient();
      addTearDown(() async {
        client.close(force: true);
        await bridge.dispose();
        await server.stop();
        await registry.close();
        await hub.dispose();
      });
      Future<({int status, String body})> get(
        String path, {
        String? token,
      }) async {
        final request = await client.getUrl(
          Uri.parse('http://127.0.0.1:${server.boundPort}$path'),
        );
        if (token != null) request.headers.set('x-showrunner-overlay', token);
        final response = await request.close();
        return (
          status: response.statusCode,
          body: await utf8.decoder.bind(response).join(),
        );
      }

      const path = '/overlays/overlay/chat/feed';
      final token = bridge.access.forOverlay('overlay');
      expect((await get(path)).status, HttpStatus.unauthorized);
      expect(
        (await get(path, token: bridge.access.forOverlay('another'))).status,
        HttpStatus.unauthorized,
      );
      expect(
        (await get('/overlays/overlay/chat/missing', token: token)).status,
        HttpStatus.forbidden,
      );
      expect(reads, 0);
      final valid = await get(path, token: token);
      expect(valid.status, HttpStatus.ok);
      expect(
        (jsonDecode(valid.body)['messages'] as List).single['id'],
        'message',
      );
      pendingRead = Completer<List<OverlayChatEntry>>();
      readStarted = Completer<void>();
      final inFlight = get(path, token: token);
      await readStarted.future.timeout(const Duration(seconds: 2));
      resource = overlay({'source': 'automation'});
      pendingRead.complete([row('must-not-leak')]);
      final denied = await inFlight;
      expect(denied.status, HttpStatus.forbidden);
      expect(denied.body, isNot(contains('must-not-leak')));
      expect(reads, 2);
    },
  );
}
