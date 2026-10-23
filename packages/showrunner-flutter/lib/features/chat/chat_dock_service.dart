import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'chat_dock_http_handler.dart';
import 'unified_chat_runtime.dart';

/// A local, authenticated OBS dock. Browser rendering stays in the overlay
/// package; this service exposes only chat capabilities, never OAuth secrets.
final class ChatDockService {
  ChatDockService({required this.runtime, this.webRoot});
  final UnifiedChatRuntime runtime;
  final Directory? webRoot;
  HttpServer? _server;
  ChatDockHttpHandler? _handler;
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
  Future<void> _lifecycle = Future<void>.value();
  int _generation = 0;
  Future<T> _serialize<T>(Future<T> Function() operation) {
    final result = _lifecycle.then((_) => operation());
    _lifecycle = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  Future<Uri> start() => _serialize(() async => url ?? await _start());
  Future<Uri> _start() async {
    final root = webRoot ?? _findWebRoot();
    if (root == null || !await File('${root.path}/chat-dock.html').exists()) {
      throw StateError(
        'Build the browser overlay before starting the chat dock.',
      );
    }
    final settings = await runtime.dataService.loadPluginSettings('chat-dock');
    final previousToken = settings['token'];
    final token = previousToken is String && previousToken.length >= 32
        ? previousToken
        : base64UrlEncode(
            List.generate(32, (_) => Random.secure().nextInt(256)),
          );
    final port = settings['port'] is int ? settings['port'] as int : 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    try {
      await runtime.dataService.updatePluginSettings('chat-dock', {
        'token': token,
        'port': server.port,
        'enabled': true,
      });
    } catch (_) {
      await server.close(force: true);
      rethrow;
    }
    _token = token;
    _server = server;
    final handler = ChatDockHttpHandler(
      runtime: runtime,
      root: root,
      port: server.port,
      token: token,
    );
    _handler = handler;
    server.listen(handler.handle);
    return url!;
  }

  Future<void> restore() async {
    final generation = _generation;
    final settings = await runtime.dataService.loadPluginSettings('chat-dock');
    if (generation == _generation && settings['enabled'] == true) await start();
  }

  Future<void> stop({bool disable = false}) {
    _generation++;
    return _serialize(() async {
      final server = _server;
      _handler?.close();
      _handler = null;
      _server = null;
      try {
        if (disable) {
          await runtime.dataService.updatePluginSetting(
            'chat-dock',
            'enabled',
            false,
          );
        }
      } finally {
        await server?.close(force: true);
      }
    });
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
