import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/features/chat/chat_dock_service.dart';
import 'package:showrunner_flutter/features/chat/chat_message.dart';
import 'package:showrunner_flutter/features/chat/command_manager.dart';
import 'package:showrunner_flutter/features/chat/unified_chat_runtime.dart';
import 'package:showrunner_flutter/persistence/secret_settings_store.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/services/plugin_event_hub.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';

void main() {
  late Directory root;
  late ShowRunnerDataService data;
  late DartPluginEventHub hub;
  late UnifiedChatRuntime runtime;
  late ChatDockService dock;
  late HttpClient client;
  late Uri url;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('showrunner-chat-dock-');
    data = ShowRunnerDataService(
      root,
      secretSettings: SecretSettingsStore(
        directory: Directory('${root.path}/secrets'),
        encrypt: (bytes) async => bytes,
        decrypt: (bytes) async => bytes,
      ),
    );
    final web = await Directory(
      '${root.path}/web/assets',
    ).create(recursive: true);
    await File(
      '${web.parent.path}/chat-dock.html',
    ).writeAsString('<title>Chat fixture</title>');
    await File('${web.path}/dock.js').writeAsString('console.log("dock");');
    hub = DartPluginEventHub();
    runtime = UnifiedChatRuntime(
      eventHub: hub,
      dataService: data,
      registryFuture: Future.value(DartPluginRegistry()),
      commands: ChatCommandManager(
        repository: CommandRepository(root),
        execute: (_, _) async {},
      ),
    );
    await runtime.start();
    runtime.ingest(
      ChatMessage(
        platform: ChatPlatform.twitch,
        id: 'one',
        channelId: 'channel',
        userId: 'viewer',
        userName: '<b>Viewer</b>',
        text: '<script>bad()</script>',
        receivedAt: DateTime.utc(2026),
        source: {'accessToken': 'never-expose-this'},
      ),
    );
    dock = ChatDockService(runtime: runtime, webRoot: web.parent);
    url = await dock.start();
    client = HttpClient();
  });
  tearDown(() async {
    client.close(force: true);
    await dock.stop();
    await runtime.close();
    await hub.dispose();
    await root.delete(recursive: true);
  });
  Future<({int status, String text})> get(
    String path, {
    bool authenticate = false,
    String? origin,
    String? host,
  }) async {
    final request = await client.getUrl(url.resolve(path));
    if (authenticate) request.headers.set('x-showrunner-chat', url.fragment);
    if (origin != null) request.headers.set('origin', origin);
    if (host != null) request.headers.set('host', host);
    final response = await request.close();
    return (
      status: response.statusCode,
      text: await utf8.decoder.bind(response).join(),
    );
  }

  test(
    'serializes stop/start and concurrent starts without leaking listeners',
    () async {
      final stopping = dock.stop();
      final restarted = dock.start();
      await stopping;
      url = await restarted;
      final concurrent = await Future.wait([dock.start(), dock.start()]);
      expect(concurrent, [url, url]);
      expect((await get('/api/chat', authenticate: true)).status, 200);
      await dock.stop(disable: true);
      expect(dock.url, isNull);
    },
  );

  test(
    'authenticated preferences update syncs and rejects unsupported versions',
    () async {
      final snapshot =
          jsonDecode((await get('/api/chat', authenticate: true)).text) as Map;
      final preferences = Map<String, dynamic>.from(
        snapshot['preferences'] as Map,
      )..['fontSize'] = 19;
      Future<int> save(
        Map<String, dynamic> value, {
        bool authenticated = true,
      }) async {
        final request = await client.postUrl(url.resolve('/api/preferences'));
        if (authenticated) {
          request.headers.set('x-showrunner-chat', url.fragment);
        }
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(value));
        final response = await request.close();
        await response.drain<void>();
        return response.statusCode;
      }

      expect(await save(preferences, authenticated: false), 401);
      expect(runtime.preferences.fontSize, 14);
      expect(await save(preferences), 200);
      expect(runtime.preferences.fontSize, 19);
      expect(await save({...preferences, 'version': 10}), 400);
      expect((await data.loadPluginSettings('chat'))['fontSize'], 19);
    },
  );
  test(
    'serves browser assets but requires authentication for chat history',
    () async {
      expect((await get('/chat-dock')).status, 200);
      expect((await get('/overlays/assets/dock.js')).status, 200);
      expect((await get('/api/chat')).status, 401);
      final response = await get('/api/chat', authenticate: true);
      expect(response.status, 200);
      final snapshot = jsonDecode(response.text) as Map;
      expect(
        (snapshot['messages'] as List).single['viewerName'],
        '<b>Viewer</b>',
      );
      expect(response.text, isNot(contains('never-expose-this')));
      expect(response.text, isNot(contains(url.fragment)));
      expect((await get('/chat-dock')).text, isNot(contains(url.fragment)));
    },
  );
  test(
    'rejects cross-origin and forged Host requests even with the dock credential',
    () async {
      expect(
        (await get(
          '/api/chat',
          authenticate: true,
          origin: 'https://example.com',
        )).status,
        403,
      );
      expect(
        (await get(
          '/api/chat',
          authenticate: true,
          host: 'example.com:${url.port}',
        )).status,
        403,
      );
      expect(
        (await get(
          '/api/chat',
          authenticate: true,
          origin: 'http://127.0.0.1:${url.port}',
        )).status,
        200,
      );
    },
  );
  test(
    'persists a stable URL securely and stops/restores without changing provider credentials',
    () async {
      final settings = await File(
        '${root.path}/settings/chat-dock.yaml',
      ).readAsString();
      expect(settings, isNot(contains('token')));
      expect(settings, isNot(contains(url.fragment)));
      await dock.stop();
      await dock.restore();
      expect(dock.url, url);
      await dock.stop(disable: true);
      expect(
        (await File('${root.path}/settings/chat-dock.yaml').readAsString()),
        isNot(contains(url.fragment)),
      );
      await dock.restore();
      expect(dock.url, isNull);
    },
  );
  test(
    'rejects unsupported API operations and unknown message targets',
    () async {
      final request = await client.postUrl(url.resolve('/api/action'));
      request.headers.set('x-showrunner-chat', url.fragment);
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode({'identity': 'not-in-history', 'action': 'ban'}),
      );
      final response = await request.close();
      await response.drain<void>();
      expect(response.statusCode, 404);
      expect((await get('/api/action', authenticate: true)).status, 405);
    },
  );

  test(
    'validates typed dock requests before provider work with safe error codes',
    () async {
      Future<(int, Object?)> post(String path, String body) async {
        final request = await client.postUrl(url.resolve(path));
        request.headers.set('x-showrunner-chat', url.fragment);
        request.headers.contentType = ContentType.json;
        request.write(body);
        final response = await request.close();
        return (
          response.statusCode,
          jsonDecode(await utf8.decoder.bind(response).join()),
        );
      }

      for (final (path, payload, code) in [
        (
          '/api/send',
          <String, dynamic>{'platform': 'twitch', 'message': 42},
          'invalid_payload',
        ),
        (
          '/api/send',
          <String, dynamic>{'platform': 'invalid', 'message': 'hello'},
          'invalid_platform',
        ),
        (
          '/api/send',
          <String, dynamic>{'platform': 'youtube', 'message': 'x' * 201},
          'invalid_payload',
        ),
        (
          '/api/send',
          <String, dynamic>{
            'platform': 'twitch',
            'message': 'hello',
            'credential': 'private-marker',
          },
          'invalid_payload',
        ),
        (
          '/api/action',
          <String, dynamic>{'identity': 'one', 'action': 'unsupported'},
          'invalid_action',
        ),
        ('/api/clear', <String, dynamic>{'surprise': true}, 'invalid_payload'),
        (
          '/api/preferences',
          <String, dynamic>{'version': 99},
          'unsupported_preferences',
        ),
      ]) {
        final response = await post(path, jsonEncode(payload));
        expect(response.$1, 400);
        expect(response.$2, {'error': code});
      }
      final malformed = await post('/api/send', '{invalid');
      expect(malformed.$1, 400);
      expect(malformed.$2, {'error': 'invalid_json'});
      expect(runtime.messages, hasLength(1));
      final cleared = await post('/api/clear', '{}');
      expect(cleared.$1, 200);
      expect(cleared.$2, {'ok': true});
      expect(runtime.messages, isEmpty);
    },
  );
}
