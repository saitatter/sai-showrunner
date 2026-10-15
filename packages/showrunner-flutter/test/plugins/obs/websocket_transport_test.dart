import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/obs/transport.dart';

void main() {
  Future<HttpServer> server(void Function(WebSocket socket) handle) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final sockets = <WebSocket>[];
    addTearDown(() async {
      for (final socket in sockets) {
        await socket.close();
      }
      await server.close(force: true);
    });
    server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      sockets.add(socket);
      handle(socket);
    });
    return server;
  }

  void reply(WebSocket socket, Map data) => socket.add(
    jsonEncode({
      'op': 7,
      'd': {
        'requestId': data['requestId'],
        'requestStatus': {'result': true, 'code': 100},
        'responseData': {'request': data['requestType']},
      },
    }),
  );

  test(
    'authenticates once and waits for Identified before concurrent requests',
    () async {
      var connections = 0;
      var identified = false;
      final endpoint = await server((socket) {
        connections++;
        socket.add(
          jsonEncode({
            'op': 0,
            'd': {
              'rpcVersion': 1,
              'authentication': {'salt': 'salt', 'challenge': 'challenge'},
            },
          }),
        );
        socket.listen((raw) async {
          final message = jsonDecode(raw as String) as Map;
          final data = message['d'] as Map;
          if (message['op'] == 1) {
            final secret = base64Encode(
              sha256.convert(utf8.encode('passwordsalt')).bytes,
            );
            final auth = base64Encode(
              sha256.convert(utf8.encode('${secret}challenge')).bytes,
            );
            expect(data['authentication'], auth);
            await Future<void>.delayed(const Duration(milliseconds: 30));
            identified = true;
            socket.add(
              jsonEncode({
                'op': 2,
                'd': {'negotiatedRpcVersion': 1},
              }),
            );
          } else if (message['op'] == 6) {
            expect(identified, isTrue);
            reply(socket, data);
          }
        });
      });
      final transport = ObsWebSocketTransport(
        host: '127.0.0.1',
        port: endpoint.port,
        password: 'password',
      );
      addTearDown(transport.close);
      final result = await Future.wait([
        transport.call('GetVersion', {}),
        transport.call('GetSceneList', {}),
      ]);
      expect(connections, 1);
      expect(result, [
        {'request': 'GetVersion'},
        {'request': 'GetSceneList'},
      ]);
    },
  );

  test(
    'rejected identification stays disconnected and permits reconnect',
    () async {
      var connections = 0;
      final connected = <bool>[];
      final endpoint = await server((socket) {
        connections++;
        final reject = connections == 1;
        socket.add(
          jsonEncode({
            'op': 0,
            'd': {'rpcVersion': 1},
          }),
        );
        socket.listen((raw) {
          final message = jsonDecode(raw as String) as Map;
          if (message['op'] == 1) {
            if (reject) {
              socket.close(4009, 'Authentication failed');
            } else {
              socket.add(jsonEncode({'op': 2, 'd': {}}));
            }
          } else if (message['op'] == 6) {
            reply(socket, message['d'] as Map);
          }
        });
      });
      final transport = ObsWebSocketTransport(
        host: '127.0.0.1',
        port: endpoint.port,
        onStateChanged: (state, value) {
          if (state == 'connected') connected.add(value as bool);
        },
      );
      addTearDown(transport.close);
      await expectLater(transport.call('GetVersion', {}), throwsStateError);
      expect(connected, isNot(contains(true)));
      expect(await transport.call('GetVersion', {}), {'request': 'GetVersion'});
      expect(connections, 2);
    },
  );

  test(
    'request timeout releases pending work without breaking the connection',
    () async {
      final endpoint = await server((socket) {
        socket.add(
          jsonEncode({
            'op': 0,
            'd': {'rpcVersion': 1},
          }),
        );
        socket.listen((raw) {
          final message = jsonDecode(raw as String) as Map;
          if (message['op'] == 1) {
            socket.add(jsonEncode({'op': 2, 'd': {}}));
          } else if (message['op'] == 6 &&
              message['d']['requestType'] != 'Ignored') {
            reply(socket, message['d'] as Map);
          }
        });
      });
      final transport = ObsWebSocketTransport(
        host: '127.0.0.1',
        port: endpoint.port,
        requestTimeout: const Duration(milliseconds: 50),
      );
      addTearDown(transport.close);
      await expectLater(
        transport.call('Ignored', {}),
        throwsA(isA<TimeoutException>()),
      );
      expect(await transport.call('GetVersion', {}), {'request': 'GetVersion'});
    },
  );
}
