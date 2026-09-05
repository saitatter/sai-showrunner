import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../../runtime/expression.dart';
import '../../services/plugin_event_hub.dart';
import 'actions.dart';

final class ObsWebSocketTransport implements ObsTransport {
  ObsWebSocketTransport({
    required this.host,
    required this.port,
    this.password,
    this.eventHub,
    this.onStateChanged,
  });

  final String host;
  final int port;
  final String? password;
  final DartPluginEventHub? eventHub;
  final void Function(String state, dynamic value)? onStateChanged;
  WebSocket? _socket;
  final _pending = <String, Completer<RuntimeMap>>{};
  int _requestId = 0;

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
      return await completer.future;
    } finally {
      _pending.remove(requestId);
    }
  }

  Future<void> connect() async {
    if (_socket != null) return;
    final socket = await WebSocket.connect('ws://$host:$port');
    _socket = socket;
    final hello = jsonDecode(await socket.first as String) as RuntimeMap;
    final helloData = Map<String, dynamic>.from(hello['d'] as Map);
    final identify = <String, dynamic>{'rpcVersion': 1};
    final authentication = helloData['authentication'];
    if (authentication is Map && password != null) {
      final auth = Map<String, dynamic>.from(authentication);
      identify['authentication'] = _authentication(
        password!,
        auth['salt'] as String,
        auth['challenge'] as String,
      );
    }
    socket.listen(_handleMessage, onDone: _handleClosed, onError: _handleError);
    socket.add(jsonEncode({'op': 1, 'd': identify}));
    onStateChanged?.call('connected', true);
    onStateChanged?.call('connection', 'connected');
  }

  @override
  Future<void> close() async {
    final socket = _socket;
    _socket = null;
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
        eventHub?.emit('obsVendorEvent', {
          'eventType': data['eventType'],
          if (eventData is Map) ...Map<String, dynamic>.from(eventData),
        });
      }
      return;
    }
    if (message['op'] != 7) return;
    final data = Map<String, dynamic>.from(message['d'] as Map);
    final requestId = data['requestId'] as String?;
    final completer = requestId == null ? null : _pending[requestId];
    if (completer == null) return;
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

  void _handleError(Object error) => _failPending(error);

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
