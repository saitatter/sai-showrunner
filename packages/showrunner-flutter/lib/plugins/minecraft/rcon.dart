import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

typedef MinecraftRconRequest =
    Future<String> Function(
      String host,
      int port,
      String password,
      String command,
    );

final class MinecraftTransport {
  const MinecraftTransport(this.request);

  final MinecraftRconRequest request;
}

final class SocketMinecraftRconTransport {
  const SocketMinecraftRconTransport();

  Future<String> request(
    String host,
    int port,
    String password,
    String command,
  ) async {
    final socket = await Socket.connect(
      host,
      port,
      timeout: const Duration(seconds: 5),
    );
    final iterator = StreamIterator<int>(socket.expand((chunk) => chunk));
    try {
      await _send(socket, 1, 3, password);
      final auth = await _read(iterator);
      if (auth.id == -1) {
        throw StateError('Minecraft RCON authentication failed.');
      }

      await _send(socket, 2, 2, command);
      final response = await _read(iterator);
      return response.body;
    } finally {
      await iterator.cancel();
      await socket.close();
    }
  }
}

/// Keeps one authenticated RCON socket per configured connection.
///
/// RCON servers are long-lived connections in the desktop runtime. The
/// one-shot transport above remains available for isolated callers, while the
/// plugin owns this transport so sequential graph actions reuse the session.
final class PersistentMinecraftRconTransport {
  final Map<({String host, int port, String password}), _RconSession>
  _sessions = {};
  bool _closed = false;

  Future<String> request(
    String host,
    int port,
    String password,
    String command,
  ) async {
    if (_closed) throw StateError('Minecraft RCON transport is closed.');
    final key = (host: host, port: port, password: password);
    final session = _sessions.putIfAbsent(
      key,
      () => _RconSession(host: host, port: port, password: password),
    );
    try {
      return await session.send(command);
    } catch (_) {
      if (identical(_sessions[key], session)) _sessions.remove(key);
      await session.close();
      rethrow;
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final sessions = _sessions.values.toList();
    _sessions.clear();
    await Future.wait(sessions.map((session) => session.close()));
  }
}

final class _RconSession {
  _RconSession({
    required this.host,
    required this.port,
    required this.password,
  });

  final String host;
  final int port;
  final String password;
  Future<void> _queue = Future<void>.value();
  Socket? _socket;
  StreamIterator<int>? _iterator;
  int _nextId = 1;
  bool _closed = false;

  Future<String> send(String command) {
    if (_closed) throw StateError('Minecraft RCON session is closed.');
    final result = Completer<String>();
    _queue = _queue.then<void>((_) async {
      try {
        result.complete(await _sendCommand(command));
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }

  Future<String> _sendCommand(String command) async {
    await _connect();
    final socket = _socket!;
    final iterator = _iterator!;
    final commandId = _nextId++;
    await _send(socket, commandId, 2, command);
    final response = await _read(iterator);
    if (response.id != commandId) {
      throw StateError('Minecraft RCON response id did not match command.');
    }
    return response.body;
  }

  Future<void> _connect() async {
    if (_socket != null && _iterator != null) return;
    final socket = await Socket.connect(
      host,
      port,
      timeout: const Duration(seconds: 5),
    );
    _socket = socket;
    _iterator = StreamIterator<int>(socket.expand((chunk) => chunk));
    try {
      final authId = _nextId++;
      await _send(socket, authId, 3, password);
      final auth = await _read(_iterator!);
      if (auth.id == -1 || auth.id != authId) {
        throw StateError('Minecraft RCON authentication failed.');
      }
    } catch (_) {
      await close();
      rethrow;
    }
  }

  Future<void> close() async {
    _closed = true;
    final iterator = _iterator;
    final socket = _socket;
    _iterator = null;
    _socket = null;
    await iterator?.cancel();
    await socket?.close();
  }
}

final class _RconPacket {
  const _RconPacket({required this.id, required this.type, required this.body});

  final int id;
  final int type;
  final String body;
}

Future<void> _send(Socket socket, int id, int type, String body) async {
  final payload = utf8.encode(body);
  final packet = ByteData(4 + 4 + 4 + payload.length + 2);
  var offset = 0;
  packet.setInt32(offset, packet.lengthInBytes - 4, Endian.little);
  offset += 4;
  packet.setInt32(offset, id, Endian.little);
  offset += 4;
  packet.setInt32(offset, type, Endian.little);
  offset += 4;
  for (final byte in payload) {
    packet.setUint8(offset++, byte);
  }
  packet.setUint8(offset++, 0);
  packet.setUint8(offset, 0);
  socket.add(packet.buffer.asUint8List());
  await socket.flush();
}

Future<_RconPacket> _read(StreamIterator<int> iterator) async {
  final lengthBytes = await _readBytes(iterator, 4);
  final length = ByteData.sublistView(
    Uint8List.fromList(lengthBytes),
  ).getInt32(0, Endian.little);
  if (length < 10 || length > 1024 * 1024) {
    throw const FormatException('Invalid Minecraft RCON packet length.');
  }
  final body = await _readBytes(iterator, length);
  final data = ByteData.sublistView(Uint8List.fromList(body));
  final id = data.getInt32(0, Endian.little);
  final type = data.getInt32(4, Endian.little);
  final text = utf8.decode(body.sublist(8, body.length - 2));
  return _RconPacket(id: id, type: type, body: text);
}

Future<List<int>> _readBytes(StreamIterator<int> iterator, int length) async {
  final bytes = <int>[];
  while (bytes.length < length) {
    if (!await iterator.moveNext()) {
      throw const SocketException('Minecraft RCON connection closed.');
    }
    bytes.add(iterator.current);
  }
  return bytes;
}
