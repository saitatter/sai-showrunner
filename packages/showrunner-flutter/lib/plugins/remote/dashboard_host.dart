import '../../services/public_data_projection.dart';
import 'dart:async';
import '../../services/structured_logger.dart';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../schema/json.dart';
import '../../schema/resource.dart';
import '../../services/plugin_event_hub.dart';
import '../../services/showrunner_data_service.dart';
import '../registry/plugin_registry.dart';
import 'satellite.dart';
import 'remote_control_session.dart';

typedef RemoteDashboardHostPeerFactory =
    Future<SatellitePeerConnection> Function(
      Map<String, dynamic> configuration,
    );

/// Hosts shared dashboards for the satellite protocol.
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
    this.dashboardLoader,
  });

  final ShowRunnerDataService dataService;
  final DartPluginRegistry registry;
  final DartPluginEventHub eventHub;
  final SatelliteSignalingController signaling;
  final RemoteDashboardHostPeerFactory peerFactory;
  final Future<ResourceData?> Function(String id)? dashboardLoader;

  final _connections = <String, _RemoteDashboardHostConnection>{};
  final _stateSubscriptions = <String, Set<String>>{};
  final _pendingCandidates = <String, List<Object?>>{};
  StreamSubscription<SatelliteSignalingMessage>? _signalingSubscription;
  StreamSubscription<FileSystemEvent>? _fileSubscription;
  final _candidateExpiry = <String, Timer>{};
  final _refreshTimers = <String, Timer>{};
  final _work = <Future<void>>{};
  final _retiring = <Future<void>>{};
  Future<void> _lifecycle = Future<void>.value();
  int _epoch = 0;
  bool _current(int epoch) => _started && !_closed && epoch == _epoch;
  Future<void> _serialize(Future<void> Function() operation) {
    final work = _lifecycle.then((_) => operation());
    _lifecycle = work.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return work;
  }

  void _observe(Future<void> Function() operation) {
    if (!_started || _closed || _work.length >= 64) return;
    final epoch = _epoch;
    late final Future<void> work;
    work = Future<void>.sync(operation)
        .catchError((Object _) {
          if (!_current(epoch)) return;
          _lastError = StateError('Remote dashboard operation failed.');
          notifyListeners();
        })
        .whenComplete(() => _work.remove(work));
    _work.add(work);
  }

  Object? _lastError;
  bool _started = false;
  bool _closed = false;

  bool get isStarted => _started;
  Object? get lastError => _lastError;
  List<String> get connectionIds => List.unmodifiable(_connections.keys);

  Future<void> start() {
    final epoch = _epoch;
    return _serialize(() => _start(epoch));
  }

  Future<void> _start(int epoch) async {
    if (_started || _closed || epoch != _epoch) return;
    _started = true;
    registry.addListener(_handleRegistryStateChange);
    _signalingSubscription = signaling.messages.listen(
      (message) => _observe(() => _handleSignal(message)),
    );
    _fileSubscription = _watchUserDirectory();

    // A project may have no shared dashboard or no Twitch token yet. That is
    // a valid desktop state and must not prevent the rest of the app starting.
    if (await _hasSharedDashboard() && _current(epoch)) {
      await _ensureSignalingStarted();
    }
  }

  Future<void> stop() {
    _epoch++;
    _started = false;
    for (final connection in _connections.values.toList()) {
      // Invalidate native callbacks before asynchronous subscription cleanup.
      unawaited(connection.close().catchError((Object _) {}));
    }
    for (final timer in [
      ..._candidateExpiry.values,
      ..._refreshTimers.values,
    ]) {
      timer.cancel();
    }
    _candidateExpiry.clear();
    _refreshTimers.clear();
    return _serialize(_stop);
  }

  Future<void> _stop() async {
    registry.removeListener(_handleRegistryStateChange);
    Object? failure;
    StackTrace? failureStack;
    Future<void> attempt(Future<void> Function() operation) async {
      try {
        await operation();
      } catch (error, stack) {
        failure ??= error;
        failureStack ??= stack;
      }
    }

    await attempt(() async => _signalingSubscription?.cancel());
    _signalingSubscription = null;
    await attempt(() async => _fileSubscription?.cancel());
    _fileSubscription = null;
    final connections = _connections.values.toList();
    _connections.clear();
    _stateSubscriptions.clear();
    _pendingCandidates.clear();
    for (final connection in connections) {
      await attempt(() async {
        try {
          await connection.close();
        } finally {
          connection.dispose();
        }
      });
    }
    await attempt(() async => Future.wait(_work.toList()));
    await attempt(() async => Future.wait(_retiring.toList()));
    await attempt(signaling.stop);
    if (failure != null) Error.throwWithStackTrace(failure!, failureStack!);

    notifyListeners();
  }

  /// Re-reads a dashboard and pushes its current configuration to connected
  /// satellites. This is also called by the filesystem watcher after an
  /// atomic resource save.
  Future<void> refreshDashboard(String dashboardId) async {
    final epoch = _epoch;
    if (!_current(epoch)) return;
    final resource = await _loadSharedDashboard(dashboardId);
    if (!_current(epoch)) return;
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
      if (!_requestIsAllowed(connection.config, resource)) {
        await _removeConnection(connection);
        continue;
      }
      connection.updateDashboardConfig(resource.config);
      await connection.sendDashboardConfig();
    }
  }

  Future<void> _handleSignal(SatelliteSignalingMessage message) async {
    final epoch = _epoch;
    if (!_current(epoch)) return;
    try {
      if (message.event == 'satelliteConnectionRequest') {
        await _handleConnectionRequest(message.data, epoch);
      } else if (message.event == 'satelliteConnectionIceCandidate' &&
          message.data['side'] == 'satellite') {
        final candidate = SatelliteIceCandidate.fromJson(
          message.data['candidate'],
        );
        final connection = _findConnection(message.data);
        if (connection != null) {
          await connection.applyCandidate(candidate.toJson());
        } else {
          final key = _signalKey(message.data);
          final config = _configFromSignal(message.data);
          if (key != null && config != null) {
            final dashboard = await _loadSharedDashboard(config.dashboardId);
            if (!_current(epoch) ||
                dashboard == null ||
                !_requestIsAllowed(config, dashboard)) {
              return;
            }
            if (!_pendingCandidates.containsKey(key) &&
                _pendingCandidates.length >= 64) {
              return;
            }
            _candidateExpiry.putIfAbsent(
              key,
              () => Timer(const Duration(seconds: 20), () {
                _pendingCandidates.remove(key);
                _candidateExpiry.remove(key);
              }),
            );
            final candidates = _pendingCandidates.putIfAbsent(
              key,
              () => <Object?>[],
            );
            if (candidates.length < 32) {
              candidates.add(candidate.toJson());
            }
          }
        }
      }
    } on Object {
      if (!_current(epoch)) return;
      _lastError = StateError('Remote dashboard negotiation failed.');
      notifyListeners();
    }
  }

  Future<void> _handleConnectionRequest(SatelliteJson data, int epoch) async {
    if (data['side']?.toString() == 'ShowRunner') return;
    final config = _configFromSignal(data);
    if (config == null) return;
    final dashboard = await _loadSharedDashboard(config.dashboardId);
    if (!_current(epoch) ||
        dashboard == null ||
        !_requestIsAllowed(config, dashboard)) {
      return;
    }

    final existing = _findConnection(data);
    if (existing != null) {
      await existing.acceptOffer(data['sdp']);
      return;
    }

    if (_connections.length >= 32) return;
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
      if (!_current(epoch) ||
          !identical(_connections[connection.id], connection)) {
        return;
      }
      final key = _signalKey(data);
      _candidateExpiry.remove(key)?.cancel();
      final candidates = key == null ? null : _pendingCandidates.remove(key);
      if (candidates != null) {
        for (final candidate in candidates) {
          await connection.applyCandidate(candidate);
        }
      }
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
    if (_closed ||
        !_started ||
        !identical(_connections[connection.id], connection)) {
      throw StateError('Dashboard session is no longer active.');
    }
    final resource = await _loadSharedDashboard(connection.config.dashboardId);
    if (_closed ||
        !_started ||
        !identical(_connections[connection.id], connection) ||
        resource == null ||
        !_requestIsAllowed(connection.config, resource)) {
      throw StateError('Dashboard access is no longer available.');
    }
    switch (name) {
      case 'dashboard_acquireState':
        _validateStateArgs(args);
        final plugin = args[0] as String;
        final state = args[1] as String;
        if (!registry.stateValues(plugin).containsKey(state)) {
          throw const FormatException('Unknown dashboard state.');
        }
        final subscriptions = _stateSubscriptions[connection.id];
        if (subscriptions == null) {
          throw StateError('Unknown dashboard connection.');
        }
        final key = '$plugin\u0000$state';
        if (!subscriptions.contains(key) && subscriptions.length >= 64) {
          throw StateError('Dashboard subscription limit exceeded.');
        }
        if (subscriptions.add(key)) {
          await connection.sendStateUpdate(
            plugin,
            state,
            registry.stateValues(plugin)[state],
          );
        }
        return null;
      case 'dashboard_freeState':
        _validateStateArgs(args);
        _stateSubscriptions[connection.id]?.remove(
          '${args[0]}\u0000${args[1]}',
        );
        return null;
      case 'dashboard_widgetRPC':
        return _handleWidgetRpc(resource.config, args);
      case 'satellite_resourceBind':
      case 'satellite_resourceUnbind':
        if (args.length != 1 ||
            !_validId(args.single) ||
            !RemoteDashboardConfig.fromJson(
              resource.config,
            ).resourceSlots.any((slot) => slot.id == args.single)) {
          throw const FormatException('Unknown dashboard resource slot.');
        }
        return null;
      default:
        throw UnsupportedError('Unsupported dashboard RPC: $name');
    }
  }

  Future<Object?> _handleWidgetRpc(
    JsonMap dashboardConfig,
    List<dynamic> args,
  ) async {
    if (args.length < 2 ||
        args.length > 3 ||
        args.any((arg) => !_validId(arg))) {
      throw const FormatException('Invalid dashboard action request.');
    }
    final rpcId = args[0]?.toString() ?? '';
    final widgetId = args[1]?.toString() ?? '';
    if (rpcId != 'pressbutton' || widgetId.isEmpty) return null;
    final widget = _findWidget(dashboardConfig, widgetId);
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

  static bool _validId(Object? value) =>
      value is String &&
      value.trim().isNotEmpty &&
      value.length <= 128 &&
      !value.contains('\u0000');
  static void _validateStateArgs(List<dynamic> args) {
    if (args.length != 2 ||
        args.any(
          (arg) => !_validId(arg) || isPrivatePublicField(arg as String),
        )) {
      throw const FormatException('Invalid dashboard state request.');
    }
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
      late final Future<void> closing;
      closing = connection
          .close()
          .whenComplete(connection.dispose)
          .catchError((Object error, StackTrace stack) {
            ShowRunnerLogger.instance.error(
              'remote',
              'Could not close dashboard connection.',
              error: error,
              stackTrace: stack,
            );
          })
          .whenComplete(() => _retiring.remove(closing));
      _retiring.add(closing);
      notifyListeners();
    }
  }

  Future<void> _removeConnection(
    _RemoteDashboardHostConnection connection,
  ) async {
    if (_connections.remove(connection.id) == null) return;
    _stateSubscriptions.remove(connection.id);
    final key = _signalKey(connection.config.toJson());
    if (key != null) {
      _pendingCandidates.remove(key);
      _candidateExpiry.remove(key)?.cancel();
    }
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
    try {
      return SatelliteConnectionConfig.fromJson(data);
    } on FormatException {
      return null;
    }
  }

  String? _signalKey(SatelliteJson data) {
    final config = _configFromSignal(data);
    if (config == null) return null;
    return [
      config.satelliteService,
      config.satelliteId,
      config.showRunnerService,
      config.showRunnerId,
      config.dashboardId,
    ].join('\u0000');
  }

  bool _requestIsAllowed(
    SatelliteConnectionConfig request,
    ResourceData dashboard,
  ) {
    final owner = dashboard.config['ownerId'];
    if (owner != null && owner is! String) return false;
    final configuredOwner = owner is String ? owner.trim() : null;
    if (configuredOwner?.isNotEmpty == true &&
        configuredOwner != request.showRunnerId) {
      return false;
    }
    final allowed = dashboard.config['remoteTwitchIds'];
    return allowed is List &&
        allowed.isNotEmpty &&
        allowed.every((value) => value is String) &&
        allowed.contains(request.satelliteId);
  }

  Future<ResourceData?> _loadSharedDashboard(String id) async {
    if (!_safeId(id)) {
      return null;
    }
    final resource =
        await (dashboardLoader?.call(id) ??
            dataService.storage
                .resource(const ResourceTypeId('Dashboard'))
                .load(id));
    if (resource == null) {
      return null;
    }
    final cloudId = resource.config['cloudId']?.toString().trim() ?? '';
    final remoteIds = resource.config['remoteTwitchIds'];
    if (cloudId.isEmpty || remoteIds is! List || remoteIds.isEmpty) return null;
    return resource;
  }

  Future<bool> _hasSharedDashboard() async {
    final resources = await dataService.storage
        .resource(const ResourceTypeId('Dashboard'))
        .list();
    return resources.any((resource) => _isShared(resource));
  }

  bool _isShared(ResourceData resource) {
    final cloudId = resource.config['cloudId']?.toString().trim() ?? '';
    final remoteIds = resource.config['remoteTwitchIds'];
    return cloudId.isNotEmpty && remoteIds is List && remoteIds.isNotEmpty;
  }

  Future<void> _ensureSignalingStarted() async {
    if (!_started || _closed || signaling.isConnected) return;
    final epoch = _epoch;
    try {
      await signaling.start();
      if (!_current(epoch)) return;
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
    try {
      return dataService.userDirectory
          .watch(recursive: true)
          .listen(
            (event) {
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
              if (!_started || _closed) return;
              if (!_refreshTimers.containsKey(id) &&
                  _refreshTimers.length >= 64) {
                return;
              }
              _refreshTimers.remove(id)?.cancel();
              final epoch = _epoch;
              _refreshTimers[id] = Timer(const Duration(milliseconds: 100), () {
                _refreshTimers.remove(id);
                if (!_current(epoch)) return;
                _observe(() async {
                  await refreshDashboard(id);
                  if (_current(epoch) &&
                      await _hasSharedDashboard() &&
                      _current(epoch)) {
                    await _ensureSignalingStarted();
                  }
                });
              });
            },
            onError: (Object error, StackTrace stackTrace) {
              _lastError = error;
              notifyListeners();
            },
          );
    } on Object catch (error) {
      _lastError = error;
      notifyListeners();
      return null;
    }
  }

  @override
  void notifyListeners() {
    if (!_closed) super.notifyListeners();
  }

  @override
  void dispose() {
    _closed = true;
    unawaited(
      stop().catchError((Object error, StackTrace stack) {
        ShowRunnerLogger.instance.error(
          'remote',
          'Dashboard host shutdown failed.',
          error: error,
          stackTrace: stack,
        );
      }),
    );
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
  RemoteControlSession? _session;
  bool _closed = false;
  bool _started = false;
  bool _configSent = false;
  int _configEpoch = 0;

  Future<void>? _accepting;
  Future<void> acceptOffer(Object? value) {
    if (_closed) return Future<void>.value();
    return _accepting ??= _acceptOffer(
      value,
    ).whenComplete(() => _accepting = null);
  }

  Future<void> _acceptOffer(Object? value) async {
    final description = SatelliteSessionDescription.fromJson(value);
    final peer =
        _peer ??
        await peerFactory({
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
    if (!_started) {
      _started = true;
      peer.onIceCandidate = (candidate) {
        if (_closed || !identical(_peer, peer)) return;
        unawaited(
          signaling
              .send('satelliteConnectionIceCandidate', {
                ...config.toJson(),
                'side': 'ShowRunner',
                'candidate': candidate.toJson(),
              })
              .catchError((Object _) {}),
        );
      };
      peer.onDataChannel = _handleDataChannel;
      peer.onStateChanged = _handlePeerState;
    }
    await peer.setRemoteDescription(description);
    if (_closed) return;
    final answer = await peer.createAnswer();
    if (_closed) return;
    await peer.setLocalDescription(answer);
    if (_closed) return;
    final local = await peer.getLocalDescription() ?? answer;
    if (_closed) return;
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

  Future<dynamic> callRpc(String name, [List<dynamic> args = const []]) {
    final session = _session;
    if (_closed || session == null) {
      return Future.error(
        StateError('Remote dashboard control channel is not connected.'),
      );
    }
    return session.call(name, args);
  }

  Future<void> sendDashboardConfig() async {
    if (_configSent || _closed) return;
    final epoch = _configEpoch;
    await callRpc('dashboard_setConfig', [
      RemoteDashboardConfig.fromJson(dashboardConfig).toJson(),
    ]);
    if (!_closed && epoch == _configEpoch) _configSent = true;
  }

  void updateDashboardConfig(JsonMap config) {
    dashboardConfig = Map<String, dynamic>.from(config);
    _configEpoch++;
    _configSent = false;
  }

  Future<void> sendStateUpdate(String plugin, String state, dynamic value) =>
      callRpc('dashboard_stateUpdate', [
        plugin,
        state,
        projectPublicValue(value),
      ]);

  Future<void>? _closing;
  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    if (_closed) return;
    _closed = true;
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
          try {
            await sessionClosing;
          } finally {
            await _accepting?.catchError((Object _) {});
          }
        }
      }
    }
  }

  @override
  void notifyListeners() {
    if (!_closed) super.notifyListeners();
  }

  void _handleDataChannel(SatelliteDataChannel channel) {
    if (_closed || _control != null) {
      unawaited(channel.close());
      return;
    }
    if (channel.label != 'controlChannel') {
      unawaited(channel.close());
      return;
    }
    _control = channel;
    _session = RemoteControlSession(
      channel: channel,
      resourceId: config.dashboardId,
      requestPrefix: id,
      onRequest: onRequest,
      onInvalid: () async {
        onClosed(this);
      },
    );
    channel.onStateChanged = (state) {
      if (_closed || !identical(_control, channel)) return;
      if (state == SatelliteChannelState.open) {
        unawaited(sendDashboardConfig().catchError((_) {}));
        notifyListeners();
      } else if (state == SatelliteChannelState.closing ||
          state == SatelliteChannelState.closed) {
        onClosed(this);
      }
    };
    if (channel.state == SatelliteChannelState.open) {
      unawaited(sendDashboardConfig().catchError((_) {}));
    }
  }

  void _handlePeerState(SatellitePeerState state) {
    if (_closed) return;
    if (state == SatellitePeerState.failed ||
        state == SatellitePeerState.disconnected ||
        state == SatellitePeerState.closed) {
      onClosed(this);
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
