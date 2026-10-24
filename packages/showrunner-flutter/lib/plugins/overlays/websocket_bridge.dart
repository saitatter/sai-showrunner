import '../../services/public_data_projection.dart';
import 'dart:async';
import 'dart:io';

import '../../persistence/viewer_data_repository.dart';
import '../../persistence/filesystem/safe_path.dart';
import '../../schema/viewer_data.dart';
import '../../runtime/expression.dart';
import '../../services/plugin_event_hub.dart';
import '../http/manifest.dart';
import '../registry/plugin_registry.dart';
import '../sound/output.dart';
import 'manifest.dart';
import 'overlay_presence.dart';
import 'overlay_peer.dart';
import 'overlay_rpc_dispatcher.dart';
import 'overlay_access.dart';
import 'overlay_projection_policy.dart';
import 'overlay_http_resources.dart';
import 'overlay_audio_bridge.dart';
import 'overlay_media_resources.dart';
import 'overlay_state_subscriptions.dart';
import 'overlay_peer_manager.dart';

/// Bridges the Flutter runtime to the browser/WebGL overlay.
///
/// The browser renderer remains in `packages/showrunner-obs-overlay`; this
/// service owns the desktop-side HTTP resources and WebSocket RPC lifecycle.
final class DartOverlayWebSocketService implements OverlayPresenceReader {
  DartOverlayWebSocketService({
    required this.server,
    required this.eventHub,
    required this.overlayStore,
    required this.registry,
    required this.viewerDataRepository,
    this.soundOutputs,
    this.mediaRoot,
    this.ttsRoot,
    this.maxMessageBytes = 1024 * 1024,
    this.maxPeers = 32,
    this.requestTimeout = const Duration(seconds: 20),
    OverlayAccessTokens? access,
    Directory? webRoot,
  }) : access = access ?? OverlayAccessTokens.random(),
       webRoot = webRoot ?? discoverOverlayWebRoot() {
    if (maxPeers <= 0 ||
        maxMessageBytes <= 0 ||
        requestTimeout <= Duration.zero) {
      throw ArgumentError('Overlay peer limit must be positive.');
    }
    server.addRequestHandler(_http.handle);
    server.addWebSocketHandler(_manager.handle);
    registry.addListener(_broadcastStates);
    _subscriptions = [
      eventHub.stream(OverlayEventIds.widget).listen(_publishWidget),
      eventHub.stream(OverlayEventIds.widgetRpc).listen(_publishWidgetRpc),
      eventHub.stream(OverlayEventIds.broadcast).listen(_publishBroadcast),
      eventHub.stream(OverlayEventIds.configChanged).listen(_publishConfig),
      eventHub
          .stream('viewerDataAdded')
          .listen((event) => _publishViewerData('viewerDataAdded', event)),
      eventHub
          .stream('viewerDataChanged')
          .listen((event) => _publishViewerData('viewerDataChanged', event)),
    ];
  }

  final DartHttpEndpointService server;
  final DartPluginEventHub eventHub;
  final OverlayResourceStore overlayStore;
  final DartPluginRegistry registry;
  final ViewerDataRepository viewerDataRepository;
  final SoundOutputRegistry? soundOutputs;
  final Directory? mediaRoot;
  final Directory? ttsRoot;
  final int maxMessageBytes;
  final int maxPeers;
  final Duration requestTimeout;
  final Directory? webRoot;
  final OverlayAccessTokens access;
  late final List<StreamSubscription<RuntimeMap>> _subscriptions;
  late final _rpc = OverlayRpcDispatcher(
    registry: registry,
    viewerDataRepository: viewerDataRepository,
    eventHub: eventHub,
    overlayStore: overlayStore,
    send: (peer, _, args) => _states.update(
      peer,
      args[0] as String,
      args[1] as String,
      args[2],
      force: true,
    ),
    onStateReleased: (peer, key) => _states.forget(peer, key),
    onProjection: (peer, policy) {
      if (!peer.isClosed) _setProjection(peer.overlayId, policy);
    },
  );
  late final _states = OverlayStateSubscriptionService<OverlayPeer>(
    send: (peer, plugin, state, value) async {
      await peer.call('overlays_stateUpdate', [plugin, state, value]);
    },
    onFailure: (peer) => peer.close(),
  );
  late final _media = OverlayMediaResources(
    mediaRoot: mediaRoot,
    ttsRoot: ttsRoot,
  );
  late final _http = OverlayHttpResourceHandler(
    overlayStore: overlayStore,
    access: access,
    registerAudioOutput: registerAudioOutput,
    webRoot: webRoot,
    media: _media,
  );
  late final OverlayPeerManager _manager = OverlayPeerManager(
    overlayStore: overlayStore,
    access: access,
    maxPeers: maxPeers,
    maxMessageBytes: maxMessageBytes,
    requestTimeout: requestTimeout,
    onRequest: (peer, name, args) {
      if (_disposed) {
        return Future.error(StateError('Overlay service is closed.'));
      }
      return _rpc.handle(peer, name, args);
    },
    onJoined: (peer, resource) {
      registerAudioOutput(resource.id);
      _setProjection(
        resource.id,
        OverlayProjectionPolicy.fromResource(resource),
      );
    },
    configure: (peer, resource) async {
      await peer.call('overlays_setConfig', [
        await _http.projectConfig(resource),
      ]);
    },
    onClosed: (peer) {
      _states.detach(peer);
      if (_manager.targets(peer.overlayId).isEmpty) {
        _projections.remove(peer.overlayId);
      }
    },
  );
  final _projections = <String, OverlayProjectionPolicy>{};
  late final _audio = OverlayAudioBridge(
    send: _sendAudio,
    soundOutputs: soundOutputs,
    resolveMedia: _media.browserUrl,
  );
  bool _disposed = false;
  Future<void>? _closing;

  @override
  Future<OverlayPresence> getPresence(String overlayId) async {
    final subscribers = _manager.targets(overlayId).length;
    return OverlayPresence(
      overlayId: overlayId,
      connected: subscribers > 0,
      subscribers: subscribers,
    );
  }

  @override
  String browserSourceUrl(String overlayId) {
    final port = server.boundPort ?? server.port;
    return Uri(
      scheme: 'http',
      host: 'localhost',
      port: port,
      pathSegments: ['overlays', overlayId],
      fragment: access.forOverlay(overlayId),
    ).toString();
  }

  Future<void> dispose() => _closing ??= _dispose();

  Future<void> _dispose() async {
    if (_disposed) return;
    _disposed = true;
    _http.close();
    registry.removeListener(_broadcastStates);
    server.removeRequestHandler(_http.handle);
    server.removeWebSocketHandler(_manager.handle);
    _projections.clear();
    await Future.wait([
      ..._subscriptions.map((subscription) => subscription.cancel()),
      _audio.close(),
      _states.close(),
      _manager.close(),
    ]);
  }

  void _publishWidget(RuntimeMap event) {
    final widgetId = event['widgetId']?.toString() ?? '';
    if (widgetId.isEmpty) return;
    final overlayId = event['overlayId']?.toString() ?? '';
    for (final peer in _targetPeers(overlayId)) {
      unawaited(_send(peer, 'overlays_widget', [widgetId, event['payload']]));
    }
  }

  void _publishWidgetRpc(RuntimeMap event) {
    final widgetId = event['widgetId']?.toString() ?? '';
    final rpcId = event['rpcId']?.toString() ?? '';
    if (widgetId.isEmpty || rpcId.isEmpty) return;
    final overlayId = event['overlayId']?.toString() ?? '';
    final args = event['args'] is List ? event['args'] as List : const [];
    for (final peer in _targetPeers(overlayId)) {
      unawaited(_send(peer, 'overlays_widgetRPC', [widgetId, rpcId, ...args]));
    }
  }

  void _publishBroadcast(RuntimeMap event) {
    final broadcastId = event['broadcastId']?.toString() ?? '';
    if (broadcastId.isEmpty) return;
    final payload = event['payload'];
    final overlayId = payload is Map
        ? payload['targetOverlayId']?.toString() ?? ''
        : '';
    for (final peer in _targetPeers(overlayId)) {
      unawaited(_send(peer, 'overlays_broadcast', [broadcastId, payload]));
    }
  }

  Iterable<OverlayPeer> _targetPeers(String id) => _manager.targets(id);

  void _setProjection(String overlayId, OverlayProjectionPolicy policy) {
    if (_disposed) return;
    final peers = _targetPeers(overlayId).toList();
    if (peers.isEmpty) return;
    _projections[overlayId] = policy;
    for (final peer in peers) {
      for (final key
          in peer.acquiredStates
              .where((key) => !policy.statePaths.containsKey(key))
              .toList()) {
        _states.forget(peer, key);
      }
      peer.acquiredStates.removeWhere(
        (key) => !policy.statePaths.containsKey(key),
      );
      if (!policy.viewerData) peer.observingViewerData = false;
    }
  }

  void _publishConfig(RuntimeMap event) {
    if (_disposed) return;
    final overlayId = event['overlayId']?.toString().trim() ?? '';
    if (overlayId.isEmpty) return;
    unawaited(_reloadConfig(overlayId));
  }

  Future<void> _reloadConfig(String overlayId) async {
    try {
      validateFileIdentifier(overlayId);
    } on ArgumentError {
      return;
    }
    final resource = await overlayStore.load(overlayId);
    if (_disposed) return;
    if (resource == null) {
      await Future.wait(_targetPeers(overlayId).map((peer) => peer.close()));
      return;
    }
    _setProjection(overlayId, OverlayProjectionPolicy.fromResource(resource));
    for (final peer in _targetPeers(overlayId)) {
      await _send(peer, 'overlays_setConfig', [
        await _http.projectConfig(resource),
      ]);
    }
  }

  Future<bool> playAudio(String overlayId, SoundPlayRequest request) =>
      _audio.playAudio(overlayId, request);
  Future<void> cancelAudio(String overlayId, String playId) =>
      _audio.cancelAudio(overlayId, playId);
  void registerAudioOutput(String overlayId) =>
      _audio.registerAudioOutput(overlayId);

  Future<bool> _sendAudio(
    String overlayId,
    String name,
    List<dynamic> args,
  ) async {
    final peers = _targetPeers(overlayId).toList();
    if (peers.isEmpty) return false;
    final delivered = await Future.wait(
      peers.map((peer) async {
        try {
          await peer.call(name, args);
          return true;
        } on Object {
          return false;
        }
      }),
    );
    return delivered.any((value) => value);
  }

  void _publishViewerData(String eventId, RuntimeMap event) {
    for (final peer in _manager.peers) {
      if (!peer.observingViewerData) continue;
      final projection = _projections[peer.overlayId];
      if (projection == null || !projection.viewerData) continue;
      final provider = event['provider']?.toString() ?? '';
      final id = event['id']?.toString() ?? '';
      if (!{'twitch', 'youtube'}.contains(provider) || id.isEmpty) continue;
      if (eventId == 'viewerDataAdded') {
        unawaited(
          _send(peer, 'overlays_onNewViewerData', [
            provider,
            id,
            projection.projectViewer(
              ViewerDataRow(
                provider: provider,
                viewer: ViewerIdentity(
                  id: id,
                  displayName: event['displayName'] is String
                      ? event['displayName'] as String
                      : id,
                ),
                values: event['values'] is Map
                    ? Map<String, dynamic>.from(event['values'] as Map)
                    : const {},
              ),
            ),
          ]),
        );
        continue;
      }
      final variable = event['variable']?.toString() ?? '';
      if (variable.isNotEmpty) {
        if (!projection.viewerFields.contains(variable)) continue;
        unawaited(
          _send(peer, 'overlays_onViewerDataChanged', [
            provider,
            id,
            variable,
            projectPublicValue(event['value']),
          ]),
        );
        continue;
      }
      final values = event['values'];
      if (values is Map) {
        for (final entry in values.entries) {
          if (!projection.viewerFields.contains(entry.key)) continue;
          unawaited(
            _send(peer, 'overlays_onViewerDataChanged', [
              provider,
              id,
              entry.key.toString(),
              projectPublicValue(entry.value),
            ]),
          );
        }
      }
    }
  }

  void _broadcastStates() {
    final snapshots = <String, Map<String, dynamic>>{};
    for (final peer in _manager.peers) {
      if (peer.isClosed) continue;
      for (final key in peer.acquiredStates) {
        final policy = _projections[peer.overlayId];
        if (policy == null || !policy.statePaths.containsKey(key)) continue;
        final separator = key.indexOf('\u0000');
        if (separator < 0) continue;
        final plugin = key.substring(0, separator);
        final state = key.substring(separator + 1);
        unawaited(
          _states
              .update(
                peer,
                plugin,
                state,
                policy.projectState(
                  plugin,
                  state,
                  snapshots.putIfAbsent(
                    plugin,
                    () => registry.stateValues(plugin),
                  )[state],
                ),
              )
              .catchError((Object _) {}),
        );
      }
    }
  }

  Future<void> _send(OverlayPeer peer, String name, List<dynamic> args) async {
    try {
      await peer.call(name, args);
    } on Object {
      // A browser source can disappear during a reconnect; event delivery is
      // best effort and must not affect the automation runtime.
    }
  }
}
