import 'dart:async';
import 'dart:io';
import '../../persistence/filesystem/safe_path.dart';
import '../../schema/resource.dart';
import 'manifest.dart';
import 'overlay_access.dart';
import 'overlay_peer.dart';

/// Owns authenticated socket admission, configuration and awaited peer teardown.
final class OverlayPeerManager {
  OverlayPeerManager({
    required this.overlayStore,
    required this.access,
    required this.onRequest,
    required this.onJoined,
    required this.configure,
    required this.onClosed,
    this.maxPeers = 32,
    this.maxMessageBytes = 1024 * 1024,
    this.requestTimeout = const Duration(seconds: 20),
  }) {
    if (maxPeers <= 0 ||
        maxMessageBytes <= 0 ||
        requestTimeout <= Duration.zero) {
      throw ArgumentError('Overlay peer limits must be positive.');
    }
  }
  final OverlayResourceStore overlayStore;
  final OverlayAccessTokens access;
  final int maxPeers, maxMessageBytes;
  final Duration requestTimeout;
  final Future<Object?> Function(OverlayPeer, String, List<dynamic>) onRequest;
  final void Function(OverlayPeer, ResourceData) onJoined;
  final Future<void> Function(OverlayPeer, ResourceData) configure;
  final void Function(OverlayPeer) onClosed;
  final _peers = <OverlayPeer>{};
  final _joins = <Future<bool>>{};
  final _serving = <Future<void>>{};
  bool _disposed = false;
  int _joining = 0;
  Future<void>? _closing;
  Iterable<OverlayPeer> get peers => List.unmodifiable(_peers);
  Iterable<OverlayPeer> targets(String id) =>
      peers.where((peer) => id.isEmpty || peer.overlayId == id);
  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    _disposed = true;
    final peers = _peers.toList();
    _peers.clear();
    await Future.wait(peers.map((peer) => peer.close()));
    await Future.wait(_joins.toList());
    await Future.wait(_serving.toList());
  }

  Future<bool> handle(HttpRequest request, WebSocket socket) {
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
      final peer = OverlayPeer(
        socket,
        overlayId: overlayId,
        maxMessageBytes: maxMessageBytes,
        requestTimeout: requestTimeout,
      );
      peer.onRequest = (name, args) => onRequest(peer, name, args);
      _peers.add(peer);
      final serving = _servePeer(peer, resource);
      _serving.add(serving);
      serving.then<void>(
        (_) {
          _serving.remove(serving);
        },
        onError: (Object _, StackTrace _) {
          _serving.remove(serving);
        },
      );
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
      onJoined(peer, resource);
      await configure(peer, resource).timeout(requestTimeout);
      await peer.done;
    } on TimeoutException {
      await peer.close(WebSocketStatus.policyViolation);
    } on Object {
      await peer.close();
    } finally {
      _peers.remove(peer);
      onClosed(peer);
    }
  }
}
