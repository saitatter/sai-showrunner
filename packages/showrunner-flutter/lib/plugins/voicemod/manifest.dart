import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../schema/data_input.dart';
import '../../runtime/expression.dart';
import '../registry/plugin_contract.dart';

abstract interface class VoiceModTransport {
  Future<List<RuntimeMap>> getVoices();

  Future<RuntimeMap> selectVoice(String voiceId);

  Future<void> close();
}

final class CallbackVoiceModTransport implements VoiceModTransport {
  const CallbackVoiceModTransport({
    required this.getVoicesCallback,
    required this.selectVoiceCallback,
    this.closeCallback,
  });

  final Future<List<RuntimeMap>> Function() getVoicesCallback;
  final Future<RuntimeMap> Function(String voiceId) selectVoiceCallback;
  final Future<void> Function()? closeCallback;

  @override
  Future<List<RuntimeMap>> getVoices() => getVoicesCallback();

  @override
  Future<RuntimeMap> selectVoice(String voiceId) =>
      selectVoiceCallback(voiceId);

  @override
  Future<void> close() async => closeCallback?.call();
}

final class VoiceModWebSocketTransport implements VoiceModTransport {
  VoiceModWebSocketTransport({this.host = '127.0.0.1', this.port = 59129});

  final String host;
  final int port;
  WebSocket? _socket;
  StreamSubscription<dynamic>? _subscription;
  Future<void>? _connecting;
  final Map<String, Completer<RuntimeMap>> _pending = {};
  int _sequence = 0;
  bool _closed = false;

  @override
  Future<List<RuntimeMap>> getVoices() async {
    final response = await _call('getVoices');
    final voices = response['voices'];
    if (voices is! List) return const [];
    return voices
        .whereType<Map>()
        .map((voice) => Map<String, dynamic>.from(voice))
        .toList();
  }

  @override
  Future<RuntimeMap> selectVoice(String voiceId) async {
    await _ensureConnected();
    final socket = _socket;
    if (socket == null) {
      throw StateError('VoiceMod WebSocket is not connected.');
    }
    socket.add(
      jsonEncode({
        'id': _nextId(),
        'action': 'selectVoice',
        'payload': {'voiceID': voiceId},
      }),
    );
    return {'selected': true, 'voiceID': voiceId};
  }

  @override
  Future<void> close() async {
    _closed = true;
    final socket = _socket;
    _socket = null;
    final subscription = _subscription;
    _subscription = null;
    _failPending(StateError('VoiceMod WebSocket closed.'));
    await subscription?.cancel();
    await socket?.close();
  }

  Future<void> _ensureConnected() async {
    if (_socket != null) {
      return;
    }
    if (_closed) {
      throw StateError('VoiceMod transport is closed.');
    }
    final current = _connecting;
    if (current != null) {
      await current;
      return;
    }
    final future = _connect();
    _connecting = future;
    try {
      await future;
    } finally {
      if (identical(_connecting, future)) {
        _connecting = null;
      }
    }
  }

  Future<void> _connect() async {
    final socket = await WebSocket.connect('ws://$host:$port/v1/');
    if (_closed) {
      await socket.close();
      throw StateError('VoiceMod transport is closed.');
    }
    _socket = socket;
    _subscription = socket.listen(
      _handleMessage,
      onError: (Object error, StackTrace stack) {
        _onDisconnected(socket, error);
      },
      onDone: () =>
          _onDisconnected(socket, StateError('VoiceMod WebSocket closed.')),
      cancelOnError: false,
    );
    try {
      await _callConnected('registerClient', {'clientKey': 'ShowRunner'});
    } catch (_) {
      await _disconnect(socket);
      rethrow;
    }
  }

  Future<RuntimeMap> _call(
    String action, [
    RuntimeMap payload = const {},
  ]) async {
    await _ensureConnected();
    return _callConnected(action, payload);
  }

  Future<RuntimeMap> _callConnected(String action, RuntimeMap payload) async {
    final socket = _socket;
    if (socket == null) {
      throw StateError('VoiceMod WebSocket is not connected.');
    }
    final id = _nextId();
    final completer = Completer<RuntimeMap>();
    _pending[id] = completer;
    try {
      socket.add(jsonEncode({'id': id, 'action': action, 'payload': payload}));
    } on Object catch (error, stack) {
      _pending.remove(id);
      completer.completeError(error, stack);
    }
    return completer.future;
  }

  void _handleMessage(dynamic data) {
    if (data is List<int>) return;
    try {
      final decoded = jsonDecode(data.toString());
      if (decoded is! Map) return;
      final id = decoded['id']?.toString();
      if (id == null) return;
      final completer = _pending.remove(id);
      if (completer == null || completer.isCompleted) return;
      final error = decoded['error'];
      if (error != null && error.toString().isNotEmpty) {
        completer.completeError(StateError('VoiceMod RPC failed: $error'));
        return;
      }
      final payload = decoded['payload'];
      completer.complete(
        payload is Map
            ? Map<String, dynamic>.from(payload)
            : <String, dynamic>{},
      );
    } on Object catch (error, stack) {
      _failPending(error, stack);
    }
  }

  void _onDisconnected(WebSocket socket, Object error) {
    if (identical(_socket, socket)) {
      _socket = null;
      _subscription = null;
    }
    _failPending(error);
  }

  Future<void> _disconnect(WebSocket socket) async {
    if (identical(_socket, socket)) {
      _socket = null;
      final subscription = _subscription;
      _subscription = null;
      await subscription?.cancel();
    }
    await socket.close();
    _failPending(StateError('VoiceMod WebSocket disconnected.'));
  }

  void _failPending(Object error, [StackTrace? stack]) {
    final pending = _pending.values.toList();
    _pending.clear();
    for (final completer in pending) {
      if (!completer.isCompleted) {
        completer.completeError(error, stack ?? StackTrace.current);
      }
    }
  }

  String _nextId() =>
      'showrunner-${DateTime.now().microsecondsSinceEpoch}-${_sequence++}';
}

const _selectVoiceSchema = DartDataInputSchema(
  label: 'VoiceMod voice',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'Voice ID',
      key: 'voice',
      kind: DartDataInputKind.text,
      required: true,
      defaultValue: 'nofx',
    ),
  ],
);

DartPluginManifest createVoiceModPlugin(VoiceModTransport transport) =>
    DartPluginManifest(
      id: 'voicemod',
      name: 'Voicemod',
      settings: const [
        DartSettingDefinition(
          id: 'host',
          displayName: 'VoiceMod Hostname',
          defaultValue: '127.0.0.1',
        ),
        DartSettingDefinition(
          id: 'port',
          displayName: 'VoiceMod Port',
          defaultValue: 59129,
        ),
      ],
      states: const [
        DartPluginStateDefinition(
          id: 'connection',
          displayName: 'Connection',
          initialValue: 'lazy',
        ),
      ],
      actions: [
        DartActionDefinition(
          pluginId: 'voicemod',
          actionId: 'getVoices',
          displayName: 'List Voices',
          invoke: (config, context) => transport.getVoices(),
        ),
        DartActionDefinition(
          pluginId: 'voicemod',
          actionId: 'selectVoice',
          displayName: 'Change Voice',
          configSchema: _selectVoiceSchema,
          invoke: (config, context) => _selectVoice(transport, config),
        ),
      ],
      dispose: transport.close,
    );

Future<Object?> _selectVoice(
  VoiceModTransport transport,
  RuntimeMap config,
) async {
  final voice = config['voice']?.toString().trim() ?? '';
  if (voice.isEmpty) return {'selected': false, 'reason': 'Voice is empty'};
  final response = await transport.selectVoice(voice);
  return {'selected': true, 'voice': voice, ...response};
}
