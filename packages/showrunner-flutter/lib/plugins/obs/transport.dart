import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../../runtime/expression.dart';
import '../../services/plugin_event_hub.dart';
import 'actions.dart';

final class ObsWebSocketTransport implements ObsTransport, ObsEventTransport {
  ObsWebSocketTransport({
    required this.host,
    required this.port,
    this.password,
    this.eventHub,
    this.onStateChanged,
    this.handshakeTimeout = const Duration(seconds: 10),
    this.requestTimeout = const Duration(seconds: 20),
  });

  final String host;
  final int port;
  final String? password;
  final DartPluginEventHub? eventHub;
  final void Function(String state, dynamic value)? onStateChanged;
  final Duration handshakeTimeout;
  final Duration requestTimeout;
  WebSocket? _socket;
  Future<void>? _connecting;
  Completer<void>? _identified;
  int _connectionGeneration = 0;
  final _pending = <String, Completer<RuntimeMap>>{};
  int _requestId = 0;
  final _events = StreamController<RuntimeMap>.broadcast();

  @override
  Stream<RuntimeMap> get events => _events.stream;

  @override
  Future<RuntimeMap> call(String request, RuntimeMap data) async {
    await connect();
    final socket = _socket;
    if (socket == null) throw StateError('OBS WebSocket is not connected.');
    final requestId = 'showrunner-${_requestId++}';
    final completer = Completer<RuntimeMap>();
    _pending[requestId] = completer;
    socket.add(
      jsonEncode({
        'op': 6,
        'd': {
          'requestType': request,
          'requestId': requestId,
          'requestData': data,
        },
      }),
    );
    try {
      return await completer.future.timeout(
        requestTimeout,
        onTimeout: () {
          throw TimeoutException(
            'OBS request "$request" timed out.',
            requestTimeout,
          );
        },
      );
    } finally {
      _pending.remove(requestId);
    }
  }

  Future<void> connect() {
    final pending = _connecting;
    if (pending != null) return pending;
    if (_socket != null) return Future.value();
    return _connecting = _open().whenComplete(() => _connecting = null);
  }

  Future<void> _open() async {
    final generation = _connectionGeneration;
    final socket = await WebSocket.connect(
      'ws://$host:$port',
    ).timeout(handshakeTimeout);
    if (generation != _connectionGeneration) {
      await socket.close();
      throw StateError('OBS connection was cancelled.');
    }
    _socket = socket;
    final identified = _identified = Completer<void>();
    // A WebSocket stream is single-subscription. Consume Hello, Identified,
    // events and responses through the same listener for its entire lifetime.
    socket.listen(
      (raw) {
        try {
          final message = jsonDecode(raw as String) as Map;
          if (message['op'] == 0) {
            final data = Map<String, dynamic>.from(message['d'] as Map);
            final identify = <String, dynamic>{'rpcVersion': 1};
            final authentication = data['authentication'];
            if (authentication is Map) {
              if (password == null || password!.isEmpty) {
                throw StateError('OBS requires a WebSocket password.');
              }
              identify['authentication'] = _authentication(
                password!,
                authentication['salt'] as String,
                authentication['challenge'] as String,
              );
            }
            socket.add(jsonEncode({'op': 1, 'd': identify}));
          } else if (message['op'] == 2) {
            if (!identified.isCompleted) identified.complete();
          } else {
            _handleMessage(raw);
          }
        } on Object catch (error) {
          if (!identified.isCompleted) identified.completeError(error);
          _failPending(error);
        }
      },
      onDone: () {
        if (!identified.isCompleted) {
          identified.completeError(
            StateError('OBS closed the connection during identification.'),
          );
        }
        if (identical(_socket, socket)) _handleClosed();
      },
      onError: (Object error) {
        if (!identified.isCompleted) identified.completeError(error);
        if (identical(_socket, socket)) {
          _handleClosed();
          unawaited(socket.close());
        }
      },
    );
    try {
      await identified.future.timeout(handshakeTimeout);
      if (generation != _connectionGeneration || !identical(_socket, socket)) {
        throw StateError('OBS connection was cancelled.');
      }
      onStateChanged?.call('connected', true);
      onStateChanged?.call('connection', 'connected');
    } on Object {
      if (identical(_socket, socket)) _socket = null;
      await socket.close();
      rethrow;
    }
  }

  @override
  Future<void> close() async {
    _connectionGeneration++;
    final socket = _socket;
    _socket = null;
    final identified = _identified;
    if (identified != null && !identified.isCompleted) {
      identified.completeError(StateError('OBS WebSocket closed.'));
    }
    await socket?.close();
    _failPending(StateError('OBS WebSocket closed.'));
    onStateChanged?.call('connected', false);
    onStateChanged?.call('connection', 'disconnected');
  }

  void _handleMessage(dynamic raw) {
    if (raw is! String) return;
    final message = jsonDecode(raw) as RuntimeMap;
    if (message['op'] == 5) {
      final data = message['d'];
      if (data is Map) {
        final eventData = data['eventData'];
        if (eventData is Map) {
          final values = Map<String, dynamic>.from(eventData);
          switch (data['eventType']?.toString()) {
            case 'CurrentProgramSceneChanged':
              onStateChanged?.call('scene', values['sceneName']);
            case 'StreamStateChanged':
              onStateChanged?.call('streaming', values['outputActive'] == true);
            case 'RecordStateChanged':
              onStateChanged?.call('recording', values['outputActive'] == true);
          }
        }
        final event = <String, dynamic>{
          'eventType': data['eventType'],
          if (eventData is Map) ...Map<String, dynamic>.from(eventData),
        };
        _events.add(event);
        eventHub?.emit('obsVendorEvent', event);
      }
      return;
    }
    if (message['op'] != 7) return;
    final data = Map<String, dynamic>.from(message['d'] as Map);
    final requestId = data['requestId'] as String?;
    final completer = requestId == null ? null : _pending[requestId];
    if (completer == null || completer.isCompleted) return;
    final status = Map<String, dynamic>.from(data['requestStatus'] as Map);
    if (status['result'] == true) {
      final response = data['responseData'];
      completer.complete(
        response is Map ? Map<String, dynamic>.from(response) : {},
      );
    } else {
      completer.completeError(
        StateError('${status['code']}: ${status['comment']}'),
      );
    }
  }

  void _handleClosed() {
    _socket = null;
    _failPending(StateError('OBS WebSocket connection closed.'));
    onStateChanged?.call('connected', false);
    onStateChanged?.call('connection', 'disconnected');
  }

  void _failPending(Object error) {
    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.completeError(error);
    }
    _pending.clear();
  }
}

String _authentication(String password, String salt, String challenge) {
  final secret = base64Encode(
    sha256.convert(utf8.encode(password + salt)).bytes,
  );
  return base64Encode(sha256.convert(utf8.encode(secret + challenge)).bytes);
}
