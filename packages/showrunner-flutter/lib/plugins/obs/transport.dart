import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../../runtime/expression.dart';
import 'actions.dart';

final class ObsWebSocketTransport implements ObsTransport {
  ObsWebSocketTransport({
    required this.host,
    required this.port,
    this.password,
  });

  final String host;
  final int port;
  final String? password;
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
  }

  Future<void> close() async {
    final socket = _socket;
    _socket = null;
    await socket?.close();
    _failPending(StateError('OBS WebSocket closed.'));
  }

  void _handleMessage(dynamic raw) {
    if (raw is! String) return;
    final message = jsonDecode(raw) as RuntimeMap;
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
