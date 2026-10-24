import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../runtime/expression.dart';
import '../../services/showrunner_data_service.dart';
import 'remote_control_session.dart';

import 'satellite/transport.dart';
export 'satellite/transport.dart';
import 'satellite/protocol.dart';
export 'satellite/protocol.dart';
import 'satellite/signaling.dart';
export 'satellite/signaling.dart';
import 'satellite/webrtc.dart';
export 'satellite/webrtc.dart';
import 'satellite/resources.dart';
export 'satellite/resources.dart';
import 'satellite/dashboard.dart';
export 'satellite/dashboard.dart';

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
  RemoteControlSession? _session;
  bool _started = false;
  bool _closed = false;
  bool _disposed = false;
  Future<void>? _disconnecting;
  Future<void>? _starting;
  bool _peerConnected = false;

  SatelliteConnectionState get state => _state;
  RemoteDashboardConfig? get dashboard => _dashboard;
  Object? get lastError => _lastError;
  Map<String, Map<String, dynamic>> get states => Map.unmodifiable(_states);
  List<RemoteResourceSlot> get slots => List.unmodifiable(_slots.values);
  Stream<RuntimeMap> get broadcasts => _broadcasts.stream;

  Future<void> start() => _starting ??= _start();

  Future<void> _start() async {
    if (_started || _closed) return;
    config.validate();
    _started = true;
    final peer = await peerFactory({
      'sdpSemantics': 'unified-plan',
      'iceServers': const [
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:3478'},
      ],
    });
    if (_closed) {
      try {
        await peer.close();
      } finally {
        await peer.dispose();
      }
      return;
    }
    _peer = peer;
    peer.onIceCandidate = (candidate) {
      if (_closed || !identical(_peer, peer)) return;
      unawaited(
        signaling
            .send('satelliteConnectionIceCandidate', {
              ...config.toJson(),
              'side': 'satellite',
              'candidate': candidate.toJson(),
            })
            .catchError((Object _) {}),
      );
    };
    peer.onStateChanged = _handlePeerState;
    peer.onDataChannel = _handleDataChannel;
    final channel = await peer.createDataChannel('controlChannel');
    if (_closed) {
      await channel.close();
      return;
    }
    _control = channel;
    _bindControl(channel);

    final offer = await peer.createOffer();
    if (_closed) return;
    await peer.setLocalDescription(offer);
    if (_closed) return;
    final local = await peer.getLocalDescription() ?? offer;
    if (_closed) return;
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

  Future<dynamic> callRpc(String name, [List<dynamic> args = const []]) {
    final session = _session;
    if (_closed ||
        _state != SatelliteConnectionState.connected ||
        session == null) {
      return Future.error(
        StateError('Remote dashboard control channel is not connected.'),
      );
    }
    return session.call(name, args);
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
    if (_closed) throw StateError('Remote dashboard disconnected.');
    _slots[slotId] = slot.copyWith(resourceId: resourceId);
    notifyListeners();
  }

  Future<void> disconnect() => _disconnecting ??= _disconnect();

  Future<void> _disconnect() async {
    if (_closed) return;
    _closed = true;
    _state = SatelliteConnectionState.disconnected;
    _rejectPendingCalls('Remote dashboard disconnected.');
    try {
      await _starting;
    } on Object {
      /* Startup caller owns the failure. */
    }
    final sessionClosing = _session?.close();
    _session = null;
    final control = _control;
    final peer = _peer;
    _control = null;
    _peer = null;
    try {
      await control?.close();
    } finally {
      try {
        await peer?.close();
      } finally {
        try {
          await peer?.dispose();
        } finally {
          await sessionClosing;
        }
      }
    }
    notifyListeners();
  }

  void _handlePeerState(SatellitePeerState state) {
    if (_closed) return;
    _peerConnected = state == SatellitePeerState.connected;
    if (state == SatellitePeerState.failed ||
        state == SatellitePeerState.disconnected ||
        state == SatellitePeerState.closed) {
      _state = SatelliteConnectionState.disconnected;
      _rejectPendingCalls('Remote dashboard disconnected.');
      unawaited(disconnect().catchError((Object _) {}));
    } else if (_peerConnected &&
        _control?.state == SatelliteChannelState.open) {
      _state = SatelliteConnectionState.connected;
    }
    notifyListeners();
  }

  void _handleDataChannel(SatelliteDataChannel channel) {
    if (_closed || _control != null) {
      unawaited(channel.close());
      return;
    }
    if (channel.label == 'controlChannel') {
      _control = channel;
      _bindControl(channel);
    } else {
      unawaited(channel.close());
    }
  }

  void _bindControl(SatelliteDataChannel channel) {
    _session = RemoteControlSession(
      channel: channel,
      resourceId: config.dashboardId,
      requestPrefix: id,
      onRequest: _handleControlRequest,
      onInvalid: disconnect,
    );
    channel.onStateChanged = (state) {
      if (_closed || !identical(_control, channel)) return;
      if (state == SatelliteChannelState.open && _peerConnected) {
        _state = SatelliteConnectionState.connected;
      } else if (state == SatelliteChannelState.closing ||
          state == SatelliteChannelState.closed) {
        _state = SatelliteConnectionState.disconnected;
        _rejectPendingCalls('Remote dashboard control channel closed.');
        unawaited(disconnect().catchError((Object _) {}));
      }
      notifyListeners();
    };
    if (channel.state == SatelliteChannelState.open && _peerConnected) {
      _state = SatelliteConnectionState.connected;
      notifyListeners();
    }
  }

  Future<Object?> _handleControlRequest(String name, List<dynamic> args) async {
    if (_closed) throw StateError('Remote dashboard disconnected.');
    switch (name) {
      case 'dashboard_setConfig':
        if (args.length != 1) {
          throw const FormatException('Invalid dashboard config request.');
        }
        _applyDashboardConfig(args.single);
        return null;
      case 'dashboard_stateUpdate':
        if (args.length != 3 || args[0] is! String || args[1] is! String) {
          throw const FormatException('Invalid dashboard state request.');
        }
        _applyStateUpdate(args);
        return null;
      case 'dashboard_broadcast':
        if (args.length != 2 || args[1] is! Map) {
          throw const FormatException('Invalid dashboard broadcast.');
        }
        _broadcasts.add(Map<String, dynamic>.from(args[1] as Map));
        return null;
      case 'satellite_resourceRPC':
        if (args.length < 2 || args[0] is! String || args[1] is! String) {
          throw const FormatException('Invalid resource request.');
        }
        final slot = _slots[args[0]];
        final handler = resourceRpc;
        if (slot == null || slot.resourceId == null || handler == null) {
          throw StateError('Remote resource slot is unavailable.');
        }
        return handler(slot, args[1] as String, args.skip(2).toList());
      default:
        throw UnsupportedError('Unsupported remote request.');
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
    _disposed = true;
    unawaited(disconnect().catchError((Object _) {}));
    unawaited(_broadcasts.close());
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  void _rejectPendingCalls(String message) => _session?.rejectPending(message);
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
