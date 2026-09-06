import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../persistence/viewer_data_repository.dart';
import '../../schema/automation.dart';
import '../../schema/resource.dart';
import '../../schema/viewer_data.dart';
import '../../runtime/expression.dart';
import '../../services/plugin_event_hub.dart';
import '../http/manifest.dart';
import '../registry/plugin_registry.dart';
import '../sound/output.dart';
import 'manifest.dart';

/// Bridges the Flutter runtime to the browser/WebGL overlay.
///
/// The browser renderer remains in `packages/showrunner-obs-overlay`; this
/// service owns the desktop-side HTTP resources and WebSocket RPC lifecycle.
final class DartOverlayWebSocketService {
  DartOverlayWebSocketService({
    required this.server,
    required this.eventHub,
    required this.overlayStore,
    required this.registry,
    required this.viewerDataRepository,
    this.soundOutputs,
    this.mediaRoot,
    this.ttsRoot,
    Directory? webRoot,
  }) : webRoot = webRoot ?? _discoverWebRoot() {
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
  final Directory? webRoot;
  late final List<StreamSubscription<RuntimeMap>> _subscriptions;
  final _peers = <_OverlayPeer>{};
  final _audioCancellations = <String, Completer<void>>{};
  bool _disposed = false;

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    registry.removeListener(_broadcastStates);
    server.removeRequestHandler(_handleHttpRequest);
    server.removeWebSocketHandler(_handleWebSocket);
    await Future.wait(
      _subscriptions.map((subscription) => subscription.cancel()),
    );
    final peers = List<_OverlayPeer>.of(_peers);
    _peers.clear();
    for (final cancellation in _audioCancellations.values) {
      if (!cancellation.isCompleted) cancellation.complete();
    }
    _audioCancellations.clear();
    await Future.wait(peers.map((peer) => peer.close()));
  }

  Future<bool> _handleHttpRequest(HttpRequest request) async {
    if (request.method.toUpperCase() != 'GET') return false;
    final segments = request.uri.pathSegments;
    if (segments.isEmpty) return false;

    if (segments.first == 'media') {
      return _serveMedia(request, segments);
    }
    if (segments.first != 'overlays') return false;

    if (segments.length == 3 && segments[2] == 'config') {
      final resource = await overlayStore.load(segments[1]);
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
      file = File('${root.path}/${segments.skip(1).join('/')}');
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

  Future<bool> _handleWebSocket(HttpRequest request, WebSocket socket) async {
    final overlayId = request.uri.queryParameters['overlay']?.trim() ?? '';
    if (overlayId.isEmpty) return false;
    final resource = await overlayStore.load(overlayId);
    if (resource == null) {
      await socket.close(WebSocketStatus.normalClosure);
      return true;
    }
    registerAudioOutput(resource.id);
    final peer = _OverlayPeer(socket);
    peer.overlayId = overlayId;
    peer.onRequest = (name, args) => _handlePeerRequest(peer, name, args);
    _peers.add(peer);
    unawaited(_servePeer(peer, resource));
    return true;
  }

  Future<void> _servePeer(_OverlayPeer peer, ResourceData resource) async {
    try {
      await peer.call('overlays_setConfig', [_remoteConfig(resource)]);
      await peer.done;
    } catch (_) {
      await peer.close();
    } finally {
      _peers.remove(peer);
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
    final file = File('${root.path}/${segments.skip(2).join('/')}');
    final rootPath = Directory(root.path).absolute.path.toLowerCase();
    final filePath = file.absolute.path.toLowerCase();
    if (!filePath.startsWith('$rootPath${Platform.pathSeparator}')) {
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

  Iterable<_OverlayPeer> _targetPeers(String overlayId) sync* {
    for (final peer in List<_OverlayPeer>.of(_peers)) {
      if (overlayId.isEmpty || peer.overlayId == overlayId) yield peer;
    }
  }

  void _publishConfig(RuntimeMap event) {
    final overlayId = event['overlayId']?.toString().trim() ?? '';
    if (overlayId.isEmpty) return;
    unawaited(_reloadConfig(overlayId));
  }

  Future<void> _reloadConfig(String overlayId) async {
    final resource = await overlayStore.load(overlayId);
    if (resource == null) return;
    for (final peer in _targetPeers(overlayId)) {
      await _send(peer, 'overlays_setConfig', [_remoteConfig(resource)]);
    }
  }

  Future<bool> playAudio(String overlayId, SoundPlayRequest request) async {
    final mediaFile = await _remoteMediaPath(request.file);
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

  Future<String?> _remoteMediaPath(String source) async {
    final file = File(source);
    if (!await file.exists()) return null;
    final absolutePath = file.absolute.path;
    final mediaRelative = _relativeTo(mediaRoot, absolutePath);
    if (mediaRelative != null) return '/media/default/$mediaRelative';
    final ttsRelative = _relativeTo(ttsRoot, absolutePath);
    if (ttsRelative != null) return '/media/tts-cache/$ttsRelative';
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
    for (final peer in List<_OverlayPeer>.of(_peers)) {
      if (!peer.observingViewerData) continue;
      final provider = event['provider']?.toString() ?? '';
      final id = event['id']?.toString() ?? '';
      if (provider.isEmpty || id.isEmpty) continue;
      if (eventId == 'viewerDataAdded') {
        unawaited(
          _send(peer, 'overlays_onNewViewerData', [provider, id, event]),
        );
        continue;
      }
      final variable = event['variable']?.toString() ?? '';
      if (variable.isNotEmpty) {
        unawaited(
          _send(peer, 'overlays_onViewerDataChanged', [
            provider,
            id,
            variable,
            event['value'],
          ]),
        );
        continue;
      }
      final values = event['values'];
      if (values is Map) {
        for (final entry in values.entries) {
          unawaited(
            _send(peer, 'overlays_onViewerDataChanged', [
              provider,
              id,
              entry.key.toString(),
              entry.value,
            ]),
          );
        }
      }
    }
  }

  void _broadcastStates() {
    for (final peer in List<_OverlayPeer>.of(_peers)) {
      for (final key in peer.acquiredStates) {
        final separator = key.indexOf('\u0000');
        if (separator < 0) continue;
        final plugin = key.substring(0, separator);
        final state = key.substring(separator + 1);
        unawaited(
          _send(peer, 'overlays_stateUpdate', [
            plugin,
            state,
            registry.stateValues(plugin)[state],
          ]),
        );
      }
    }
  }

  Future<Object?> _handlePeerRequest(
    _OverlayPeer peer,
    String name,
    List<dynamic> args,
  ) async {
    switch (name) {
      case 'overlays_acquireState':
        if (args.length < 2) return null;
        final plugin = args[0].toString();
        final state = args[1].toString();
        peer.acquiredStates.add('$plugin\u0000$state');
        await _send(peer, 'overlays_stateUpdate', [
          plugin,
          state,
          registry.stateValues(plugin)[state],
        ]);
        return null;
      case 'overlays_freeState':
        if (args.length >= 2) {
          peer.acquiredStates.remove('${args[0]}\u0000${args[1]}');
        }
        return null;
      case 'overlays_widgetRPC':
        if (args.length < 2) return null;
        eventHub.emit(OverlayEventIds.widgetRpc, {
          'overlayId': peer.overlayId,
          'widgetId': args[1],
          'rpcId': args[0],
          'args': args.skip(2).toList(),
        });
        return null;
      case 'overlays_observeViewerData':
        peer.observingViewerData = true;
        return null;
      case 'overlays_unobserveViewerData':
        peer.observingViewerData = false;
        return null;
      case 'overlays_queryViewerData':
        return _queryViewerData(args);
      case 'overlays_getViewerVariables':
        return _viewerVariableSchemas();
      default:
        return null;
    }
  }

  Future<List<JsonMap>> _queryViewerData(List<dynamic> args) async {
    final start = _integer(args.elementAtOrNull(0), 0).clamp(0, 1 << 30);
    final end = _integer(
      args.elementAtOrNull(1),
      start + 100,
    ).clamp(start, 1 << 30);
    final sortBy = args.elementAtOrNull(2)?.toString() ?? 'id';
    final descending = _integer(args.elementAtOrNull(3), 1) < 0;
    final rows = <ViewerDataRow>[
      ...await viewerDataRepository.queryViewers('twitch'),
      ...await viewerDataRepository.queryViewers('youtube'),
    ];
    rows.sort((left, right) {
      final leftValue = _viewerSortValue(left, sortBy);
      final rightValue = _viewerSortValue(right, sortBy);
      final result = leftValue.compareTo(rightValue);
      return descending ? -result : result;
    });
    final from = start.clamp(0, rows.length).toInt();
    final to = end.clamp(from, rows.length).toInt();
    return rows.sublist(from, to).map((row) => row.toJson()).toList();
  }

  Future<List<JsonMap>> _viewerVariableSchemas() async {
    final definitions = await viewerDataRepository.loadDefinitions();
    return [
      for (final definition in definitions)
        {
          'name': definition.name,
          'type': _ipcType(definition.normalizedType),
          if (definition.normalizedType == 'object')
            'properties': <String, dynamic>{},
          if (definition.normalizedType == 'list')
            'items': <String, dynamic>{'type': 'String'},
          if (definition.defaultValue != null)
            'default': definition.defaultValue,
          'required': definition.required,
        },
    ];
  }

  Future<void> _send(_OverlayPeer peer, String name, List<dynamic> args) async {
    try {
      await peer.call(name, args);
    } on Object {
      // A browser source can disappear during a reconnect; event delivery is
      // best effort and must not affect the automation runtime.
    }
  }
}

final class _OverlayPeer {
  _OverlayPeer(this.socket) {
    _subscription = socket.listen(
      (data) => unawaited(_receive(data)),
      onError: (_, _) => _finish(),
      onDone: _finish,
      cancelOnError: false,
    );
  }

  final WebSocket socket;
  late final StreamSubscription<dynamic> _subscription;
  final _pending = <String, Completer<Object?>>{};
  final acquiredStates = <String>{};
  final doneCompleter = Completer<void>();
  var _nextRequest = 0;
  var _closed = false;
  String overlayId = '';
  bool observingViewerData = false;
  Future<Object?> Function(String, List<dynamic>)? onRequest;

  Future<void> get done => doneCompleter.future;

  Future<Object?> call(String name, List<dynamic> args) {
    if (_closed) {
      return Future.error(StateError('Overlay WebSocket is closed.'));
    }
    final requestId = 'flutter-overlay-${_nextRequest++}';
    final completer = Completer<Object?>();
    _pending[requestId] = completer;
    socket.add(
      jsonEncode({'requestId': requestId, 'name': name, 'args': args}),
    );
    return completer.future;
  }

  Future<void> close() async {
    if (!_closed) await socket.close(WebSocketStatus.normalClosure);
    await done;
  }

  Future<void> _receive(dynamic data) async {
    if (data is! String) return;
    final decoded = jsonDecode(data);
    if (decoded is! Map) return;
    final message = Map<String, dynamic>.from(decoded);
    final responseId = message['responseId']?.toString();
    if (responseId != null) {
      final completer = _pending.remove(responseId);
      if (completer == null) return;
      if (message.containsKey('failed')) {
        completer.completeError(StateError('Overlay RPC failed.'));
      } else {
        completer.complete(message['result']);
      }
      return;
    }
    final requestId = message['requestId']?.toString();
    final name = message['name']?.toString();
    if (requestId == null || name == null) return;
    final args = message['args'] is List
        ? List<dynamic>.from(message['args'] as List)
        : <dynamic>[];
    try {
      final result = await onRequest?.call(name, args);
      socket.add(jsonEncode({'responseId': requestId, 'result': result}));
    } on Object {
      socket.add(jsonEncode({'responseId': requestId, 'failed': true}));
    }
  }

  void _finish() {
    if (_closed) return;
    _closed = true;
    for (final completer in _pending.values) {
      completer.completeError(StateError('Overlay WebSocket closed.'));
    }
    _pending.clear();
    if (!doneCompleter.isCompleted) doneCompleter.complete();
    unawaited(_subscription.cancel());
  }
}

JsonMap _remoteConfig(ResourceData resource) {
  final config = resource.config;
  final rawSize = config['size'];
  final size = rawSize is Map
      ? Map<String, dynamic>.from(rawSize)
      : <String, dynamic>{};
  final width =
      (size['width'] as num?)?.toInt() ??
      (config['width'] as num?)?.toInt() ??
      1920;
  final height =
      (size['height'] as num?)?.toInt() ??
      (config['height'] as num?)?.toInt() ??
      1080;
  final widgets = config['widgets'] is List
      ? (config['widgets'] as List)
            .whereType<Map>()
            .map((widget) => _remoteWidget(Map<String, dynamic>.from(widget)))
            .toList()
      : <JsonMap>[];
  return {
    'name': resource.name,
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

String _ipcType(String type) => switch (type) {
  'number' => 'Number',
  'boolean' => 'Boolean',
  'object' || 'json' => 'Object',
  'list' => 'Array',
  'color' => 'Color',
  'lightcolor' => 'LightColor',
  'twitchviewer' => 'TwitchViewer',
  _ => 'String',
};

int _integer(Object? value, int fallback) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? fallback;

String _viewerSortValue(ViewerDataRow row, String sortBy) {
  if (sortBy == 'id') return row.viewer.id;
  if (sortBy == 'name' || sortBy == 'displayName') {
    return row.viewer.displayName;
  }
  return '${row.values[sortBy] ?? ''}';
}
