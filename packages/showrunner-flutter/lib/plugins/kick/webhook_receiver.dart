import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../runtime/expression.dart';
import 'contracts.dart';
import 'webhook_signature.dart';

/// Only this dedicated loopback listener should be forwarded by the public
/// HTTPS reverse proxy. It deliberately has no application/admin endpoints.
final class KickWebhookReceiver {
  KickWebhookReceiver({
    required this.broadcasterId,
    required this.verifier,
    required this.onEvent,
    DateTime Function()? now,
    this.replayCapacity = 131072,
  }) : _now = now ?? DateTime.now {
    kickUserId(broadcasterId, 'broadcasterId');
    if (replayCapacity < 2) throw ArgumentError('replayCapacity is too small.');
  }

  final int broadcasterId;
  final KickWebhookSignatureVerifier verifier;
  final void Function(KickWebhookEvent) onEvent;
  final DateTime Function() _now;
  final int replayCapacity;
  final _seen = <String, DateTime>{};
  Map<String, String> _subscriptions = const {};
  HttpServer? _server;
  Future<int>? _starting;
  Future<void>? _closing;
  bool _closed = false;
  int _active = 0;
  DateTime? _prunedAt;

  int? get port => _server?.port;

  void setSubscriptions(Map<String, String> subscriptions) {
    if (_closed) throw StateError('Kick webhook receiver is closed.');
    if (subscriptions.length > 16 ||
        subscriptions.entries.any(
          (entry) =>
              !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(entry.key) ||
              !const {
                'chat.message.sent',
                'moderation.banned',
              }.contains(entry.value),
        )) {
      throw ArgumentError('Unsupported Kick webhook subscriptions.');
    }
    _subscriptions = Map.unmodifiable(subscriptions);
  }

  Future<int> start({int port = 53544}) {
    if (_closed) return Future.error(StateError('Kick receiver is closed.'));
    if (port < 0 || port > 65535) return Future.error(ArgumentError('port'));
    if (_server != null) return Future.value(_server!.port);
    return _starting ??= _bind(port).whenComplete(() => _starting = null);
  }

  Future<int> _bind(int port) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    if (_closed) {
      await server.close(force: true);
      throw StateError('Kick receiver is closed.');
    }
    _server = server;
    server.listen((request) => unawaited(_handle(request)));
    return server.port;
  }

  Future<void> _handle(HttpRequest request) async {
    var admitted = false;
    try {
      if (_closed) {
        return await _respond(request, HttpStatus.serviceUnavailable);
      }
      if (request.uri.path != '/kick/webhook' ||
          request.uri.hasQuery ||
          request.uri.hasFragment) {
        return await _respond(request, HttpStatus.notFound);
      }
      if (request.method != 'POST') {
        return await _respond(request, HttpStatus.methodNotAllowed);
      }
      if (_active >= 8 || verifier.busy || _subscriptions.isEmpty) {
        return await _respond(request, HttpStatus.serviceUnavailable);
      }
      _active++;
      admitted = true;
      final id = _header(request, 'Kick-Event-Message-Id');
      final timestamp = _header(request, 'Kick-Event-Message-Timestamp');
      final signature = _header(request, 'Kick-Event-Signature');
      final subscription = _header(request, 'Kick-Event-Subscription-Id');
      final type = _header(request, 'Kick-Event-Type');
      final version = _header(request, 'Kick-Event-Version');
      if ([
        id,
        timestamp,
        signature,
        subscription,
        type,
        version,
      ].any((value) => value == null)) {
        return await _respond(request, HttpStatus.badRequest);
      }
      if (request.contentLength > 262144) {
        return await _respond(request, HttpStatus.requestEntityTooLarge);
      }
      final bytes = BytesBuilder(copy: false);
      final chunks = StreamIterator(request);
      final deadline = Stopwatch()..start();
      try {
        while (await chunks.moveNext().timeout(
          const Duration(seconds: 10) - deadline.elapsed,
        )) {
          final chunk = chunks.current;
          if (_closed) {
            return await _respond(request, HttpStatus.serviceUnavailable);
          }
          if (bytes.length + chunk.length > 262144) {
            return await _respond(request, HttpStatus.requestEntityTooLarge);
          }
          bytes.add(chunk);
        }
      } finally {
        await chunks.cancel();
      }
      if (verifier.busy) {
        return await _respond(request, HttpStatus.serviceUnavailable);
      }
      final body = bytes.takeBytes();
      final valid = await verifier.verify(
        messageId: id!,
        timestamp: timestamp!,
        signature: signature!,
        body: body,
      );
      if (_closed) {
        return await _respond(request, HttpStatus.serviceUnavailable);
      }
      if (!valid) return await _respond(request, HttpStatus.forbidden);
      // The signature does not cover type/version/subscription headers. Bind
      // them to our configured subscriptions and validate the body separately.
      if (version != '1' || _subscriptions[subscription] != type) {
        return await _respond(request, HttpStatus.noContent);
      }
      final decoded = jsonDecode(utf8.decode(body));
      if (decoded is! Map<String, dynamic>) {
        return await _respond(request, HttpStatus.badRequest);
      }
      final event = KickWebhookEvent.decode(type!, decoded);
      if (event.broadcasterId != broadcasterId) {
        return await _respond(request, HttpStatus.noContent);
      }
      final now = _now();
      if (_prunedAt == null ||
          now.difference(_prunedAt!) >= const Duration(seconds: 30)) {
        _seen.removeWhere((_, expires) => !expires.isAfter(now));
        _prunedAt = now;
      }
      final deliveryKey = 'delivery:$id';
      final eventKey = type == 'chat.message.sent'
          ? 'chat:${event.payload['messageId']}'
          : 'moderation:${sha256.convert(body)}';
      if ((_seen[deliveryKey]?.isAfter(now) ?? false) ||
          (_seen[eventKey]?.isAfter(now) ?? false)) {
        return await _respond(request, HttpStatus.noContent);
      }
      // Never evict a still-live replay key to make room for a new request.
      if (_seen.length + 2 > replayCapacity) {
        return await _respond(request, HttpStatus.serviceUnavailable);
      }
      // Synchronous admission means duplicate concurrent requests cannot both
      // publish. If the event hub is full, leave the event retryable.
      onEvent(event);
      final expires = now.add(KickWebhookSignatureVerifier.replayWindow * 2);
      _seen[deliveryKey] = expires;
      _seen[eventKey] = expires;
      return await _respond(request, HttpStatus.noContent);
    } on FormatException {
      return await _respond(request, HttpStatus.badRequest);
    } on ArgumentError {
      return await _respond(request, HttpStatus.badRequest);
    } catch (_) {
      if (!_closed) {
        return await _respond(request, HttpStatus.serviceUnavailable);
      }
    } finally {
      if (admitted) _active--;
    }
  }

  Future<void> close() {
    _closed = true;
    verifier.close();
    _subscriptions = const {};
    _seen.clear();
    return _closing ??= _close();
  }

  Future<void> _close() async {
    try {
      await _starting;
    } catch (_) {
      // A bind completing after close releases its own server.
    }
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }
}

String? _header(HttpRequest request, String name) {
  final values = request.headers[name];
  if (values == null ||
      values.length != 1 ||
      values.single.isEmpty ||
      values.single.length > 1400) {
    return null;
  }
  return values.single;
}

Future<void> _respond(HttpRequest request, int status) async {
  try {
    request.response.statusCode = status;
    request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    await request.response.close();
  } catch (_) {
    // A disconnected remote client must not create an unhandled async error.
  }
}

final class KickWebhookEvent {
  const KickWebhookEvent._(this.type, this.broadcasterId, this.payload);

  final String type;
  final int broadcasterId;
  final RuntimeMap payload;

  factory KickWebhookEvent.decode(String type, RuntimeMap body) {
    final broadcaster = _object(body['broadcaster']);
    final channel = kickUserId(broadcaster['user_id'], 'broadcasterId');
    if (type == 'chat.message.sent') {
      final sender = _object(body['sender']);
      final userId = kickUserId(sender['user_id'], 'userId');
      final identity = sender['identity'] == null
          ? const <String, dynamic>{}
          : _object(sender['identity']);
      final badges = identity['badges'];
      if (badges != null && (badges is! List || badges.length > 32)) {
        throw const FormatException('Invalid Kick badges.');
      }
      final roles = <String>{
        if (badges is List)
          for (final badge in badges)
            if (badge is Map && badge['type'] is String)
              badge['type'] as String,
      };
      final createdAt = _date(body['created_at']);
      final content = body['content'];
      if (content is! String || content.length > 8192) {
        throw const FormatException('Invalid Kick message.');
      }
      return KickWebhookEvent._(
        'kickChatMessage',
        channel,
        Map.unmodifiable({
          'messageId': kickMessageId(body['message_id']),
          'viewerId': userId.toString(),
          'viewerName': _text(sender['username'], 256),
          'message': content,
          'createdAt': createdAt.toUtc().toIso8601String(),
          'broadcasterId': channel.toString(),
          'isOwner': userId == channel,
          'isModerator': roles.contains('moderator'),
          'isSubscriber': roles.contains('subscriber'),
          'isVip': roles.contains('vip'),
          'isBot': roles.contains('bot'),
          if (_avatar(sender['profile_picture']) case final String avatar)
            'avatarUrl': avatar,
        }),
      );
    }
    if (type != 'moderation.banned') {
      throw const FormatException('Unsupported Kick event.');
    }
    final user = _object(body['banned_user']);
    final metadata = _object(body['metadata']);
    final expiresAt = metadata['expires_at'] == null
        ? null
        : _date(metadata['expires_at']);
    return KickWebhookEvent._(
      expiresAt == null ? 'kickUserBanned' : 'kickUserTimedOut',
      channel,
      Map.unmodifiable({
        'viewerId': kickUserId(user['user_id'], 'userId').toString(),
        'viewerName': _text(user['username'], 256),
        'broadcasterId': channel.toString(),
        'createdAt': _date(metadata['created_at']).toUtc().toIso8601String(),
        if (expiresAt != null) 'expiresAt': expiresAt.toUtc().toIso8601String(),
        // Moderation reasons and unrelated raw identity fields stay private.
      }),
    );
  }
}

RuntimeMap _object(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Invalid Kick event object.');
  }
  return value;
}

String _text(Object? value, int max) {
  if (value is! String || value.isEmpty || value.length > max) {
    throw const FormatException('Invalid Kick event text.');
  }
  return value;
}

DateTime _date(Object? value) {
  final text = _text(value, 64);
  if (!RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(text)) {
    throw const FormatException('Invalid Kick event date.');
  }
  final date = DateTime.tryParse(text);
  if (date == null) throw const FormatException('Invalid Kick event date.');
  return date;
}

String? _avatar(Object? value) {
  if (value is! String || value.length > 2048) return null;
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.userInfo.isNotEmpty ||
      uri.port != 443 ||
      !const {'kick.com', 'files.kick.com'}.contains(uri.host)) {
    return null;
  }
  return uri.toString();
}
