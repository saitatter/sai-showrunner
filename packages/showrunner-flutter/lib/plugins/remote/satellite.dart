import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;

import '../../runtime/expression.dart';
import '../../services/http_provider_transports.dart';
import '../../services/showrunner_data_service.dart';
import '../spellcast/cloud_pubsub.dart';

typedef SatelliteJson = Map<String, dynamic>;

enum SatelliteConnectionState { connecting, connected, disconnected }

enum SatellitePeerState {
  newState,
  connecting,
  connected,
  disconnected,
  failed,
  closed,
}

enum SatelliteChannelState { connecting, open, closing, closed }

final class SatelliteConnectionConfig {
  const SatelliteConnectionConfig({
    required this.satelliteService,
    required this.satelliteId,
    required this.showRunnerService,
    required this.showRunnerId,
    required this.dashboardId,
  });

  final String satelliteService;
  final String satelliteId;
  final String showRunnerService;
  final String showRunnerId;
  final String dashboardId;

  SatelliteJson toJson() => {
    'satelliteService': satelliteService,
    'satelliteId': satelliteId,
    'ShowRunnerService': showRunnerService,
    'ShowRunnerId': showRunnerId,
    'dashId': dashboardId,
  };

  bool matches(Object? value) {
    if (value is! Map) return false;
    return value['satelliteService']?.toString() == satelliteService &&
        value['satelliteId']?.toString() == satelliteId &&
        value['ShowRunnerService']?.toString() == showRunnerService &&
        value['ShowRunnerId']?.toString() == showRunnerId &&
        value['dashId']?.toString() == dashboardId;
  }
}

final class SatelliteSessionDescription {
  const SatelliteSessionDescription({required this.sdp, required this.type});

  final String sdp;
  final String type;

  SatelliteJson toJson() => {'sdp': sdp, 'type': type};

  factory SatelliteSessionDescription.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('Satellite SDP must be an object.');
    }
    final sdp = value['sdp']?.toString() ?? '';
    final type = value['type']?.toString() ?? '';
    if (sdp.isEmpty || type.isEmpty) {
      throw const FormatException('Satellite SDP is incomplete.');
    }
    return SatelliteSessionDescription(sdp: sdp, type: type);
  }
}

final class SatelliteIceCandidate {
  const SatelliteIceCandidate({
    required this.candidate,
    this.sdpMid,
    this.sdpMLineIndex,
  });

  final String candidate;
  final String? sdpMid;
  final int? sdpMLineIndex;

  SatelliteJson toJson() => {
    'candidate': candidate,
    if (sdpMid != null) 'sdpMid': sdpMid,
    if (sdpMLineIndex != null) 'sdpMLineIndex': sdpMLineIndex,
  };

  factory SatelliteIceCandidate.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('Satellite ICE candidate must be an object.');
    }
    final candidate = value['candidate']?.toString() ?? '';
    if (candidate.isEmpty) {
      throw const FormatException('Satellite ICE candidate is empty.');
    }
    return SatelliteIceCandidate(
      candidate: candidate,
      sdpMid: value['sdpMid']?.toString(),
      sdpMLineIndex: (value['sdpMLineIndex'] as num?)?.toInt(),
    );
  }
}

final class SatelliteSignalingMessage {
  const SatelliteSignalingMessage({required this.event, required this.data});

  final String event;
  final SatelliteJson data;
}

typedef SatelliteSignalingNegotiator =
    Future<String> Function(String accessToken);
typedef SatelliteSignalingSocketFactory =
    Future<CloudPubSubSocket> Function(Uri uri);

/// Raw Azure Web PubSub signaling used by the legacy satellite.
///
/// The cloud endpoint already authenticates the connection with the Twitch
/// token. Only the three satellite signaling events are surfaced to the
/// connection manager; unrelated PubSub traffic is ignored.
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
  bool _connected = false;
  Object? _lastError;

  Stream<SatelliteSignalingMessage> get messages => _messages.stream;
  bool get isConnected => _connected;
  Object? get lastError => _lastError;

  Future<void> start() async {
    if (_socket != null && _connected) return;
    final settings = await dataService.loadPluginSettings('twitch');
    final token = settings['accessToken']?.toString().trim() ?? '';
    if (token.isEmpty) {
      throw StateError(
        'Twitch access token is required for remote dashboard connections.',
      );
    }

    final url = await negotiator(token);
    final socket = await socketFactory(Uri.parse(url));
    await _closeSocket();
    _socket = socket;
    _subscription = socket.messages.listen(
      _handleMessage,
      onError: (Object error) {
        _lastError = error;
        _connected = false;
        notifyListeners();
      },
      onDone: () {
        _connected = false;
        _socket = null;
        notifyListeners();
      },
      cancelOnError: false,
    );
    _connected = true;
    _lastError = null;
    notifyListeners();
  }

  Future<void> send(String event, SatelliteJson data) async {
    final socket = _socket;
    if (!_connected || socket == null) {
      throw StateError('Remote dashboard signaling is not connected.');
    }
    socket.add(
      jsonEncode({
        'type': 'event',
        'event': 'satellite_$event',
        'dataType': 'json',
        'data': data,
      }),
    );
  }

  Future<void> stop() async {
    await _closeSocket();
    _connected = false;
    notifyListeners();
  }

  void _handleMessage(dynamic raw) {
    final decoded = raw is String
        ? _decodeJson(raw)
        : raw is Map
        ? Map<String, dynamic>.from(raw)
        : null;
    if (decoded is! Map) return;
    final payload = decoded['data'] is Map
        ? Map<String, dynamic>.from(decoded['data'] as Map)
        : decoded;
    if (payload['plugin']?.toString() != 'satellite') return;
    final event = payload['event']?.toString() ?? '';
    if (event != 'satelliteConnectionResponse' &&
        event != 'satelliteConnectionIceCandidate') {
      return;
    }
    final context = payload['context'];
    final data = context is Map
        ? Map<String, dynamic>.from(context)
        : Map<String, dynamic>.from(payload);
    _messages.add(SatelliteSignalingMessage(event: event, data: data));
  }

  Future<void> _closeSocket() async {
    await _subscription?.cancel();
    _subscription = null;
    final socket = _socket;
    _socket = null;
    await socket?.close();
  }

  @override
  void dispose() {
    _connected = false;
    unawaited(_closeSocket());
    unawaited(_messages.close());
    super.dispose();
  }
}

abstract interface class SatelliteDataChannel {
  String get label;
  SatelliteChannelState get state;
  set onStateChanged(void Function(SatelliteChannelState state)? listener);
  set onMessage(void Function(String message)? listener);
  Future<void> sendText(String message);
  Future<void> close();
}

abstract interface class SatellitePeerConnection {
  set onIceCandidate(void Function(SatelliteIceCandidate candidate)? listener);
  set onDataChannel(void Function(SatelliteDataChannel channel)? listener);
  set onStateChanged(void Function(SatellitePeerState state)? listener);
  Future<SatelliteDataChannel> createDataChannel(String label);
  Future<SatelliteSessionDescription> createOffer();
  Future<void> setLocalDescription(SatelliteSessionDescription description);
  Future<SatelliteSessionDescription?> getLocalDescription();
  Future<void> setRemoteDescription(SatelliteSessionDescription description);
  Future<void> addCandidate(SatelliteIceCandidate candidate);
  Future<void> close();
  Future<void> dispose();
}

typedef SatellitePeerConnectionFactory =
    Future<SatellitePeerConnection> Function(
      Map<String, dynamic> configuration,
    );

typedef SatelliteResourceRpcHandler =
    Future<Object?> Function(
      RemoteResourceSlot slot,
      String method,
      List<dynamic> args,
    );

final class FlutterSatellitePeerConnection implements SatellitePeerConnection {
  FlutterSatellitePeerConnection(this._peer);

  final rtc.RTCPeerConnection _peer;

  @override
  set onIceCandidate(void Function(SatelliteIceCandidate candidate)? listener) {
    _peer.onIceCandidate = (candidate) {
      final value = candidate.candidate;
      if (listener == null || value == null || value.isEmpty) return;
      listener(
        SatelliteIceCandidate(
          candidate: value,
          sdpMid: candidate.sdpMid,
          sdpMLineIndex: candidate.sdpMLineIndex,
        ),
      );
    };
  }

  @override
  set onDataChannel(void Function(SatelliteDataChannel channel)? listener) {
    _peer.onDataChannel = (channel) {
      listener?.call(FlutterSatelliteDataChannel(channel));
    };
  }

  @override
  set onStateChanged(void Function(SatellitePeerState state)? listener) {
    _peer.onConnectionState = (state) {
      listener?.call(switch (state) {
        rtc.RTCPeerConnectionState.RTCPeerConnectionStateNew =>
          SatellitePeerState.newState,
        rtc.RTCPeerConnectionState.RTCPeerConnectionStateConnecting =>
          SatellitePeerState.connecting,
        rtc.RTCPeerConnectionState.RTCPeerConnectionStateConnected =>
          SatellitePeerState.connected,
        rtc.RTCPeerConnectionState.RTCPeerConnectionStateDisconnected =>
          SatellitePeerState.disconnected,
        rtc.RTCPeerConnectionState.RTCPeerConnectionStateFailed =>
          SatellitePeerState.failed,
        rtc.RTCPeerConnectionState.RTCPeerConnectionStateClosed =>
          SatellitePeerState.closed,
      });
    };
  }

  @override
  Future<SatelliteDataChannel> createDataChannel(String label) async =>
      FlutterSatelliteDataChannel(
        await _peer.createDataChannel(label, rtc.RTCDataChannelInit()),
      );

  @override
  Future<SatelliteSessionDescription> createOffer() async {
    final description = await _peer.createOffer(<String, dynamic>{});
    return SatelliteSessionDescription(
      sdp: description.sdp ?? '',
      type: description.type ?? 'offer',
    );
  }

  @override
  Future<void> setLocalDescription(SatelliteSessionDescription description) =>
      _peer.setLocalDescription(
        rtc.RTCSessionDescription(description.sdp, description.type),
      );

  @override
  Future<SatelliteSessionDescription?> getLocalDescription() async {
    final description = await _peer.getLocalDescription();
    if (description == null ||
        description.sdp == null ||
        description.type == null) {
      return null;
    }
    return SatelliteSessionDescription(
      sdp: description.sdp!,
      type: description.type!,
    );
  }

  @override
  Future<void> setRemoteDescription(SatelliteSessionDescription description) =>
      _peer.setRemoteDescription(
        rtc.RTCSessionDescription(description.sdp, description.type),
      );

  @override
  Future<void> addCandidate(SatelliteIceCandidate candidate) =>
      _peer.addCandidate(
        rtc.RTCIceCandidate(
          candidate.candidate,
          candidate.sdpMid,
          candidate.sdpMLineIndex,
        ),
      );

  @override
  Future<void> close() => _peer.close();

  @override
  Future<void> dispose() => _peer.dispose();
}

final class FlutterSatelliteDataChannel implements SatelliteDataChannel {
  FlutterSatelliteDataChannel(this._channel);

  final rtc.RTCDataChannel _channel;
  void Function(SatelliteChannelState state)? _onStateChanged;
  void Function(String message)? _onMessage;

  @override
  String get label => _channel.label ?? '';

  @override
  SatelliteChannelState get state => switch (_channel.state) {
    rtc.RTCDataChannelState.RTCDataChannelConnecting =>
      SatelliteChannelState.connecting,
    rtc.RTCDataChannelState.RTCDataChannelOpen => SatelliteChannelState.open,
    rtc.RTCDataChannelState.RTCDataChannelClosing =>
      SatelliteChannelState.closing,
    rtc.RTCDataChannelState.RTCDataChannelClosed =>
      SatelliteChannelState.closed,
    null => SatelliteChannelState.closed,
  };

  @override
  set onStateChanged(void Function(SatelliteChannelState state)? listener) {
    _onStateChanged = listener;
    _channel.onDataChannelState = (_) => _onStateChanged?.call(state);
  }

  @override
  set onMessage(void Function(String message)? listener) {
    _onMessage = listener;
    _channel.onMessage = (message) {
      if (!message.isBinary) _onMessage?.call(message.text);
    };
  }

  @override
  Future<void> sendText(String message) =>
      _channel.send(rtc.RTCDataChannelMessage(message));

  @override
  Future<void> close() => _channel.close();
}

Future<SatellitePeerConnection> createFlutterSatellitePeerConnection(
  Map<String, dynamic> configuration,
) async => FlutterSatellitePeerConnection(
  await rtc.createPeerConnection(configuration),
);

final class RemoteResourceSlot {
  const RemoteResourceSlot({
    required this.id,
    required this.name,
    required this.resourceType,
    this.resourceId,
  });

  final String id;
  final String name;
  final String resourceType;
  final String? resourceId;

  RemoteResourceSlot copyWith({String? resourceId}) => RemoteResourceSlot(
    id: id,
    name: name,
    resourceType: resourceType,
    resourceId: resourceId,
  );
}

final class RemoteDashboardConfig {
  const RemoteDashboardConfig({
    required this.name,
    required this.pages,
    required this.resourceSlots,
  });

  final String name;
  final List<RemoteDashboardPage> pages;
  final List<RemoteResourceSlot> resourceSlots;

  factory RemoteDashboardConfig.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('Remote dashboard config must be an object.');
    }
    final pages = <RemoteDashboardPage>[];
    for (final raw in (value['pages'] as List?) ?? const []) {
      try {
        pages.add(RemoteDashboardPage.fromJson(raw));
      } on FormatException {
        // Keep valid pages visible when one remote widget is malformed.
      }
    }
    final slots = <RemoteResourceSlot>[];
    for (final raw in (value['resourceSlots'] as List?) ?? const []) {
      if (raw is! Map) continue;
      final id = raw['id']?.toString().trim() ?? '';
      final type = raw['slotType']?.toString().trim() ?? '';
      if (id.isEmpty || type.isEmpty) continue;
      slots.add(
        RemoteResourceSlot(
          id: id,
          name: raw['name']?.toString().trim().isNotEmpty == true
              ? raw['name'].toString()
              : id,
          resourceType: type,
        ),
      );
    }
    return RemoteDashboardConfig(
      name: value['name']?.toString().trim().isNotEmpty == true
          ? value['name'].toString()
          : 'Remote dashboard',
      pages: pages,
      resourceSlots: slots,
    );
  }
}

final class RemoteDashboardPage {
  const RemoteDashboardPage({
    required this.id,
    required this.name,
    required this.sections,
  });

  final String id;
  final String name;
  final List<RemoteDashboardSection> sections;

  factory RemoteDashboardPage.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('Remote dashboard page must be an object.');
    }
    final id = value['id']?.toString().trim() ?? '';
    if (id.isEmpty) {
      throw const FormatException('Remote dashboard page has no ID.');
    }
    return RemoteDashboardPage(
      id: id,
      name: value['name']?.toString() ?? id,
      sections: [
        for (final raw in (value['sections'] as List?) ?? const [])
          if (raw is Map) RemoteDashboardSection.fromJson(raw),
      ],
    );
  }
}

final class RemoteDashboardSection {
  const RemoteDashboardSection({
    required this.id,
    required this.name,
    required this.columns,
    required this.widgets,
  });

  final String id;
  final String name;
  final int columns;
  final List<RemoteDashboardWidget> widgets;

  factory RemoteDashboardSection.fromJson(Map value) {
    final id = value['id']?.toString().trim() ?? '';
    if (id.isEmpty) {
      throw const FormatException('Remote dashboard section has no ID.');
    }
    return RemoteDashboardSection(
      id: id,
      name: value['name']?.toString() ?? id,
      columns: (value['columns'] as num?)?.toInt().clamp(1, 12) ?? 4,
      widgets: [
        for (final raw in (value['widgets'] as List?) ?? const [])
          if (raw is Map) RemoteDashboardWidget.fromJson(raw),
      ],
    );
  }
}

final class RemoteDashboardWidget {
  const RemoteDashboardWidget({
    required this.id,
    required this.plugin,
    required this.widget,
    required this.width,
    required this.height,
    required this.config,
  });

  final String id;
  final String plugin;
  final String widget;
  final int width;
  final int height;
  final SatelliteJson config;

  factory RemoteDashboardWidget.fromJson(Map value) {
    final id = value['id']?.toString().trim() ?? '';
    if (id.isEmpty) {
      throw const FormatException('Remote dashboard widget has no ID.');
    }
    final size = value['size'] is Map
        ? Map<String, dynamic>.from(value['size'] as Map)
        : const <String, dynamic>{};
    final config = value['config'] is Map
        ? Map<String, dynamic>.from(value['config'] as Map)
        : <String, dynamic>{};
    return RemoteDashboardWidget(
      id: id,
      plugin: value['plugin']?.toString() ?? '',
      widget: value['widget']?.toString() ?? '',
      width: ((size['width'] as num?)?.toInt() ?? 1).clamp(1, 12),
      height: ((size['height'] as num?)?.toInt() ?? 1).clamp(1, 12),
      config: config,
    );
  }
}

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
