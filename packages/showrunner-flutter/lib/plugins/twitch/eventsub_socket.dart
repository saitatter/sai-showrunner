import 'dart:io';

typedef EventSubSocketFactory = Future<EventSubSocket> Function(Uri uri);

abstract interface class EventSubSocket {
  Stream<dynamic> get messages;

  Future<void> close([int? code, String? reason]);
}

final class WebSocketEventSubSocket implements EventSubSocket {
  const WebSocketEventSubSocket(this.socket);

  final WebSocket socket;

  @override
  Stream<dynamic> get messages => socket;

  @override
  Future<void> close([int? code, String? reason]) => socket.close(code, reason);
}

Future<EventSubSocket> connectEventSubSocket(Uri uri) async =>
    WebSocketEventSubSocket(await WebSocket.connect(uri.toString()));
