import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'overlay_protocol.generated.dart';

/// Owns a browser connection and its bounded request lifetime. The service owns
/// domain operations; a disconnected peer never publishes their late results.
final class OverlayPeer {
  OverlayPeer(
    this.socket, {
    required this.overlayId,
    this.maxMessageBytes = 1024 * 1024,
    this.requestTimeout = const Duration(seconds: 20),
    this.maxPendingRequests = 64,
    this.maxInboundRequests = 16,
  }) {
    if (maxMessageBytes <= 0 ||
        maxPendingRequests <= 0 ||
        maxInboundRequests <= 0 ||
        requestTimeout <= Duration.zero) {
      throw ArgumentError('Overlay peer limits must be positive.');
    }
    _subscription = socket.listen(
      (data) => unawaited(_receive(data)),
      onError: (Object _, StackTrace _) => _finish(),
      onDone: _finish,
    );
  }

  final WebSocket socket;
  final String overlayId;
  final int maxMessageBytes, maxPendingRequests, maxInboundRequests;
  final Duration requestTimeout;
  late final StreamSubscription<dynamic> _subscription;
  final _pending = <String, _PendingCall>{};
  final _active = <String>{};
  final _seen = <String>{};
  final acquiredStates = <String>{};
  final _done = Completer<void>();
  Future<void>? _closing;
  Future<void>? _cancelled;
  var _nextRequest = 0;
  var _closed = false;
  bool observingViewerData = false;
  Future<Object?> Function(String, List<dynamic>)? onRequest;
  Future<void> get done => _done.future;
  bool get isClosed => _closed;
  int get pendingRequests => _pending.length;
  int get activeRequests => _active.length;

  Future<Object?> call(String name, List<dynamic> args) {
    if (_closed || socket.readyState != WebSocket.open) {
      return Future.error(StateError('Overlay connection is closed.'));
    }
    if (_pending.length >= maxPendingRequests) {
      return Future.error(StateError('Overlay request limit reached.'));
    }
    final id = 'flutter-overlay-${_nextRequest++}';
    final completer = Completer<Object?>();
    final timer = Timer(requestTimeout, () {
      final pending = _pending.remove(id);
      pending?.completer.completeError(
        TimeoutException('Overlay request expired.'),
      );
    });
    _pending[id] = _PendingCall(completer, timer);
    try {
      _write({'requestId': id, 'name': name, 'args': args});
    } on Object {
      _pending.remove(id);
      timer.cancel();
      completer.completeError(StateError('Overlay request could not be sent.'));
    }
    return completer.future;
  }

  Future<void> close([int code = WebSocketStatus.normalClosure]) =>
      _closing ??= _close(code);

  Future<void> _close(int code) async {
    // Settle callers before waiting for a remote close handshake.
    try {
      final closing = socket.close(code);
      _finish();
      await closing.timeout(requestTimeout);
      await _cancelled;
    } on Object {
      _finish();
      // Socket shutdown must not expose a remote error payload to callers.
    }
  }

  void _write(Map<String, dynamic> message) {
    if (_closed || socket.readyState != WebSocket.open) return;
    final encoded = jsonEncode(encodeOverlayWire(message, overlayId));
    if (encoded.length > maxMessageBytes ||
        utf8.encode(encoded).length > maxMessageBytes) {
      throw StateError('Overlay message limit reached.');
    }
    socket.add(encoded);
  }

  Future<void> _receive(dynamic data) async {
    try {
      if (_closed) return;
      if (data is! String) {
        await close(WebSocketStatus.unsupportedData);
        return;
      }
      if (data.length > maxMessageBytes ||
          utf8.encode(data).length > maxMessageBytes) {
        await close(WebSocketStatus.messageTooBig);
        return;
      }
      final value = decodeOverlayWire(jsonDecode(data), overlayId);
      final response = value['responseId'];
      if (response != null) {
        if (!_validId(response) || value.containsKey('requestId')) {
          throw const FormatException();
        }
        final pending = _pending.remove(response);
        if (pending == null) return; // Expired or previous-generation response.
        pending.timer.cancel();
        if (value.containsKey('failed')) {
          pending.completer.completeError(StateError('Overlay RPC failed.'));
        } else {
          pending.completer.complete(value['result']);
        }
        return;
      }
      final id = value['requestId'], name = value['name'], args = value['args'];
      if (!_validId(id) ||
          !_validId(name) ||
          args is! List ||
          args.length > 32) {
        throw const FormatException();
      }
      if (_active.length >= maxInboundRequests || !_seen.add(id as String)) {
        await close(WebSocketStatus.policyViolation);
        return;
      }
      if (_seen.length > 256) _seen.remove(_seen.first);
      _active.add(id);
      // Keep the admission slot until domain work actually ends, even after
      // the response deadline. Timeouts must not admit unlimited hung reads.
      final work = Future<Object?>.sync(
        () => onRequest?.call(name as String, List<dynamic>.from(args)),
      );
      work.then<void>(
        (_) {
          _active.remove(id);
        },
        onError: (Object _, StackTrace _) {
          _active.remove(id);
        },
      );
      try {
        final result = await work.timeout(requestTimeout);
        _write({'responseId': id, 'result': result});
      } on Object {
        _write({'responseId': id, 'failed': true});
      }
    } on Object {
      await close(WebSocketStatus.invalidFramePayloadData);
    }
  }

  static bool _validId(Object? value) =>
      value is String && value.isNotEmpty && value.length <= 128;

  void _finish() {
    if (_closed) return;
    _closed = true;
    acquiredStates.clear();
    observingViewerData = false;
    for (final pending in _pending.values) {
      pending.timer.cancel();
      pending.completer.completeError(StateError('Overlay connection closed.'));
    }
    _pending.clear();
    if (!_done.isCompleted) _done.complete();
    _cancelled = _subscription.cancel();
    _cancelled!.ignore();
  }
}

final class _PendingCall {
  const _PendingCall(this.completer, this.timer);
  final Completer<Object?> completer;
  final Timer timer;
}
