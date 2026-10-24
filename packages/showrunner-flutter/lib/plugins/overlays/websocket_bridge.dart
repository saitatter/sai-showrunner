import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../persistence/viewer_data_repository.dart';
import '../../persistence/filesystem/safe_path.dart';
import '../../schema/json.dart';
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
       webRoot = webRoot ?? _discoverWebRoot() {
    if (maxPeers <= 0) {
      throw ArgumentError('Overlay peer limit must be positive.');
    }
    server.addRequestHandler(_handleHttpRequest);
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
  final _peers = <OverlayPeer>{};
  final _projections = <String, OverlayProjectionPolicy>{};
  final _audioCancellations = <String, Completer<void>>{};
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
    registry.removeListener(_broadcastStates);
    server.removeRequestHandler(_handleHttpRequest);
    server.removeWebSocketHandler(_handleWebSocket);
    await Future.wait(
      _subscriptions.map((subscription) => subscription.cancel()),
    );
    final peers = List<OverlayPeer>.of(_peers);
    _peers.clear();
    _projections.clear();
    for (final cancellation in _audioCancellations.values) {
      if (!cancellation.isCompleted) cancellation.complete();
    }
    _audioCancellations.clear();
    await Future.wait(peers.map((peer) => peer.close()));
    await Future.wait(_joins.toList());
  }

  Future<bool> _handleHttpRequest(HttpRequest request) async {
    if (_disposed) {
      await _respond(request, HttpStatus.serviceUnavailable);
      return true;
    }
    final segments = request.uri.pathSegments;
    if (segments.isEmpty) return false;
    if (segments.first != 'overlays') return false;
    request.response.headers.set('Cache-Control', 'no-store');
    request.response.headers.set('Referrer-Policy', 'no-referrer');

    if (segments.length >= 3 && segments[1] != 'assets') {
      final id = segments[1];
      if (segments[2] == 'session' &&
          segments.length == 3 &&
          request.method == 'POST') {
        if (!access.accepts(
          id,
          request.headers.value('x-showrunner-overlay'),
        )) {
          await _respond(request, HttpStatus.unauthorized);
          return true;
        }
        request.response.cookies.add(
          Cookie(OverlayAccessTokens.cookieName, access.forOverlay(id))
            ..path = '/overlays/${Uri.encodeComponent(id)}'
            ..httpOnly = true
            ..sameSite = SameSite.strict
            ..maxAge = 86400,
        );
        await _respond(request, HttpStatus.noContent);
        return true;
      }
      if ((segments[2] == 'config' || segments[2] == 'media') &&
          !_authorized(request, id)) {
        await _respond(request, HttpStatus.unauthorized);
        return true;
      }
      if (segments[2] == 'media' && request.method == 'GET') {
        final resource = await overlayStore.load(id);
        if (_disposed || resource == null) {
          await _respond(
            request,
            _disposed ? HttpStatus.serviceUnavailable : HttpStatus.notFound,
          );
          return true;
        }
        return _serveMedia(request, segments.skip(2).toList());
      }
    }
    if (request.method != 'GET') return false;

    if (segments.length == 3 && segments[2] == 'config') {
      final resource = await overlayStore.load(segments[1]);
      if (_disposed) {
        await _respond(request, HttpStatus.serviceUnavailable);
        return true;
      }
      if (resource == null) {
        await _respond(request, HttpStatus.notFound);
        return true;
      }
      registerAudioOutput(resource.id);
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json;
      request.response.write(jsonEncode(_remoteConfig(resource)));
      await request.response.close();
      return true;
    }

    final root = webRoot;
    if (root == null) return false;
    File? file;
    if (segments.length == 2) {
      final resource = await overlayStore.load(segments[1]);
      if (_disposed) {
        await _respond(request, HttpStatus.serviceUnavailable);
        return true;
      }
      if (resource == null) {
        await _respond(request, HttpStatus.notFound);
        return true;
      }
      file = File('${root.path}/overlay.html');
    } else if (segments.length > 2 && segments[1] == 'assets') {
      if (segments
          .skip(2)
          .any((segment) => segment == '..' || segment == '.')) {
        await _respond(request, HttpStatus.badRequest);
        return true;
      }
      try {
        file = await containedFile(root, segments.skip(1).toList());
      } on ArgumentError {
        await _respond(request, HttpStatus.badRequest);
        return true;
      }
    }
    if (file == null) return false;
    if (!await file.exists()) {
      await _respond(request, HttpStatus.notFound);
      return true;
    }
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = _contentType(file.path);
    await file.openRead().pipe(request.response);
    return true;
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

  bool _authorized(HttpRequest request, String overlayId) =>
      access.accepts(
        overlayId,
        request.headers.value('x-showrunner-overlay'),
      ) ||
      request.cookies.any(
        (cookie) =>
            cookie.name == OverlayAccessTokens.cookieName &&
            access.accepts(overlayId, cookie.value),
      );

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
        !_authorized(request, overlayId) ||
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
      await peer.call('overlays_setConfig', [_remoteConfig(resource)]);
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

  Future<bool> _serveMedia(HttpRequest request, List<String> segments) async {
    if (segments.length < 3) return false;
    final root = switch (segments[1]) {
      'default' => mediaRoot,
      'tts-cache' => ttsRoot,
      _ => null,
    };
    if (root == null ||
        segments.skip(2).any((segment) => segment == '..' || segment == '.')) {
      await _respond(request, HttpStatus.notFound);
      return true;
    }
    File file;
    try {
      file = await containedFile(root, segments.skip(2).toList());
    } on ArgumentError {
      await _respond(request, HttpStatus.badRequest);
      return true;
    }
    if (!await file.exists()) {
      await _respond(request, HttpStatus.notFound);
      return true;
    }
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = _contentType(file.path);
    await file.openRead().pipe(request.response);
    return true;
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
      await _send(peer, 'overlays_setConfig', [_remoteConfig(resource)]);
    }
  }

  Future<bool> playAudio(String overlayId, SoundPlayRequest request) async {
    final mediaFile = await _remoteMediaPath(request.file, overlayId);
    if (mediaFile == null) return false;
    final peers = _targetPeers(overlayId).toList();
    if (peers.isEmpty) return false;
    final playId = request.playId?.trim().isNotEmpty == true
        ? request.playId!.trim()
        : 'overlay-audio-${DateTime.now().microsecondsSinceEpoch}';
    final cancellation = Completer<void>();
    _audioCancellations[playId] = cancellation;
    try {
      await Future.wait(
        peers.map(
          (peer) => _send(peer, 'overlays_playAudio', [
            mediaFile,
            playId,
            request.startSec,
            request.endSec.isFinite ? request.endSec : null,
            request.volume,
          ]),
        ),
      );
      final duration = request.endSec.isFinite
          ? (request.endSec - request.startSec).clamp(0, double.infinity)
          : 0;
      if (duration > 0) {
        await Future.any<void>([
          Future<void>.delayed(
            Duration(milliseconds: (duration * 1000).round()),
          ),
          cancellation.future,
        ]);
      }
      return true;
    } finally {
      if (identical(_audioCancellations[playId], cancellation)) {
        _audioCancellations.remove(playId);
      }
    }
  }

  Future<void> cancelAudio(String overlayId, String playId) async {
    final cancellation = _audioCancellations[playId];
    if (cancellation != null && !cancellation.isCompleted) {
      cancellation.complete();
    }
    await Future.wait(
      _targetPeers(
        overlayId,
      ).map((peer) => _send(peer, 'overlays_cancelAudio', [playId])),
    );
  }

  Future<String?> _remoteMediaPath(String source, String overlayId) async {
    final file = File(source);
    if (!await file.exists()) return null;
    final absolutePath = file.absolute.path;
    final mediaRelative = _relativeTo(mediaRoot, absolutePath);
    if (mediaRelative != null) {
      return '/overlays/${Uri.encodeComponent(overlayId)}/media/default/$mediaRelative';
    }
    final ttsRelative = _relativeTo(ttsRoot, absolutePath);
    if (ttsRelative != null) {
      return '/overlays/${Uri.encodeComponent(overlayId)}/media/tts-cache/$ttsRelative';
    }
    return null;
  }

  String? _relativeTo(Directory? root, String filePath) {
    if (root == null) return null;
    final rootPath = Directory(root.path).absolute.path.replaceAll('\\', '/');
    final normalizedRoot = rootPath.toLowerCase().replaceFirst(
      RegExp(r'/+$'),
      '',
    );
    final normalizedFilePath = filePath.replaceAll('\\', '/');
    if (!normalizedFilePath.toLowerCase().startsWith('$normalizedRoot/')) {
      return null;
    }
    final relative = normalizedFilePath.substring(normalizedRoot.length + 1);
    if (relative.split(RegExp(r'[/\\]+')).any((part) => part == '..')) {
      return null;
    }
    return relative
        .split(RegExp(r'[/\\]+'))
        .where((part) => part.isNotEmpty)
        .map(Uri.encodeComponent)
        .join('/');
  }

  void registerAudioOutput(String overlayId) {
    final outputs = soundOutputs;
    if (outputs == null || outputs.find('overlay-audio.$overlayId') != null) {
      return;
    }
    outputs.register(
      CallbackSoundOutput(
        id: 'overlay-audio.$overlayId',
        player: (request) => playAudio(overlayId, request),
        aborter: (playId) => cancelAudio(overlayId, playId),
      ),
    );
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

JsonMap _remoteConfig(ResourceData resource) {
  final config = resource.config;
  final rawSize = config['size'];
  if (rawSize is! Map || config['widgets'] is! List) {
    throw const FormatException(
      'Overlay config must contain size and widgets fields.',
    );
  }
  final size = Map<String, dynamic>.from(rawSize);
  final width = (size['width'] as num?)?.toInt() ?? 1920;
  final height = (size['height'] as num?)?.toInt() ?? 1080;
  final widgets = (config['widgets'] as List)
      .whereType<Map>()
      .map((widget) => _remoteWidget(Map<String, dynamic>.from(widget)))
      .toList();
  return {
    'name': resource.name,
    'schemaVersion': 1,
    'size': {'width': width, 'height': height},
    'widgets': widgets,
  };
}

JsonMap _remoteWidget(JsonMap widget) {
  final size = widget['size'] is Map
      ? Map<String, dynamic>.from(widget['size'] as Map)
      : const <String, dynamic>{};
  final position = widget['position'] is Map
      ? Map<String, dynamic>.from(widget['position'] as Map)
      : const <String, dynamic>{};
  return {
    'id': widget['id']?.toString() ?? '',
    'plugin': widget['plugin']?.toString() ?? 'overlays',
    'widget': widget['widget']?.toString() ?? '',
    'name': widget['name']?.toString() ?? widget['widget']?.toString() ?? '',
    'size': {
      'width': (size['width'] as num?)?.toInt() ?? 100,
      'height': (size['height'] as num?)?.toInt() ?? 100,
    },
    'position': {
      'x': (position['x'] as num?)?.toDouble() ?? 0,
      'y': (position['y'] as num?)?.toDouble() ?? 0,
    },
    'config': widget['config'] is Map
        ? Map<String, dynamic>.from(widget['config'] as Map)
        : <String, dynamic>{},
    'locked': widget['locked'] == true,
    'visible': widget['visible'] != false,
  };
}

Directory? _discoverWebRoot() {
  final executableDirectory = File(Platform.resolvedExecutable).parent;
  final candidates = [
    Directory('${executableDirectory.path}/obs-overlay'),
    Directory('${Directory.current.path}/obs-overlay'),
    Directory(
      '${Directory.current.path}/../showrunner-obs-overlay/dist/obs-overlay',
    ),
  ];
  for (final candidate in candidates) {
    if (candidate.existsSync()) return candidate;
  }
  return null;
}

ContentType _contentType(String path) {
  return switch (path.toLowerCase().split('.').last) {
    'html' => ContentType.html,
    'css' => ContentType('text', 'css'),
    'js' => ContentType('application', 'javascript'),
    'json' => ContentType.json,
    'svg' => ContentType('image', 'svg+xml'),
    'png' => ContentType('image', 'png'),
    'jpg' || 'jpeg' => ContentType('image', 'jpeg'),
    'webp' => ContentType('image', 'webp'),
    'woff' => ContentType('font', 'woff'),
    'woff2' => ContentType('font', 'woff2'),
    _ => ContentType('application', 'octet-stream'),
  };
}

Future<void> _respond(HttpRequest request, int statusCode) async {
  request.response
    ..statusCode = statusCode
    ..headers.contentLength = 0;
  await request.response.close();
}
