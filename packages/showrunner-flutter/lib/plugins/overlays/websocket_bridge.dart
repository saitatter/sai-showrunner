import 'dart:async';
import 'dart:io';

import '../../persistence/viewer_data_repository.dart';
import '../../persistence/filesystem/safe_path.dart';
import '../../schema/resource.dart';
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
    if (maxPeers <= 0) {
      throw ArgumentError('Overlay peer limit must be positive.');
    }
    server.addRequestHandler(_http.handle);
    server.addWebSocketHandler(_handleWebSocket);
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
    send: _send,
    onProjection: (peer, policy) {
      if (!peer.isClosed) _setProjection(peer.overlayId, policy);
    },
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
  final _peers = <OverlayPeer>{};
  final _projections = <String, OverlayProjectionPolicy>{};
  late final _audio = OverlayAudioBridge(
    send: _sendAudio,
    soundOutputs: soundOutputs,
    resolveMedia: _media.browserUrl,
  );
  bool _disposed = false;
  int _joining = 0;
  final _joins = <Future<bool>>{};
  Future<void>? _closing;

  @override
  Future<OverlayPresence> getPresence(String overlayId) async {
    final subscribers = _peers
        .where((peer) => peer.overlayId == overlayId)
        .length;
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
    server.removeWebSocketHandler(_handleWebSocket);
    await Future.wait(
      _subscriptions.map((subscription) => subscription.cancel()),
    );
    final peers = List<OverlayPeer>.of(_peers);
    _peers.clear();
    _projections.clear();
    await Future.wait([_audio.close(), ...peers.map((peer) => peer.close())]);
    await Future.wait(_joins.toList());
  }

  Future<bool> _handleWebSocket(HttpRequest request, WebSocket socket) {
    final joining = _joinSocket(request, socket);
    _joins.add(joining);
    joining.then<void>(
      (_) {
        _joins.remove(joining);
      },
      onError: (Object _, StackTrace _) {
        _joins.remove(joining);
      },
    );
    return joining;
  }

  Future<void> _rejectSocket(WebSocket socket, int code) async {
    try {
      await socket.close(code).timeout(requestTimeout);
    } on Object {
      /* The server owns final socket teardown. */
    }
  }

  Future<bool> _joinSocket(HttpRequest request, WebSocket socket) async {
    final segments = request.uri.pathSegments;
    if (segments.length != 3 ||
        segments.first != 'overlays' ||
        segments.last != 'socket') {
      return false;
    }
    final overlayId = segments[1];
    if (overlayId.isEmpty) return false;
    try {
      validateFileIdentifier(overlayId);
    } on ArgumentError {
      return false;
    }
    if (_disposed ||
        !access.authorizes(request, overlayId) ||
        _peers.length + _joining >= maxPeers) {
      await _rejectSocket(socket, WebSocketStatus.policyViolation);
      return true;
    }
    _joining++;
    try {
      final resource = await overlayStore
          .load(overlayId)
          .timeout(requestTimeout);
      if (_disposed || resource == null) {
        await _rejectSocket(socket, WebSocketStatus.normalClosure);
        return true;
      }
      registerAudioOutput(resource.id);
      final peer = OverlayPeer(
        socket,
        overlayId: overlayId,
        maxMessageBytes: maxMessageBytes,
        requestTimeout: requestTimeout,
      );
      peer.onRequest = (name, args) => _rpc.handle(peer, name, args);
      _peers.add(peer);
      _setProjection(overlayId, OverlayProjectionPolicy.fromResource(resource));
      unawaited(_servePeer(peer, resource));
      return true;
    } on Object {
      await _rejectSocket(socket, WebSocketStatus.policyViolation);
      return true;
    } finally {
      _joining--;
    }
  }

  Future<void> _servePeer(OverlayPeer peer, ResourceData resource) async {
    try {
      await peer.call('overlays_setConfig', [
        await _http.projectConfig(resource),
      ]);
      await peer.done;
    } catch (_) {
      await peer.close();
    } finally {
      _peers.remove(peer);
      if (!_peers.any((other) => other.overlayId == peer.overlayId)) {
        _projections.remove(peer.overlayId);
      }
    }
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

  Iterable<OverlayPeer> _targetPeers(String overlayId) sync* {
    for (final peer in List<OverlayPeer>.of(_peers)) {
      if (overlayId.isEmpty || peer.overlayId == overlayId) yield peer;
    }
  }

  void _setProjection(String overlayId, OverlayProjectionPolicy policy) {
    if (_disposed) return;
    final peers = _targetPeers(overlayId).toList();
    if (peers.isEmpty) return;
    _projections[overlayId] = policy;
    for (final peer in peers) {
      peer.acquiredStates.removeWhere(
        (key) => !policy.statePaths.containsKey(key),
      );
      if (!policy.viewerData) peer.observingViewerData = false;
    }
  }

  void _publishConfig(RuntimeMap event) {
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
    for (final peer in List<OverlayPeer>.of(_peers)) {
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
            publicOverlayValue(event['value']),
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
              publicOverlayValue(entry.value),
            ]),
          );
        }
      }
    }
  }

  void _broadcastStates() {
    for (final peer in List<OverlayPeer>.of(_peers)) {
      for (final key in peer.acquiredStates) {
        final policy = _projections[peer.overlayId];
        if (policy == null || !policy.statePaths.containsKey(key)) continue;
        final separator = key.indexOf('\u0000');
        if (separator < 0) continue;
        final plugin = key.substring(0, separator);
        final state = key.substring(separator + 1);
        unawaited(
          _send(peer, 'overlays_stateUpdate', [
            plugin,
            state,
            policy.projectState(
              plugin,
              state,
              registry.stateValues(plugin)[state],
            ),
          ]),
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
