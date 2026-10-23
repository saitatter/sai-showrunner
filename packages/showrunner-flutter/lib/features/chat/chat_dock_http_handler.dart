import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../../persistence/filesystem/safe_path.dart';
import 'unified_chat_runtime.dart';
import 'chat_dock_protocol.dart';

/// Owns routing for one immutable loopback dock listener, never app settings.
final class ChatDockHttpHandler {
  ChatDockHttpHandler({
    required this.runtime,
    required this.root,
    required this.port,
    required this.token,
  });
  final UnifiedChatRuntime runtime;
  final Directory root;
  final int port;
  final String token;
  bool _closed = false;
  void close() {
    _closed = true;
  }

  Future<void> handle(HttpRequest request) async {
    try {
      if (_closed) {
        return await _respond(request, HttpStatus.serviceUnavailable);
      }
      request.response.headers.set('Cache-Control', 'no-store');
      request.response.headers.set('Referrer-Policy', 'no-referrer');
      request.response.headers.set('X-Content-Type-Options', 'nosniff');
      request.response.headers.set(
        'Content-Security-Policy',
        "default-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self'; img-src 'self' https://static-cdn.jtvnw.net https://cdn.betterttv.net https://cdn.frankerfacez.com https://cdn.7tv.app https://cdn.7tv.io; object-src 'none'; base-uri 'none'",
      );
      final origin = 'http://127.0.0.1:$port';
      if (request.headers.value('host') != '127.0.0.1:$port' ||
          (request.headers.value('origin') != null &&
              request.headers.value('origin') != origin)) {
        return await _respond(request, HttpStatus.forbidden);
      }
      final path = request.uri.path;
      if (path.startsWith('/api/')) {
        if (request.headers.value('x-showrunner-chat') != token) {
          return await _respond(request, HttpStatus.unauthorized);
        }
        if (path == '/api/chat' && request.method == 'GET') {
          return await _respond(
            request,
            HttpStatus.ok,
            chatDockSnapshot(runtime),
          );
        }
        if (request.method != 'POST') {
          return await _respond(request, HttpStatus.methodNotAllowed);
        }
        final bytes = <int>[];
        await for (final chunk in request.timeout(
          const Duration(seconds: 10),
        )) {
          bytes.addAll(chunk);
          if (bytes.length > (path == '/api/preferences' ? 262144 : 8192)) {
            return await _respond(request, HttpStatus.requestEntityTooLarge);
          }
        }
        if (_closed) {
          return await _respond(request, HttpStatus.serviceUnavailable);
        }
        Object? payload;
        try {
          payload = jsonDecode(utf8.decode(bytes));
        } on FormatException {
          throw const ChatDockProtocolException('invalid_json');
        }
        final command = ChatDockRequest.parse(path, payload);
        await command.execute(runtime);
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
    } on ChatDockProtocolException catch (error) {
      await _safeError(request, error.status, error.code);
    } on FormatException {
      await _safeError(request, HttpStatus.badRequest, 'invalid_request');
    } on TimeoutException {
      await _safeError(request, HttpStatus.requestTimeout, 'request_timeout');
    } on Object {
      await _safeError(request, HttpStatus.badGateway, 'operation_failed');
    }
  }

  Future<void> _safeError(HttpRequest request, int status, String code) async {
    try {
      await _respond(request, status, {'error': code});
    } on Object {
      /* A disconnected browser owns its abandoned response. */
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
}
