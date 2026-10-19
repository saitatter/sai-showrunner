import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../../persistence/filesystem/safe_path.dart';
import 'chat_message.dart';
import 'unified_chat_runtime.dart';

/// A local, authenticated OBS dock. Browser rendering stays in the overlay
/// package; this service exposes only chat capabilities, never OAuth secrets.
final class ChatDockService {
  ChatDockService({required this.runtime, this.webRoot});
  final UnifiedChatRuntime runtime;
  final Directory? webRoot;
  HttpServer? _server;
  String? _token;
  Uri? get url => _server == null
      ? null
      : Uri(
          scheme: 'http',
          host: '127.0.0.1',
          port: _server!.port,
          path: '/chat-dock',
          fragment: _token,
        );
  Future<Uri>? _starting;
  Future<Uri> start() =>
      _starting ??= _start().onError((Object error, StackTrace stack) {
        _starting = null;
        Error.throwWithStackTrace(error, stack);
      });
  Future<Uri> _start() async {
    final root = webRoot ?? _findWebRoot();
    if (root == null || !await File('${root.path}/chat-dock.html').exists()) {
      throw StateError(
        'Build the browser overlay before starting the chat dock.',
      );
    }
    final secrets = runtime.dataService.secretSettingsStore;
    final stored = await secrets.load('chat-dock');
    final settings = await runtime.dataService.loadPluginSettings('chat-dock');
    final previousToken = stored['token'];
    final token = previousToken is String && previousToken.length >= 32
        ? previousToken
        : base64UrlEncode(
            List.generate(32, (_) => Random.secure().nextInt(256)),
          );
    final port = settings['port'] is int ? settings['port'] as int : 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    try {
      await secrets.save('chat-dock', {'token': token});
      await runtime.dataService.savePluginSettings('chat-dock', {
        'port': server.port,
        'enabled': true,
      });
    } catch (_) {
      await server.close(force: true);
      rethrow;
    }
    _token = token;
    _server = server;
    server.listen((request) {
      _handle(request, root);
    });
    return url!;
  }

  Future<void> restore() async {
    final settings = await runtime.dataService.loadPluginSettings('chat-dock');
    if (settings['enabled'] == true) await start();
  }

  Future<void> stop({bool disable = false}) async {
    try {
      await _starting;
    } catch (_) {
      /* The start caller receives the failure. */
    }
    if (disable) {
      await runtime.dataService.updatePluginSetting(
        'chat-dock',
        'enabled',
        false,
      );
    }
    final server = _server;
    _server = null;
    _starting = null;
    await server?.close(force: true);
  }

  Future<void> _handle(HttpRequest request, Directory root) async {
    try {
      request.response.headers.set('Cache-Control', 'no-store');
      request.response.headers.set('Referrer-Policy', 'no-referrer');
      request.response.headers.set('X-Content-Type-Options', 'nosniff');
      request.response.headers.set(
        'Content-Security-Policy',
        "default-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self'; object-src 'none'; base-uri 'none'",
      );
      final origin = 'http://127.0.0.1:${_server?.port}';
      if (request.headers.value('host') != '127.0.0.1:${_server?.port}' ||
          (request.headers.value('origin') != null &&
              request.headers.value('origin') != origin)) {
        return await _respond(request, HttpStatus.forbidden);
      }
      final path = request.uri.path;
      if (path.startsWith('/api/')) {
        if (request.headers.value('x-showrunner-chat') != _token) {
          return await _respond(request, HttpStatus.unauthorized);
        }
        if (path == '/api/chat' && request.method == 'GET') {
          return await _respond(request, HttpStatus.ok, {
            'messages': runtime.messages
                .map(
                  (m) => {
                    'identity': m.identity,
                    ...m.context,
                    'deleted': m.deleted,
                    'time': m.receivedAt.toUtc().toIso8601String(),
                  },
                )
                .toList(),
            'emotes': runtime.emotes
                .map((e) => {'name': e.name, 'text': e.text})
                .toList(),
          });
        }
        if (request.method != 'POST') {
          return await _respond(request, HttpStatus.methodNotAllowed);
        }
        final bytes = <int>[];
        await for (final chunk in request.timeout(
          const Duration(seconds: 10),
        )) {
          bytes.addAll(chunk);
          if (bytes.length > 8192) {
            return await _respond(request, HttpStatus.requestEntityTooLarge);
          }
        }
        final payload = jsonDecode(utf8.decode(bytes));
        if (payload is! Map) {
          return await _respond(request, HttpStatus.badRequest);
        }
        if (path == '/api/send') {
          await runtime.send(
            ChatPlatform.values.byName(payload['platform'] as String),
            payload['message'] as String,
          );
        } else if (path == '/api/action') {
          final target = runtime.messages
              .where((m) => m.identity == payload['identity'])
              .firstOrNull;
          if (target == null) {
            return await _respond(request, HttpStatus.notFound);
          }
          await runtime.quickAction(
            target,
            ChatQuickAction.values.byName(payload['action'] as String),
          );
        } else {
          return await _respond(request, HttpStatus.notFound);
        }
        return await _respond(request, HttpStatus.ok, {'ok': true});
      }
      if (request.method != 'GET') {
        return await _respond(request, HttpStatus.methodNotAllowed);
      }
      File file;
      if (path == '/chat-dock') {
        file = await containedFile(root, ['chat-dock.html']);
      } else if (request.uri.pathSegments case [
        'overlays',
        'assets',
        final String name,
      ]) {
        file = await containedFile(root, ['assets', name]);
      } else {
        return await _respond(request, HttpStatus.notFound);
      }
      if (!await file.exists()) {
        return await _respond(request, HttpStatus.notFound);
      }
      request.response.headers.contentType = switch (file.path
          .split('.')
          .last) {
        'html' => ContentType.html,
        'css' => ContentType('text', 'css'),
        'js' => ContentType('application', 'javascript'),
        _ => ContentType.binary,
      };
      await request.response.addStream(file.openRead());
      await request.response.close();
    } catch (_) {
      // Provider error bodies and internal filesystem paths never leave the desktop.
      try {
        await _respond(request, HttpStatus.badRequest, {
          'error':
              'Chat operation failed. Check the account connection and permissions in ShowRunner.',
        });
      } catch (_) {
        /* disconnected browser */
      }
    }
  }

  Future<void> _respond(HttpRequest request, int code, [Object? body]) async {
    request.response.statusCode = code;
    if (body != null) {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(body));
    }
    await request.response.close();
  }

  Directory? _findWebRoot() {
    for (final path in [
      '${File(Platform.resolvedExecutable).parent.path}/obs-overlay',
      '${Directory.current.path}/obs-overlay',
      '${Directory.current.path}/../showrunner-obs-overlay/dist/obs-overlay',
      '${Directory.current.path}/packages/showrunner-obs-overlay/dist/obs-overlay',
    ]) {
      final directory = Directory(path);
      if (File('${directory.path}/chat-dock.html').existsSync()) {
        return directory;
      }
    }
    return null;
  }
}
