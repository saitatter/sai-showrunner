import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../../services/showrunner_data_service.dart';
import '../../../services/http_provider_transports.dart';
import '../../twitch/account_runtime.dart';
import '../../spellcast/cloud_pubsub.dart';
import 'protocol.dart';

/// Owns one bounded provider signaling socket; control RPC uses its own session.
final class SatelliteSignalingController extends ChangeNotifier {
  SatelliteSignalingController({
    required this.dataService,
    this.negotiator = _negotiateSatellite,
    this.socketFactory = _connectSatelliteSocket,
  });
  final ShowRunnerDataService dataService;
  final SatelliteSignalingNegotiator negotiator;
  final SatelliteSignalingSocketFactory socketFactory;
  final _messages = StreamController<SatelliteSignalingMessage>.broadcast();
  CloudPubSubSocket? _socket;
  StreamSubscription<dynamic>? _subscription;
  Future<void> _lifecycle = Future<void>.value();
  int _epoch = 0;
  bool _connected = false, _disposed = false;
  Object? _lastError;
  Future<void>? _closing;
  Stream<SatelliteSignalingMessage> get messages => _messages.stream;
  bool get isConnected => _connected;
  Object? get lastError => _lastError;
  bool _current(int epoch) => !_disposed && epoch == _epoch;
  Future<void> _serialize(Future<void> Function() operation) {
    final work = _lifecycle.then((_) => operation());
    _lifecycle = work.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return work;
  }

  Future<void> start() {
    final epoch = _epoch;
    return _serialize(() => _start(epoch));
  }

  Future<void> _start(int epoch) async {
    if (!_current(epoch) || (_socket != null && _connected)) return;
    try {
      final settings = await loadTwitchChannelSettings(dataService);
      if (!_current(epoch)) return;
      final token = settings['accessToken'];
      if (token is! String || token.trim().isEmpty) {
        throw StateError('Connect the Twitch account before remote signaling.');
      }
      final url = await negotiator(token).timeout(const Duration(seconds: 20));
      if (!_current(epoch)) return;
      final uri = Uri.parse(url);
      if (uri.scheme != 'wss' &&
          !(uri.scheme == 'ws' &&
              {'localhost', '127.0.0.1', '::1'}.contains(uri.host))) {
        throw const FormatException('Unsupported signaling URL.');
      }
      final socket = await _openSocket(uri, epoch);
      if (socket == null) return;
      await _closeSocket();
      if (!_current(epoch)) {
        await socket.close();
        return;
      }
      _socket = socket;
      _connected = true;
      bool owns() => _current(epoch) && identical(_socket, socket);
      _subscription = socket.messages.listen(
        (raw) {
          if (owns() && _connected) _handleMessage(raw);
        },
        onError: (Object _) {
          if (!owns()) return;
          _lastError = StateError('Remote signaling disconnected.');
          _connected = false;
          notifyListeners();
        },
        onDone: () {
          if (!owns()) return;
          _connected = false;
          _socket = null;
          notifyListeners();
        },
      );
      _lastError = null;
      notifyListeners();
    } on Object {
      if (!_current(epoch)) return;
      _lastError = StateError('Remote signaling connection failed.');
      _connected = false;
      notifyListeners();
      throw StateError('Remote signaling connection failed.');
    }
  }

  Future<CloudPubSubSocket?> _openSocket(Uri uri, int epoch) async {
    var abandoned = false;
    final opened = socketFactory(uri).then<CloudPubSubSocket?>((socket) async {
      if (abandoned || !_current(epoch)) {
        await socket.close();
        return null;
      }
      return socket;
    });
    try {
      return await opened.timeout(const Duration(seconds: 20));
    } on Object {
      abandoned = true;
      rethrow;
    }
  }

  Future<void> send(String event, SatelliteJson data) async {
    final socket = _socket;
    if (_disposed || !_connected || socket == null) {
      throw StateError('Remote signaling is not connected.');
    }
    if (!const {
      'satelliteConnectionRequest',
      'satelliteConnectionResponse',
      'satelliteConnectionIceCandidate',
    }.contains(event)) {
      throw const FormatException('Unsupported signaling event.');
    }
    final encoded = jsonEncode({
      'type': 'event',
      'event': 'satellite_$event',
      'dataType': 'json',
      'data': data,
    });
    if (utf8.encode(encoded).length > 1024 * 1024) {
      throw const FormatException('Signaling payload limit exceeded.');
    }
    socket.add(encoded);
  }

  Future<void> stop() {
    _epoch++;
    _connected = false;
    return _serialize(() async {
      await _closeSocket();
      notifyListeners();
    });
  }

  void _handleMessage(dynamic raw) {
    if (_disposed || !_connected) return;
    try {
      if (raw is String &&
          (raw.length > 1024 * 1024 || utf8.encode(raw).length > 1024 * 1024)) {
        return;
      }
      final decoded = raw is String
          ? _decodeJson(raw)
          : raw is Map
          ? Map<String, dynamic>.from(raw)
          : null;
      if (decoded is! Map) return;
      final payload = decoded['data'] is Map
          ? Map<String, dynamic>.from(decoded['data'] as Map)
          : decoded;
      if (payload['plugin'] != 'satellite') return;
      final event = payload['event'];
      if (event is! String ||
          !const {
            'satelliteConnectionRequest',
            'satelliteConnectionResponse',
            'satelliteConnectionIceCandidate',
          }.contains(event)) {
        return;
      }
      final context = payload['context'];
      final data = context is Map
          ? Map<String, dynamic>.from(context)
          : Map<String, dynamic>.from(payload);
      _messages.add(SatelliteSignalingMessage(event: event, data: data));
    } on Object {
      /* Malformed provider frames never reach native sessions. */
    }
  }

  Future<void> _closeSocket() async {
    final subscription = _subscription;
    final socket = _socket;
    _subscription = null;
    _socket = null;
    _connected = false;
    try {
      await subscription?.cancel();
    } finally {
      await socket?.close();
    }
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    unawaited(close().catchError((Object _) {}));
    super.dispose();
  }

  Future<void> close() {
    _disposed = true;
    return _closing ??= _close();
  }

  Future<void> _close() async {
    try {
      await stop();
    } finally {
      await _messages.close();
    }
  }
}

dynamic _decodeJson(String value) {
  try {
    return jsonDecode(value);
  } on FormatException {
    return null;
  }
}

Future<String> _negotiateSatellite(String accessToken) async {
  final response = await JsonHttpTransport(
    baseUrl: 'https://api.showrunner.io',
    accessToken: accessToken,
  ).requestValue('GET', '/pubsub/satellite/negotiate', const {}, null);
  if (response is Map && response['url']?.toString().isNotEmpty == true) {
    return response['url'].toString();
  }
  throw const FormatException(
    'Satellite PubSub negotiation did not return a URL.',
  );
}

Future<CloudPubSubSocket> _connectSatelliteSocket(Uri uri) async =>
    IoCloudPubSubSocket(await WebSocket.connect(uri.toString()));
