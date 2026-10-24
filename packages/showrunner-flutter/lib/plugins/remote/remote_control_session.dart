import 'dart:async';
import 'dart:convert';
import 'remote_protocol.generated.dart';
import 'remote_request_window.dart';
import 'satellite/protocol.dart';
import 'satellite/transport.dart';

/// Owns bounded control-channel RPC independently of signaling and WebRTC peers.
final class RemoteControlSession {
  RemoteControlSession({
    required this.channel,
    required this.resourceId,
    required this.requestPrefix,
    required this.onRequest,
    required this.onInvalid,
    this.requestTimeout = const Duration(seconds: 20),
  }) {
    if (requestTimeout <= Duration.zero) {
      throw ArgumentError('Remote request timeout must be positive.');
    }
    channel.onMessage = (raw) => unawaited(_receive(raw));
  }
  final SatelliteDataChannel channel;
  final String resourceId, requestPrefix;
  final Duration requestTimeout;
  final Future<Object?> Function(String name, List<dynamic> args) onRequest;
  final Future<void> Function() onInvalid;
  final _pending = <String, _PendingRemoteCall>{};
  final _writes = <Future<void>>{};
  final _inbound = RemoteRequestWindow();
  int _sequence = 0;
  bool _closed = false, _invalidating = false;
  Future<void>? _closing;

  Future<Object?> call(String name, List<dynamic> args) {
    if (_closed || channel.state != SatelliteChannelState.open) {
      return Future.error(
        StateError('Remote dashboard control channel is not connected.'),
      );
    }
    if (_pending.length >= 64) {
      return Future.error(StateError('Remote request limit reached.'));
    }
    final id = '$requestPrefix-${_sequence++}';
    final done = Completer<Object?>();
    done.future.ignore();
    final timer = Timer(requestTimeout, () {
      final entry = _pending.remove(id);
      entry?.done.completeError(TimeoutException('Remote request expired.'));
      unawaited(_invalidate());
    });
    _pending[id] = _PendingRemoteCall(done, timer);
    _write({'requestId': id, 'name': name, 'args': args}).catchError((
      Object _,
    ) {
      final entry = _pending.remove(id);
      entry?.timer.cancel();
      entry?.done.completeError(
        StateError('Remote request could not be sent.'),
      );
    });
    return done.future;
  }

  Future<void> _write(Map<String, dynamic> message) {
    final work = _send(message);
    _writes.add(work);
    work.then<void>(
      (_) {
        _writes.remove(work);
      },
      onError: (Object _, StackTrace _) {
        _writes.remove(work);
      },
    );
    return work;
  }

  Future<void> _send(Map<String, dynamic> message) async {
    if (_closed || channel.state != SatelliteChannelState.open) {
      throw StateError('Remote control channel is closed.');
    }
    final encoded = jsonEncode(encodeRemoteWire(message, resourceId));
    if (encoded.length > 1024 * 1024 ||
        utf8.encode(encoded).length > 1024 * 1024) {
      throw StateError('Remote message limit reached.');
    }
    await channel.sendText(encoded).timeout(requestTimeout);
  }

  Future<void> _receive(String raw) async {
    try {
      if (_closed) return;
      if (raw.length > 1024 * 1024 || utf8.encode(raw).length > 1024 * 1024) {
        throw const FormatException();
      }
      final message = decodeRemoteWire(jsonDecode(raw), resourceId);
      final response = message['responseId'];
      if (response is String) {
        final entry = _pending.remove(response);
        if (entry == null) return;
        entry.timer.cancel();
        if (message.containsKey('failed')) {
          entry.done.completeError(StateError('Remote RPC failed.'));
        } else {
          entry.done.complete(message['result']);
        }
        return;
      }
      final id = message['requestId'] as String;
      _inbound.enter(id);
      final work = Future<Object?>.sync(
        () => onRequest(
          message['name'] as String,
          List<dynamic>.from(message['args'] as List),
        ),
      );
      work.then<void>(
        (_) {
          _inbound.leave();
        },
        onError: (Object _, StackTrace _) {
          _inbound.leave();
        },
      );
      try {
        final result = await work.timeout(requestTimeout);
        if (!_closed) await _write({'responseId': id, 'result': result});
      } on Object {
        if (!_closed) await _write({'responseId': id, 'failed': true});
      }
    } on Object {
      await _invalidate();
    }
  }

  Future<void> _invalidate() async {
    if (_closed || _invalidating) return;
    _invalidating = true;
    final closing = close();
    try {
      await onInvalid();
    } on Object {
      /* Owner teardown already attempted its resources. */
    }
    await closing;
  }

  void rejectPending(String message) {
    for (final entry in _pending.values) {
      entry.timer.cancel();
      entry.done.completeError(StateError(message));
    }
    _pending.clear();
  }

  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    _closed = true;
    channel.onMessage = null;
    rejectPending('Remote dashboard disconnected.');
    await Future.wait(
      _writes.toList().map(
        (work) => work.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      ),
    );
  }
}

final class _PendingRemoteCall {
  const _PendingRemoteCall(this.done, this.timer);
  final Completer<Object?> done;
  final Timer timer;
}
