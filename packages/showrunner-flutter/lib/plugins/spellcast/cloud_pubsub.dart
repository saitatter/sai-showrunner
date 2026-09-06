import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../schema/automation.dart';
import '../../schema/resource.dart';
import '../../services/http_provider_transports.dart';
import '../../services/plugin_event_hub.dart';
import '../../services/showrunner_data_service.dart';
import '../twitch/account_runtime.dart';

typedef CloudPubSubNegotiator = Future<String> Function(String accessToken);
typedef CloudPubSubSocketFactory = Future<CloudPubSubSocket> Function(Uri uri);

List<String> resolveActiveSpellcastIds(
  Iterable<JsonMap> activeProfileTriggers,
  Iterable<ResourceData> spells,
) {
  final spellsByLocalId = {for (final spell in spells) spell.id: spell};
  final remoteIds = <String>{};
  for (final trigger in activeProfileTriggers) {
    if (trigger['plugin'] != 'spellcast' || trigger['trigger'] != 'spellHook') {
      continue;
    }
    final config = trigger['config'];
    final localId = config is Map ? config['spell']?.toString() ?? '' : '';
    final remoteId = spellsByLocalId[localId]?.config['spellId']?.toString();
    if (remoteId?.isNotEmpty == true) remoteIds.add(remoteId!);
  }
  return remoteIds.toList();
}

abstract interface class CloudPubSubSocket {
  Stream<dynamic> get messages;

  void add(String message);

  Future<void> close();
}

final class IoCloudPubSubSocket implements CloudPubSubSocket {
  IoCloudPubSubSocket(this._socket);

  final WebSocket _socket;

  @override
  Stream<dynamic> get messages => _socket;

  @override
  void add(String message) => _socket.add(message);

  @override
  Future<void> close() => _socket.close();
}

final class SpellcastCloudPubSubController extends ChangeNotifier {
  SpellcastCloudPubSubController({
    required this.dataService,
    required this.eventHub,
    this.negotiator = _negotiate,
    this.socketFactory = _connectSocket,
  });

  final ShowRunnerDataService dataService;
  final DartPluginEventHub eventHub;
  final CloudPubSubNegotiator negotiator;
  final CloudPubSubSocketFactory socketFactory;

  CloudPubSubSocket? _socket;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  List<String> _activeSpellIds = const [];
  Object? _lastError;
  bool _shouldRun = false;
  bool _connecting = false;
  bool _connected = false;

  bool get shouldRun => _shouldRun;
  bool get isConnecting => _connecting;
  bool get isConnected => _connected;
  Object? get lastError => _lastError;
  List<String> get activeSpellIds => List.unmodifiable(_activeSpellIds);

  Future<void> start({Iterable<String> activeSpellIds = const []}) async {
    _shouldRun = true;
    _activeSpellIds = _normalizeIds(activeSpellIds);
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    notifyListeners();
    await _connect();
  }

  Future<void> stop() async {
    _shouldRun = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _sendActiveSpellIds(const []);
    await _closeSocket();
    _connected = false;
    _connecting = false;
    notifyListeners();
  }

  Future<void> setActiveSpellIds(Iterable<String> spellIds) async {
    _activeSpellIds = _normalizeIds(spellIds);
    await _sendActiveSpellIds(_activeSpellIds);
    notifyListeners();
  }

  Future<void> _connect() async {
    if (!_shouldRun || _connecting || _connected) return;
    _connecting = true;
    _lastError = null;
    notifyListeners();
    try {
      final settings = await loadTwitchChannelSettings(dataService);
      final token = settings['accessToken']?.toString().trim() ?? '';
      if (token.isEmpty) {
        throw StateError(
          'Twitch access token is required for Spellcast Cloud PubSub.',
        );
      }
      final url = await negotiator(token);
      final socket = await socketFactory(Uri.parse(url));
      if (!_shouldRun) {
        await socket.close();
        return;
      }
      await _closeSocket();
      _socket = socket;
      _subscription = socket.messages.listen(
        _handleMessage,
        onError: _handleSocketError,
        onDone: _handleSocketClosed,
        cancelOnError: false,
      );
      _connected = true;
      await _sendActiveSpellIds(_activeSpellIds);
    } catch (error) {
      _lastError = error;
      _connected = false;
      if (_shouldRun) _scheduleReconnect();
    } finally {
      _connecting = false;
      notifyListeners();
    }
  }

  Future<void> _sendActiveSpellIds(Iterable<String> spellIds) async {
    final socket = _socket;
    if (!_connected || socket == null) return;
    try {
      socket.add(
        jsonEncode({
          'type': 'event',
          'event': 'spellcast_setActiveSpells',
          'dataType': 'json',
          'data': {'spells': _normalizeIds(spellIds)},
        }),
      );
    } catch (error) {
      _lastError = error;
    }
  }

  void _handleMessage(dynamic raw) {
    final decoded = raw is String
        ? _decodeJson(raw)
        : raw is Map
        ? Map<String, dynamic>.from(raw)
        : null;
    if (decoded == null) return;
    final payload = decoded['data'] is Map
        ? Map<String, dynamic>.from(decoded['data'] as Map)
        : decoded;
    final plugin = payload['plugin']?.toString();
    final event = payload['event']?.toString();
    final context = payload['context'];
    if (plugin != 'spellcast' || event == null) return;

    if (event == 'reinit') {
      unawaited(_sendActiveSpellIds(_activeSpellIds));
      return;
    }
    if (event != 'spellHook' || context is! Map) return;
    final spellContext = Map<String, dynamic>.from(context);
    final spellId =
        spellContext['buttonId']?.toString() ??
        spellContext['spellId']?.toString();
    eventHub.emit('spellcast', {
      ...spellContext,
      if (spellId != null && spellId.isNotEmpty) ...{
        'spell': spellId,
        'spellId': spellId,
      },
    });
  }

  void _handleSocketError(Object error, [StackTrace? stackTrace]) {
    _lastError = error;
    _connected = false;
    if (_shouldRun) _scheduleReconnect();
    notifyListeners();
  }

  void _handleSocketClosed() {
    _subscription = null;
    _socket = null;
    _connected = false;
    if (_shouldRun) _scheduleReconnect();
    notifyListeners();
  }

  void _scheduleReconnect() {
    if (_reconnectTimer != null || !_shouldRun) return;
    _reconnectTimer = Timer(const Duration(seconds: 2), () {
      _reconnectTimer = null;
      unawaited(_connect());
    });
  }

  Future<void> _closeSocket() async {
    await _subscription?.cancel();
    _subscription = null;
    final socket = _socket;
    _socket = null;
    await socket?.close();
  }

  static List<String> _normalizeIds(Iterable<String> values) => values
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toSet()
      .toList();
}

dynamic _decodeJson(String value) {
  try {
    return jsonDecode(value);
  } on FormatException {
    return null;
  }
}

Future<String> _negotiate(String accessToken) async {
  final response = await JsonHttpTransport(
    baseUrl: 'https://api.showrunner.io',
    accessToken: accessToken,
  ).requestValue('GET', '/pubsub/negotiate', const {}, null);
  if (response is Map && response['url']?.toString().isNotEmpty == true) {
    return response['url'].toString();
  }
  throw const FormatException('Cloud PubSub negotiation did not return a URL.');
}

Future<CloudPubSubSocket> _connectSocket(Uri uri) async =>
    IoCloudPubSubSocket(await WebSocket.connect(uri.toString()));
