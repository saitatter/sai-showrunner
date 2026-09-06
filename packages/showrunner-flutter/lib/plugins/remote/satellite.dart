import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;

import '../../runtime/expression.dart';
import '../../services/http_provider_transports.dart';
import '../../services/showrunner_data_service.dart';
import '../twitch/account_runtime.dart';
import '../spellcast/cloud_pubsub.dart';

part 'satellite/protocol.dart';
part 'satellite/signaling.dart';
part 'satellite/webrtc.dart';
part 'satellite/resources.dart';
part 'satellite/dashboard.dart';

final class RemoteSatelliteConnection extends ChangeNotifier {
  RemoteSatelliteConnection({
    required this.config,
    required this.signaling,
    this.peerFactory = createFlutterSatellitePeerConnection,
    this.resourceRpc,
    String? id,
  }) : id = id ?? 'remote-${DateTime.now().microsecondsSinceEpoch}';

  final SatelliteConnectionConfig config;
  final SatelliteSignalingController signaling;
  final SatellitePeerConnectionFactory peerFactory;
  final SatelliteResourceRpcHandler? resourceRpc;
  final String id;

  SatelliteConnectionState _state = SatelliteConnectionState.connecting;
  SatellitePeerConnection? _peer;
  SatelliteDataChannel? _control;
  RemoteDashboardConfig? _dashboard;
  Object? _lastError;
  final _states = <String, Map<String, dynamic>>{};
  final _slots = <String, RemoteResourceSlot>{};
  final _broadcasts = StreamController<RuntimeMap>.broadcast();
  final _pendingCalls = <String, Completer<dynamic>>{};
  int _requestNumber = 0;
  bool _started = false;
  bool _closed = false;
  bool _peerConnected = false;

  SatelliteConnectionState get state => _state;
  RemoteDashboardConfig? get dashboard => _dashboard;
  Object? get lastError => _lastError;
  Map<String, Map<String, dynamic>> get states => Map.unmodifiable(_states);
  List<RemoteResourceSlot> get slots => List.unmodifiable(_slots.values);
  Stream<RuntimeMap> get broadcasts => _broadcasts.stream;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    final peer = await peerFactory({
      'sdpSemantics': 'unified-plan',
      'iceServers': const [
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:3478'},
      ],
    });
    if (_closed) {
      await peer.dispose();
      return;
    }
    _peer = peer;
    peer.onIceCandidate = (candidate) {
      unawaited(
        signaling.send('satelliteConnectionIceCandidate', {
          ...config.toJson(),
          'side': 'satellite',
          'candidate': candidate.toJson(),
        }),
      );
    };
    peer.onStateChanged = _handlePeerState;
    peer.onDataChannel = _handleDataChannel;
    _control = await peer.createDataChannel('controlChannel');
    _bindControl(_control!);

    final offer = await peer.createOffer();
    await peer.setLocalDescription(offer);
    final local = await peer.getLocalDescription() ?? offer;
    await signaling.send('satelliteConnectionRequest', {
      ...config.toJson(),
      'sdp': local.toJson(),
    });
  }

  Future<void> applyResponse(Object? value) async {
    final response = SatelliteSessionDescription.fromJson(value);
    final peer = _peer;
    if (peer == null || _closed) return;
    await peer.setRemoteDescription(response);
  }

  Future<void> applyCandidate(Object? value) async {
    final candidate = SatelliteIceCandidate.fromJson(value);
    final peer = _peer;
    if (peer == null || _closed) return;
    await peer.addCandidate(candidate);
  }

  Future<dynamic> callRpc(String name, [List<dynamic> args = const []]) async {
    final channel = _control;
    if (_closed ||
        channel == null ||
        channel.state != SatelliteChannelState.open) {
      throw StateError('Remote dashboard control channel is not connected.');
    }
    final requestId = '$id-${_requestNumber++}';
    final completer = Completer<dynamic>();
    _pendingCalls[requestId] = completer;
    await channel.sendText(
      jsonEncode({'requestId': requestId, 'name': name, 'args': args}),
    );
    try {
      return await completer.future.timeout(const Duration(seconds: 20));
    } finally {
      _pendingCalls.remove(requestId);
    }
  }

  Future<void> acquireState(String plugin, String state) async {
    await callRpc('dashboard_acquireState', [plugin, state]);
  }

  Future<void> releaseState(String plugin, String state) async {
    await callRpc('dashboard_freeState', [plugin, state]);
  }

  Future<dynamic> callWidgetRpc(
    String widgetId,
    String rpcId,
    List<dynamic> args,
  ) => callRpc('dashboard_widgetRPC', [rpcId, widgetId, ...args]);

  Future<void> bindSlot(String slotId, String? resourceId) async {
    final slot = _slots[slotId];
    if (slot == null) throw StateError('Unknown remote resource slot: $slotId');
    await callRpc(
      resourceId == null
          ? 'satellite_resourceUnbind'
          : 'satellite_resourceBind',
      [slotId],
    );
    _slots[slotId] = slot.copyWith(resourceId: resourceId);
    notifyListeners();
  }

  Future<void> disconnect() async {
    if (_closed) return;
    _closed = true;
    _state = SatelliteConnectionState.disconnected;
    for (final completer in _pendingCalls.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('Remote dashboard disconnected.'));
      }
    }
    _pendingCalls.clear();
    await _control?.close();
    await _peer?.close();
    await _peer?.dispose();
    _control = null;
    _peer = null;
    notifyListeners();
  }

  void _handlePeerState(SatellitePeerState state) {
    _peerConnected = state == SatellitePeerState.connected;
    if (state == SatellitePeerState.failed ||
        state == SatellitePeerState.disconnected ||
        state == SatellitePeerState.closed) {
      _state = SatelliteConnectionState.disconnected;
    } else if (_peerConnected &&
        _control?.state == SatelliteChannelState.open) {
      _state = SatelliteConnectionState.connected;
    }
    notifyListeners();
  }

  void _handleDataChannel(SatelliteDataChannel channel) {
    if (channel.label == 'controlChannel') {
      _control = channel;
      _bindControl(channel);
    } else {
      unawaited(channel.close());
    }
  }

  void _bindControl(SatelliteDataChannel channel) {
    channel.onStateChanged = (state) {
      if (state == SatelliteChannelState.open && _peerConnected) {
        _state = SatelliteConnectionState.connected;
      } else if (state == SatelliteChannelState.closed) {
        _state = SatelliteConnectionState.disconnected;
      }
      notifyListeners();
    };
    channel.onMessage = (message) => unawaited(_handleControlMessage(message));
    if (channel.state == SatelliteChannelState.open && _peerConnected) {
      _state = SatelliteConnectionState.connected;
      notifyListeners();
    }
  }

  Future<void> _handleControlMessage(String raw) async {
    final decoded = _decodeJson(raw);
    if (decoded is! Map) return;
    if (decoded['responseId'] is String) {
      final completer = _pendingCalls[decoded['responseId']];
      if (completer == null || completer.isCompleted) return;
      if (decoded.containsKey('failed')) {
        completer.completeError(StateError('Remote RPC failed.'));
      } else {
        completer.complete(decoded['result']);
      }
      return;
    }
    final requestId = decoded['requestId']?.toString();
    final name = decoded['name']?.toString();
    if (requestId == null || name == null) return;
    try {
      dynamic result;
      switch (name) {
        case 'dashboard_setConfig':
          final args = decoded['args'];
          _applyDashboardConfig(
            args is List && args.isNotEmpty ? args.first : null,
          );
          break;
        case 'dashboard_stateUpdate':
          _applyStateUpdate(decoded['args']);
          break;
        case 'dashboard_broadcast':
          final args = decoded['args'] is List
              ? decoded['args'] as List
              : const [];
          if (args.length >= 2 && args[1] is Map) {
            _broadcasts.add(Map<String, dynamic>.from(args[1] as Map));
          }
          break;
        case 'satellite_resourceRPC':
          final args = decoded['args'] is List
              ? decoded['args'] as List
              : const [];
          if (args.length < 2) {
            throw const FormatException('Resource RPC is incomplete.');
          }
          final slot = _slots[args[0]?.toString()];
          if (slot == null) throw StateError('Unknown remote resource slot.');
          final handler = resourceRpc;
          if (handler == null || slot.resourceId == null) {
            throw StateError('Remote resource slot is not bound in Flutter.');
          }
          result = await handler(
            slot,
            args[1].toString(),
            args.skip(2).toList(),
          );
          break;
        default:
          return;
      }
      await _control?.sendText(
        jsonEncode({'responseId': requestId, 'result': result}),
      );
    } on Object catch (error) {
      await _control?.sendText(
        jsonEncode({'responseId': requestId, 'failed': error.toString()}),
      );
    }
  }

  void _applyDashboardConfig(Object? value) {
    final next = RemoteDashboardConfig.fromJson(value);
    final previous = Map<String, RemoteResourceSlot>.from(_slots);
    _slots
      ..clear()
      ..addEntries(
        next.resourceSlots.map(
          (slot) => MapEntry(
            slot.id,
            slot.copyWith(
              resourceId: previous[slot.id]?.resourceType == slot.resourceType
                  ? previous[slot.id]?.resourceId
                  : null,
            ),
          ),
        ),
      );
    _dashboard = next;
    notifyListeners();
  }

  void _applyStateUpdate(Object? value) {
    final args = value is List ? value : const [];
    if (args.length < 3) return;
    final plugin = args[0]?.toString() ?? '';
    final state = args[1]?.toString() ?? '';
    if (plugin.isEmpty || state.isEmpty) return;
    final pluginStates = _states.putIfAbsent(plugin, () => <String, dynamic>{});
    pluginStates[state] = args[2];
    notifyListeners();
  }

  @override
  void dispose() {
    if (!_closed) {
      _closed = true;
      unawaited(_control?.close());
      unawaited(_peer?.close());
      unawaited(_peer?.dispose());
    }
    unawaited(_broadcasts.close());
    super.dispose();
  }
}

final class RemoteSatelliteConnectionManager extends ChangeNotifier {
  RemoteSatelliteConnectionManager({
    required this.dataService,
    SatelliteSignalingController? signaling,
    this.peerFactory = createFlutterSatellitePeerConnection,
    this.resourceRpc,
  }) : signaling =
           signaling ?? SatelliteSignalingController(dataService: dataService) {
    _signalingSubscription = this.signaling.messages.listen(_handleSignal);
  }

  final ShowRunnerDataService dataService;
  final SatelliteSignalingController signaling;
  final SatellitePeerConnectionFactory peerFactory;
  final SatelliteResourceRpcHandler? resourceRpc;
  late final StreamSubscription<SatelliteSignalingMessage>
  _signalingSubscription;
  RemoteSatelliteConnection? _connection;
  Object? _lastError;

  RemoteSatelliteConnection? get connection => _connection;
  Object? get lastError => _lastError;

  Future<RemoteSatelliteConnection> connect(
    SatelliteConnectionConfig config,
  ) async {
    await disconnect();
    try {
      await signaling.start();
      final connection = RemoteSatelliteConnection(
        config: config,
        signaling: signaling,
        peerFactory: peerFactory,
        resourceRpc: resourceRpc,
      );
      _connection = connection;
      connection.addListener(notifyListeners);
      notifyListeners();
      await connection.start();
      return connection;
    } catch (error) {
      _lastError = error;
      await disconnect();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> disconnect() async {
    final connection = _connection;
    _connection = null;
    if (connection != null) {
      connection.removeListener(notifyListeners);
      await connection.disconnect();
      connection.dispose();
    }
    await signaling.stop();
    notifyListeners();
  }

  void _handleSignal(SatelliteSignalingMessage message) {
    final connection = _connection;
    if (connection == null || !connection.config.matches(message.data)) return;
    try {
      if (message.event == 'satelliteConnectionResponse') {
        unawaited(connection.applyResponse(message.data['sdp']));
      } else if (message.event == 'satelliteConnectionIceCandidate' &&
          message.data['side']?.toString() == 'ShowRunner') {
        unawaited(connection.applyCandidate(message.data['candidate']));
      }
    } catch (error) {
      _lastError = error;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    final connection = _connection;
    _connection = null;
    if (connection != null) {
      connection.removeListener(notifyListeners);
      connection.dispose();
    }
    unawaited(_signalingSubscription.cancel());
    signaling.dispose();
    super.dispose();
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
