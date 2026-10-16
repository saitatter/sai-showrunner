import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';
import 'package:showrunner_flutter/persistence/resource_repository.dart';
import 'package:showrunner_flutter/persistence/viewer_data_repository.dart';
import 'package:showrunner_flutter/plugins/http/manifest.dart';
import 'package:showrunner_flutter/plugins/obs/transport.dart';
import 'package:showrunner_flutter/plugins/overlays/manifest.dart';
import 'package:showrunner_flutter/plugins/overlays/websocket_bridge.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/plugins/twitch/actions.dart';
import 'package:showrunner_flutter/plugins/twitch/event_worker.dart';
import 'package:showrunner_flutter/plugins/variables/manifest.dart';
import 'package:showrunner_flutter/runtime/expression.dart';
import 'package:showrunner_flutter/runtime/graph_execution_engine.dart';
import 'package:showrunner_flutter/schema/automation.dart';
import 'package:showrunner_flutter/schema/resource.dart';
import 'package:showrunner_flutter/services/http_provider_transports.dart';
import 'package:showrunner_flutter/services/plugin_event_hub.dart';
import 'twitch_chat_fixture.dart';

AutomationData _overlayChatGraph(String overlayId) {
  final base = twitchChatProofGraph().graph;
  return AutomationData(
    graph: AutomationGraph(
      entryNodeId: base.entryNodeId,
      nodes: [
        ...base.nodes,
        GraphNode(
          id: 'overlay-chat',
          type: 'action',
          x: 600,
          y: 0,
          data: {
            'plugin': 'overlays',
            'action': 'pushChatMessage',
            'config': {
              'targetWidget': {'widgetId': 'chat', 'overlayId': overlayId},
              'messageId': '{{messageId}}',
              'platform': 'twitch',
              'viewerName': '{{viewerName}}',
              'message': '{{message}}',
            },
          },
        ),
      ],
      edges: [
        ...base.edges,
        const GraphEdge(id: 'publish', from: 'matched', to: 'overlay-chat'),
      ],
    ),
  );
}

void main() {
  final configPath = Platform.environment['SHOWRUNNER_LIVE_CONFIG'];
  test(
    'Twitch chat renders through the graph and real overlay in portable OBS',
    () async {
      // Check the listening process before opening any OBS connection. The main
      // OBS profile and its port are never used by this fixture.
      final owner = await Process.run('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        r'$qaSocket=Get-NetTCPConnection -LocalPort 4456 -State Listen -ErrorAction Stop | Select-Object -First 1; (Get-Process -Id $qaSocket.OwningProcess).Path',
      ]);
      final expectedExe = File(
        '.tmp/obs-portable/bin/64bit/obs64.exe',
      ).absolute.path.toLowerCase().replaceAll('\\', '/');
      if (owner.exitCode != 0 ||
          '${owner.stdout}'.trim().toLowerCase().replaceAll('\\', '/') !=
              expectedExe) {
        fail(
          'Port 4456 must belong to the workspace portable OBS executable. Main OBS will not be used.',
        );
      }
      Map yaml;
      try {
        yaml = loadYaml(await File(configPath!).readAsString()) as Map;
      } catch (_) {
        fail('Cannot read private live YAML; values omitted.');
      }
      String resolve(Object? value) {
        final s = value?.toString() ?? '';
        return s.startsWith('env:')
            ? Platform.environment[s.substring(4)] ?? ''
            : s;
      }

      final obsSettings = yaml['plugin_settings']['obs'] as Map;
      final twitchSettings = yaml['plugin_settings']['twitch'] as Map;
      if ('${obsSettings['port']}' != '4456') {
        fail('Use portable OBS port 4456 in the live YAML.');
      }
      final obs = ObsWebSocketTransport(
        host: '127.0.0.1',
        port: 4456,
        password: resolve(obsSettings['password']),
      );
      final root = await Directory(
        '.tmp/chat-overlay-proof-${DateTime.now().millisecondsSinceEpoch}',
      ).create(recursive: true);
      final overlayId = 'chat-proof-${DateTime.now().millisecondsSinceEpoch}';
      final scene = 'ShowRunner Chat Proof $overlayId';
      final browser = '$scene Browser';
      final report = <String, Object?>{'portableObsVerified': true};
      final repository = ResourceRepository(Directory('${root.path}/overlays'));
      final store = OverlayResourceStore(
        load: repository.load,
        save: repository.save,
      );
      await repository.save(
        ResourceData(
          id: overlayId,
          config: {
            'name': 'Twitch chat proof',
            'size': {'width': 640, 'height': 360},
            'widgets': [
              {
                'id': 'title',
                'plugin': 'overlays',
                'widget': 'label',
                'name': 'Proof title',
                'position': {'x': 20, 'y': 15},
                'size': {'width': 600, 'height': 70},
                'config': {
                  'message': 'TWITCH → GRAPH → OVERLAY → OBS',
                  'font': {
                    'fontSize': 24,
                    'fontFamily': 'Arial',
                    'fontColor': '#FFFFFF',
                    'fontWeight': 700,
                  },
                },
              },
              {
                'id': 'chat',
                'plugin': 'overlays',
                'widget': 'chatFeed',
                'name': 'Live chat',
                'position': {'x': 20, 'y': 95},
                'size': {'width': 600, 'height': 240},
                'config': {
                  'fontFamily': 'Arial',
                  'fontSize': 30,
                  'maxMessages': 3,
                  'fadeTime': 0,
                  'backgroundColor': '#15334B',
                  'backgroundOpacity': 1,
                  'orientation': 'vertical',
                  'showBadges': false,
                },
              },
            ],
          },
        ),
      );
      final hub = DartPluginEventHub();
      final twitch = createTwitchPlugin(
        TwitchTransport((method, path, query, body) async {
          throw StateError(
            'This proof does not send messages or modify Twitch.',
          );
        }),
        eventHub: hub,
      );
      final registry = DartPluginRegistry()
        ..register(twitch)
        ..register(createVariablesPlugin())
        ..register(createOverlaysPlugin(eventHub: hub, overlayStore: store));
      final server = DartHttpEndpointService(host: '127.0.0.1', port: 0);
      await server.start();
      final bridge = DartOverlayWebSocketService(
        server: server,
        eventHub: hub,
        overlayStore: store,
        registry: registry,
        viewerDataRepository: InMemoryViewerDataRepository(),
      );
      final token = resolve(twitchSettings['accessToken']);
      final clientId = resolve(twitchSettings['clientId']);
      final transport = JsonHttpTransport(
        baseUrl: 'https://api.twitch.tv',
        accessToken: token,
        headers: {'Client-Id': clientId},
      );
      final worker = TwitchEventSubWorker(
        accessToken: token,
        clientId: clientId,
        broadcasterId: resolve(twitchSettings['broadcasterId']),
        request: transport.request,
        eventHub: hub,
        subscriptionTypes: const ['channel.chat.message'],
        ignoreSubscriptionErrors: false,
      );
      final message = Completer<RuntimeMap>();
      final trigger = twitch.triggers.firstWhere(
        (t) => t.triggerId.value == 'chat',
      );
      final listener = trigger.listenFromRuntime().listen((event) {
        if (event['message'] == 'showrunner-test' && !message.isCompleted) {
          message.complete(event);
        }
      });
      final originalScene = (await obs.call(
        'GetCurrentProgramScene',
        {},
      ))['currentProgramSceneName'];
      var created = false;
      Future<void> screenshot(String name) async {
        await obs.call('SaveSourceScreenshot', {
          'sourceName': browser,
          'imageFormat': 'png',
          'imageFilePath': '${root.absolute.path}/$name.png',
          'imageWidth': 640,
          'imageHeight': 360,
        });
      }

      try {
        await obs.call('CreateScene', {'sceneName': scene});
        created = true;
        await obs.call('CreateInput', {
          'sceneName': scene,
          'inputName': browser,
          'inputKind': 'browser_source',
          'inputSettings': {
            'url': bridge.browserSourceUrl(overlayId),
            'width': 640,
            'height': 360,
            'shutdown': false,
            'restart_when_active': false,
          },
          'sceneItemEnabled': true,
        });
        await obs.call('SetCurrentProgramScene', {'sceneName': scene});
        for (var i = 0; i < 100; i++) {
          if ((await bridge.getPresence(overlayId)).connected) break;
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        expect(
          (await bridge.getPresence(overlayId)).connected,
          true,
          reason:
              'Actual OBS browser must connect to the production overlay bridge.',
        );
        await Future<void>.delayed(const Duration(seconds: 2));
        await screenshot('before');
        final before = sha256
            .convert(await File('${root.path}/before.png').readAsBytes())
            .toString();
        report['obsBrowserConnected'] = true;
        RuntimeMap event;
        if (Platform.environment['SHOWRUNNER_CHAT_OVERLAY_DRY_RUN'] == '1') {
          report['source'] = 'local fixture';
          event = {
            'message': 'showrunner-test',
            'viewerName': 'LOCAL PRECHECK',
            'messageId': 'local-proof',
          };
        } else {
          await worker.start().timeout(const Duration(seconds: 30));
          stdout.writeln(
            'READY: send showrunner-test in your Twitch chat. Portable OBS browser is connected and before.png is captured.',
          );
          event = await message.future.timeout(const Duration(minutes: 4));
          report['source'] = 'live Twitch EventSub';
        }
        final result = await CompiledExecutionEngine().executeWithRegistry(
          automation: _overlayChatGraph(overlayId),
          context: EvaluationContext(locals: Map<String, dynamic>.from(event)),
          registry: registry,
        );
        expect(result.completed, true);
        expect(result.nodeResults['matched']?['value'], 'showrunner-test');
        expect(result.nodeResults['overlay-chat']?['sent'], true);
        var changed = false;
        for (var i = 0; i < 30; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          await screenshot('after');
          if (sha256
                  .convert(await File('${root.path}/after.png').readAsBytes())
                  .toString() !=
              before) {
            changed = true;
            break;
          }
        }
        expect(
          changed,
          true,
          reason:
              'The real OBS browser screenshot must change after the graph publishes the chat event.',
        );
        report['compiledGraph'] = 'PASS';
        report['obsScreenshotChanged'] = 'PASS';
        stdout.writeln(
          'PASS ${report['source']}: typed trigger -> graph -> overlay broadcast -> production browser renderer -> changed OBS screenshot.',
        );
        stdout.writeln(
          'Screenshots: ${root.absolute.path}/before.png and after.png',
        );
      } finally {
        await worker.stop();
        await listener.cancel();
        if (created) {
          await obs.call('SetCurrentProgramScene', {
            'sceneName': originalScene,
          });
          await obs.call('RemoveScene', {'sceneName': scene});
        }
        await obs.close();
        await bridge.dispose();
        await server.stop();
        await registry.close();
        await hub.dispose();
        await File(
          '${root.path}/report.json',
        ).writeAsString(const JsonEncoder.withIndent('  ').convert(report));
        stdout.writeln('Report: ${root.absolute.path}/report.json');
      }
    },
    skip:
        configPath == null ||
        Platform.environment['SHOWRUNNER_TWITCH_OVERLAY_OBS'] != '1',
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
