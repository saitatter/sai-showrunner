import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../persistence/resource_repository.dart';
import '../../schema/automation.dart';
import '../../schema/resource.dart';
import '../../services/plugin_event_hub.dart';
import '../../services/showrunner_data_service.dart';
import '../registry/plugin_registry.dart';
import 'satellite.dart';

typedef RemoteDashboardHostPeerFactory =
    Future<SatellitePeerConnection> Function(
      Map<String, dynamic> configuration,
    );

/// Hosts shared dashboards for the Electron-compatible satellite protocol.
///
/// The desktop app is the ShowRunner side of the connection. Signaling is
/// still performed through the cloud PubSub service, while dashboard data and
/// RPC traffic stay on the authenticated WebRTC data channel.
final class RemoteDashboardHost extends ChangeNotifier {
  RemoteDashboardHost({
    required this.dataService,
    required this.registry,
    required this.eventHub,
    required this.signaling,
    this.peerFactory = createFlutterSatellitePeerConnection,
  });

  final ShowRunnerDataService dataService;
  final DartPluginRegistry registry;
  final DartPluginEventHub eventHub;
  final SatelliteSignalingController signaling;
  final RemoteDashboardHostPeerFactory peerFactory;

  final _connections = <String, _RemoteDashboardHostConnection>{};
  final _stateSubscriptions = <String, Set<String>>{};
  StreamSubscription<SatelliteSignalingMessage>? _signalingSubscription;
  StreamSubscription<FileSystemEvent>? _fileSubscription;
  Object? _lastError;
  bool _started = false;
  bool _closed = false;

  bool get isStarted => _started;
  Object? get lastError => _lastError;
  List<String> get connectionIds => List.unmodifiable(_connections.keys);

  Future<void> start() async {
    if (_started || _closed) return;
    _started = true;
    registry.addListener(_handleRegistryStateChange);
    _signalingSubscription = signaling.messages.listen(
      (message) => unawaited(_handleSignal(message)),
    );
    _fileSubscription = _watchUserDirectory();

    // A project may have no shared dashboard or no Twitch token yet. That is
    // a valid desktop state and must not prevent the rest of the app starting.
    if (await _hasSharedDashboard()) {
      await _ensureSignalingStarted();
    }
  }

  Future<void> stop() async {
    if (!_started) return;
    _started = false;
    registry.removeListener(_handleRegistryStateChange);
    await _signalingSubscription?.cancel();
    _signalingSubscription = null;
    await _fileSubscription?.cancel();
    _fileSubscription = null;
    for (final connection in _connections.values.toList()) {
      _connections.remove(connection.id);
      _stateSubscriptions.remove(connection.id);
      await connection.close();
      connection.dispose();
    }
    _connections.clear();
    _stateSubscriptions.clear();
    await signaling.stop();
    notifyListeners();
  }

  /// Re-reads a dashboard and pushes its current configuration to connected
  /// satellites. This is also called by the filesystem watcher after an
  /// atomic resource save.
  Future<void> refreshDashboard(String dashboardId) async {
    final resource = await _loadSharedDashboard(dashboardId);
    final matching = _connections.values
        .where((connection) => connection.config.dashboardId == dashboardId)
        .toList();
    if (resource == null) {
      for (final connection in matching) {
        await _removeConnection(connection);
      }
      return;
    }
    for (final connection in matching) {
      connection.updateDashboardConfig(resource.config);
      await connection.sendDashboardConfig();
    }
  }

  Future<void> _handleSignal(SatelliteSignalingMessage message) async {
    try {
      if (message.event == 'satelliteConnectionRequest') {
        await _handleConnectionRequest(message.data);
      } else if (message.event == 'satelliteConnectionIceCandidate' &&
          message.data['side']?.toString() == 'satellite') {
        final connection = _findConnection(message.data);
        await connection?.applyCandidate(message.data['candidate']);
      }
    } on Object catch (error) {
      _lastError = error;
      notifyListeners();
    }
  }

  Future<void> _handleConnectionRequest(SatelliteJson data) async {
    if (data['side']?.toString() == 'ShowRunner') return;
    final config = _configFromSignal(data);
    if (config == null) return;
    final dashboard = await _loadSharedDashboard(config.dashboardId);
    if (dashboard == null || !_requestIsAllowed(config, dashboard)) return;

    final existing = _findConnection(data);
    if (existing != null) {
      await existing.acceptOffer(data['sdp']);
      return;
    }

    late final _RemoteDashboardHostConnection connection;
    connection = _RemoteDashboardHostConnection(
      id: 'host-${DateTime.now().microsecondsSinceEpoch}',
      config: config,
      dashboardConfig: dashboard.config,
      signaling: signaling,
      peerFactory: peerFactory,
      onRequest: (name, args) => _handleRpc(connection, name, args),
      onClosed: _connectionClosed,
    );
    _connections[connection.id] = connection;
    _stateSubscriptions[connection.id] = <String>{};
    try {
      await connection.acceptOffer(data['sdp']);
      notifyListeners();
    } catch (_) {
      await _removeConnection(connection);
      rethrow;
    }
  }

  Future<Object?> _handleRpc(
    _RemoteDashboardHostConnection connection,
    String name,
    List<dynamic> args,
  ) async {
    switch (name) {
      case 'dashboard_acquireState':
        if (args.length < 2) {
          throw const FormatException('State request is incomplete.');
        }
        final plugin = args[0]?.toString() ?? '';
        final state = args[1]?.toString() ?? '';
        if (plugin.isEmpty || state.isEmpty) {
          throw const FormatException('State request is incomplete.');
        }
        final subscriptions = _stateSubscriptions[connection.id];
        if (subscriptions == null) {
          throw StateError('Unknown dashboard connection.');
        }
        final key = '$plugin\u0000$state';
        if (subscriptions.add(key)) {
          await connection.sendStateUpdate(
            plugin,
            state,
            registry.stateValues(plugin)[state],
          );
        }
        return null;
      case 'dashboard_freeState':
        if (args.length >= 2) {
          _stateSubscriptions[connection.id]?.remove(
            '${args[0]}\u0000${args[1]}',
          );
        }
        return null;
      case 'dashboard_widgetRPC':
        return _handleWidgetRpc(connection, args);
      case 'satellite_resourceBind':
      case 'satellite_resourceUnbind':
        // Resource slots are owned by the dashboard host. The binding itself
        // is tracked by the satellite side; acknowledging these messages is
        // enough for protocol parity and keeps the host ready for resource
        // widgets added by future dashboard plugins.
        return null;
      default:
        throw UnsupportedError('Unsupported dashboard RPC: $name');
    }
  }

  Future<Object?> _handleWidgetRpc(
    _RemoteDashboardHostConnection connection,
    List<dynamic> args,
  ) async {
    if (args.length < 2) {
      throw const FormatException('Widget RPC is incomplete.');
    }
    final rpcId = args[0]?.toString() ?? '';
    final widgetId = args[1]?.toString() ?? '';
    if (rpcId != 'pressbutton' || widgetId.isEmpty) return null;
    final widget = _findWidget(connection.dashboardConfig, widgetId);
    if (widget == null ||
        widget['plugin']?.toString() != 'remote' ||
        widget['widget']?.toString() != 'button') {
      return null;
    }
    final configuredName = _mapValue(
      widget['config'],
    )['triggerName']?.toString().trim();
    final requestedName = args.length > 2 ? args[2]?.toString().trim() : null;
    if (configuredName == null ||
        configuredName.isEmpty ||
        (requestedName?.isNotEmpty == true &&
            requestedName != configuredName)) {
      return null;
    }
    eventHub.emit('remoteButton', {'name': configuredName});
    return true;
  }

  void _handleRegistryStateChange() {
    for (final connection in _connections.values) {
      for (final key
          in _stateSubscriptions[connection.id] ?? const <String>{}) {
        final parts = key.split('\u0000');
        if (parts.length != 2) {
          continue;
        }
        unawaited(
          connection
              .sendStateUpdate(
                parts[0],
                parts[1],
                registry.stateValues(parts[0])[parts[1]],
              )
              .catchError((_) {}),
        );
      }
    }
  }

  void _connectionClosed(_RemoteDashboardHostConnection connection) {
    if (_connections.remove(connection.id) != null) {
      _stateSubscriptions.remove(connection.id);
      connection.dispose();
      notifyListeners();
    }
  }

  Future<void> _removeConnection(
    _RemoteDashboardHostConnection connection,
  ) async {
    if (_connections.remove(connection.id) == null) return;
    _stateSubscriptions.remove(connection.id);
    await connection.close();
    connection.dispose();
    notifyListeners();
  }

  _RemoteDashboardHostConnection? _findConnection(SatelliteJson data) {
    for (final connection in _connections.values) {
      if (connection.config.matches(data)) return connection;
    }
    return null;
  }

  SatelliteConnectionConfig? _configFromSignal(SatelliteJson data) {
    final satelliteService = data['satelliteService']?.toString().trim() ?? '';
    final satelliteId = data['satelliteId']?.toString().trim() ?? '';
    final showRunnerService =
        data['ShowRunnerService']?.toString().trim() ?? '';
    final showRunnerId = data['ShowRunnerId']?.toString().trim() ?? '';
    final dashboardId = data['dashId']?.toString().trim() ?? '';
    if ([
      satelliteService,
      satelliteId,
      showRunnerService,
      showRunnerId,
      dashboardId,
    ].any((value) => value.isEmpty)) {
      return null;
    }
    return SatelliteConnectionConfig(
      satelliteService: satelliteService,
      satelliteId: satelliteId,
      showRunnerService: showRunnerService,
      showRunnerId: showRunnerId,
      dashboardId: dashboardId,
    );
  }

  bool _requestIsAllowed(
    SatelliteConnectionConfig request,
    ResourceData dashboard,
  ) {
    final configuredOwner = dashboard.config['ownerId']?.toString().trim();
    if (configuredOwner?.isNotEmpty == true &&
        configuredOwner != request.showRunnerId) {
      return false;
    }
    final allowed = dashboard.config['remoteTwitchIds'];
    if (allowed is List && allowed.isNotEmpty) {
      return allowed
          .map((value) => value.toString())
          .contains(request.satelliteId);
    }
    return true;
  }

  Future<ResourceData?> _loadSharedDashboard(String id) async {
    if (!_safeId(id)) {
      return null;
    }
    final resource = await ResourceRepository(
      Directory('${dataService.userDirectory.path}/dashboards'),
    ).load(id);
    if (resource == null) {
      return null;
    }
    final cloudId = resource.config['cloudId']?.toString().trim() ?? '';
    final remoteIds = resource.config['remoteTwitchIds'];
    if (cloudId.isEmpty || remoteIds is! List || remoteIds.isEmpty) return null;
    return resource;
  }

  Future<bool> _hasSharedDashboard() async {
    final resources = await ResourceRepository(
      Directory('${dataService.userDirectory.path}/dashboards'),
    ).list();
    return resources.any((resource) => _isShared(resource));
  }

  bool _isShared(ResourceData resource) {
    final cloudId = resource.config['cloudId']?.toString().trim() ?? '';
    final remoteIds = resource.config['remoteTwitchIds'];
    return cloudId.isNotEmpty && remoteIds is List && remoteIds.isNotEmpty;
  }

  Future<void> _ensureSignalingStarted() async {
    if (!_started || _closed || signaling.isConnected) return;
    try {
      await signaling.start();
      _lastError = null;
      notifyListeners();
    } on Object catch (error) {
      _lastError = error;
      notifyListeners();
      // Remote connectivity is optional and must not break local startup.
    }
  }

  StreamSubscription<FileSystemEvent>? _watchUserDirectory() {
    if (!dataService.userDirectory.existsSync()) return null;
    return dataService.userDirectory.watch(recursive: true).listen((event) {
      final path = event.path.replaceAll('\\', '/');
      final marker = '/dashboards/';
      final markerIndex = path.indexOf(marker);
      if (markerIndex < 0) return;
      final name = path.substring(markerIndex + marker.length);
      if (name.contains('/') ||
          !(name.endsWith('.json') || name.endsWith('.yaml'))) {
        return;
      }
      final id = name.replaceFirst(RegExp(r'\.(json|yaml)$'), '');
      unawaited(
        Future<void>.delayed(const Duration(milliseconds: 100), () async {
          await refreshDashboard(id);
          if (await _hasSharedDashboard()) await _ensureSignalingStarted();
        }),
      );
    });
  }

  @override
  void dispose() {
    _closed = true;
    unawaited(stop());
    super.dispose();
  }
}

final class _RemoteDashboardHostConnection extends ChangeNotifier {
  _RemoteDashboardHostConnection({
    required this.id,
    required this.config,
    required this.dashboardConfig,
    required this.signaling,
    required this.peerFactory,
    required this.onRequest,
    required this.onClosed,
  });

  final String id;
  final SatelliteConnectionConfig config;
  final SatelliteSignalingController signaling;
  final RemoteDashboardHostPeerFactory peerFactory;
  Future<Object?> Function(String name, List<dynamic> args) onRequest;
  final void Function(_RemoteDashboardHostConnection connection) onClosed;

  JsonMap dashboardConfig;
  SatellitePeerConnection? _peer;
  SatelliteDataChannel? _control;
  final _pending = <String, Completer<dynamic>>{};
  int _requestNumber = 0;
  bool _closed = false;
  bool _started = false;
  bool _configSent = false;

  Future<void> acceptOffer(Object? value) async {
    if (_closed) return;
    final peer = _peer ??= await peerFactory({
      'sdpSemantics': 'unified-plan',
      'iceServers': const [
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:3478'},
      ],
    });
    if (!_started) {
      _started = true;
      peer.onIceCandidate = (candidate) {
        unawaited(
          signaling.send('satelliteConnectionIceCandidate', {
            ...config.toJson(),
            'side': 'ShowRunner',
            'candidate': candidate.toJson(),
          }),
        );
      };
      peer.onDataChannel = _handleDataChannel;
      peer.onStateChanged = _handlePeerState;
    }
    await peer.setRemoteDescription(
      SatelliteSessionDescription.fromJson(value),
    );
    final answer = await peer.createAnswer();
    await peer.setLocalDescription(answer);
    final local = await peer.getLocalDescription() ?? answer;
    await signaling.send('satelliteConnectionResponse', {
      ...config.toJson(),
      'sdp': local.toJson(),
    });
  }

  Future<void> applyCandidate(Object? value) async {
    final peer = _peer;
    if (peer == null || _closed) return;
    await peer.addCandidate(SatelliteIceCandidate.fromJson(value));
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
    _pending[requestId] = completer;
    await channel.sendText(
      jsonEncode({'requestId': requestId, 'name': name, 'args': args}),
    );
    try {
      return await completer.future.timeout(const Duration(seconds: 20));
    } finally {
      _pending.remove(requestId);
    }
  }

  Future<void> sendDashboardConfig() async {
    if (_configSent || _closed) return;
    await callRpc('dashboard_setConfig', [dashboardConfig]);
    _configSent = true;
  }

  void updateDashboardConfig(JsonMap config) {
    dashboardConfig = Map<String, dynamic>.from(config);
    _configSent = false;
  }

  Future<void> sendStateUpdate(String plugin, String state, dynamic value) =>
      callRpc('dashboard_stateUpdate', [plugin, state, value]);

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('Remote dashboard disconnected.'));
      }
    }
    _pending.clear();
    await _control?.close();
    await _peer?.close();
    await _peer?.dispose();
    _control = null;
    _peer = null;
  }

  void _handleDataChannel(SatelliteDataChannel channel) {
    if (channel.label != 'controlChannel') {
      unawaited(channel.close());
      return;
    }
    _control = channel;
    channel.onStateChanged = (state) {
      if (state == SatelliteChannelState.open) {
        unawaited(sendDashboardConfig().catchError((_) {}));
        notifyListeners();
      } else if (state == SatelliteChannelState.closed) {
        onClosed(this);
      }
    };
    channel.onMessage = (message) => unawaited(_handleControlMessage(message));
    if (channel.state == SatelliteChannelState.open) {
      unawaited(sendDashboardConfig().catchError((_) {}));
    }
  }

  void _handlePeerState(SatellitePeerState state) {
    if (state == SatellitePeerState.failed ||
        state == SatellitePeerState.disconnected ||
        state == SatellitePeerState.closed) {
      onClosed(this);
    }
  }

  Future<void> _handleControlMessage(String raw) async {
    final decoded = _decodeJson(raw);
    if (decoded is! Map) return;
    final responseId = decoded['responseId']?.toString();
    if (responseId != null) {
      final completer = _pending[responseId];
      if (completer == null || completer.isCompleted) return;
      if (decoded.containsKey('failed')) {
        completer.completeError(StateError(decoded['failed'].toString()));
      } else {
        completer.complete(decoded['result']);
      }
      return;
    }
    final requestId = decoded['requestId']?.toString();
    final name = decoded['name']?.toString();
    if (requestId == null || name == null) return;
    final args = decoded['args'] is List
        ? List<dynamic>.from(decoded['args'] as List)
        : const <dynamic>[];
    try {
      final result = await onRequest(name, args);
      await _control?.sendText(
        jsonEncode({'responseId': requestId, 'result': result}),
      );
    } on Object catch (error) {
      await _control?.sendText(
        jsonEncode({'responseId': requestId, 'failed': error.toString()}),
      );
    }
  }

  dynamic _decodeJson(String value) {
    try {
      return jsonDecode(value);
    } on FormatException {
      return null;
    }
  }
}

Map<String, dynamic> _mapValue(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

Map<String, dynamic>? _findWidget(JsonMap config, String widgetId) {
  final pages = config['pages'];
  if (pages is! List) return null;
  for (final page in pages) {
    final sections = _mapValue(page)['sections'];
    if (sections is! List) continue;
    for (final section in sections) {
      final widgets = _mapValue(section)['widgets'];
      if (widgets is! List) continue;
      for (final widget in widgets) {
        final candidate = _mapValue(widget);
        if (candidate['id']?.toString() == widgetId) return candidate;
      }
    }
  }
  return null;
}

bool _safeId(String value) =>
    value.trim().isNotEmpty && !value.contains('/') && !value.contains('\\');
