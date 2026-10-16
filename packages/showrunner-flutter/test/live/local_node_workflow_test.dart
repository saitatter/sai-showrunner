import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/http/manifest.dart';
import 'package:showrunner_flutter/plugins/discord/manifest.dart';
import 'package:showrunner_flutter/plugins/obs/actions.dart';
import 'package:showrunner_flutter/plugins/obs/transport.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/runtime/expression.dart';
import 'package:showrunner_flutter/runtime/graph_execution_engine.dart';
import 'package:showrunner_flutter/schema/automation.dart';
import 'package:showrunner_flutter/plugins/twitch/actions.dart';
import 'package:showrunner_flutter/plugins/variables/manifest.dart';
import 'package:showrunner_flutter/services/plugin_event_hub.dart';
import 'twitch_chat_fixture.dart';
import 'package:showrunner_flutter/plugins/remote/manifest.dart';

AutomationData _graph(
  String plugin,
  String action,
  Map<String, dynamic> config,
) => AutomationData(
  graph: AutomationGraph(
    entryNodeId: 'probe',
    nodes: [
      GraphNode(
        id: 'probe',
        x: 0,
        y: 0,
        type: 'action',
        data: {'plugin': plugin, 'action': action, 'config': config},
      ),
    ],
  ),
);

void main() {
  test(
    'real local remote buttons execute graphs once before and after restart',
    () async {
      final hub = DartPluginEventHub();
      final runtime = RemoteButtonRuntime(
        eventHub: hub,
        port: 0,
        loadButtonNames: () async => ['Start'],
      );
      final plugin = createRemotePlugin(eventHub: hub);
      final registry = DartPluginRegistry()
        ..register(plugin)
        ..register(createVariablesPlugin());
      addTearDown(registry.close);
      addTearDown(hub.dispose);
      addTearDown(runtime.stop);
      final results = <Future<void>>[];
      final trigger = plugin.triggers.single;
      final listener = trigger.listenFromRuntime().listen((event) {
        if (!trigger.matchesRuntime({'name': 'Start'}, event)) return;
        results.add(
          CompiledExecutionEngine()
              .executeWithRegistry(
                automation: _graph('variables', 'set', {
                  'variable': 'buttonProof',
                  'value': '{{name}}',
                }),
                context: EvaluationContext(locals: event),
                registry: registry,
              )
              .then((r) {
                expect(r.completed, true);
                expect(r.nodeResults['probe']?['value'], 'Start');
              }),
        );
      });
      addTearDown(listener.cancel);
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      for (var round = 0; round < 2; round++) {
        await runtime.start();
        final port = runtime.boundPort;
        await runtime.start();
        expect(runtime.boundPort, port);
        final list = await (await client.getUrl(
          Uri.parse('http://127.0.0.1:$port/buttons'),
        )).close();
        expect(jsonDecode(await utf8.decoder.bind(list).join()), {
          'buttons': ['Start'],
        });
        final missing = await (await client.postUrl(
          Uri.parse('http://127.0.0.1:$port/buttons/press'),
        )).close();
        expect(missing.statusCode, 404);
        await missing.drain<void>();
        await Future.wait(
          List.generate(3, (_) async {
            final response = await (await client.postUrl(
              Uri.parse('http://127.0.0.1:$port/buttons/press?button=Start'),
            )).close();
            expect(response.statusCode, 204);
            await response.drain<void>();
          }),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await Future.wait(results);
        expect(results, hasLength((round + 1) * 3));
        await runtime.stop();
        expect(runtime.boundPort, isNull);
      }
    },
  );
  test('typed Twitch chat triggers run the gated compiled graph', () async {
    final hub = DartPluginEventHub();
    final twitch = createTwitchPlugin(
      TwitchTransport((method, path, query, body) async => {}),
      eventHub: hub,
    );
    final registry = DartPluginRegistry()
      ..register(twitch)
      ..register(createVariablesPlugin());
    addTearDown(registry.close);
    addTearDown(hub.dispose);
    final trigger = twitch.triggers.firstWhere(
      (t) => t.triggerId.value == 'chat',
    );
    for (final message in ['showrunner-test', 'different-message']) {
      final eventFuture = trigger.listenFromRuntime().first;
      hub.emit('chat', {
        'viewerId': 'local-viewer',
        'message': message,
        'platform': 'twitch',
      });
      final event = await eventFuture;
      final result = await CompiledExecutionEngine().executeWithRegistry(
        automation: twitchChatProofGraph(),
        context: EvaluationContext(locals: Map<String, dynamic>.from(event)),
        registry: registry,
      );
      expect(result.completed, true);
      expect(
        result.nodeResults.containsKey('matched'),
        message == 'showrunner-test',
      );
      if (message == 'showrunner-test') {
        expect(result.nodeResults['matched']?['value'], message);
      }
    }
  });

  test(
    'Discord consumes streamed JSON before closing its HTTP client',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        await request.drain<void>();
        request.response.headers.contentType = ContentType.json;
        request.response.write('{"id":');
        await request.response.flush();
        await Future<void>.delayed(const Duration(milliseconds: 30));
        request.response.write('"local-message"}');
        await request.response.close();
      });
      final url = 'http://127.0.0.1:${server.port}/local-webhook';
      const transport = DiscordHttpTransport();
      expect(await transport.request(url, {'content': 'Local fixture'}), {
        'statusCode': 200,
        'body': '{"id":"local-message"}',
      });
      expect(
        await transport.requestWithFiles(url, {'content': 'Local fixture'}, []),
        {'statusCode': 200, 'body': '{"id":"local-message"}'},
      );
    },
  );
  test(
    'HTTP node executes a real local request through the production VM',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        expect(request.uri.path, '/node-proof');
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'ok': true, 'answer': 42}));
        await request.response.close();
      });
      final registry = DartPluginRegistry()..register(createHttpPlugin());
      addTearDown(registry.close);
      final result = await CompiledExecutionEngine().executeWithRegistry(
        automation: _graph('http', 'request', {
          'url': 'http://127.0.0.1:${server.port}/node-proof',
          'method': 'GET',
        }),
        context: EvaluationContext(),
        registry: registry,
      );
      expect(result.completed, isTrue);
      expect(result.nodeResults['probe'], {'ok': true, 'answer': 42});
    },
  );

  test(
    'OBS node completes a real local WebSocket identify and request round trip',
    () async {
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
        socket.add(
          jsonEncode({
            'op': 0,
            'd': {'obsWebSocketVersion': '5.5.0', 'rpcVersion': 1},
          }),
        );
        socket.listen((raw) {
          final message = jsonDecode(raw as String) as Map;
          if (message['op'] == 1) {
            socket.add(
              jsonEncode({
                'op': 2,
                'd': {'negotiatedRpcVersion': 1},
              }),
            );
          } else if (message['op'] == 6) {
            final data = message['d'] as Map;
            expect(data['requestType'], 'GetInputSettings');
            expect(data['requestData'], {'inputName': 'QA label'});
            socket.add(
              jsonEncode({
                'op': 7,
                'd': {
                  'requestId': data['requestId'],
                  'requestStatus': {'result': true, 'code': 100},
                  'responseData': {
                    'inputSettings': {'text': 'Local OBS proof'},
                    'inputKind': 'text_gdiplus_v2',
                  },
                },
              }),
            );
          }
        });
      });
      final transport = ObsWebSocketTransport(
        host: '127.0.0.1',
        port: server.port,
      );
      addTearDown(transport.close);
      final registry = DartPluginRegistry()
        ..register(createObsPlugin(transport));
      addTearDown(registry.close);
      final result = await CompiledExecutionEngine()
          .executeWithRegistry(
            automation: _graph('obs', 'getInputSettings', {
              'sourceName': 'QA label',
            }),
            context: EvaluationContext(),
            registry: registry,
          )
          .timeout(const Duration(seconds: 5));
      expect(result.completed, isTrue);
      expect(
        result.nodeResults['probe'],
        containsPair('inputSettings', {'text': 'Local OBS proof'}),
      );
    },
  );
}
