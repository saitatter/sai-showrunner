// Opt-in live mutations on the owner's channel and an explicitly selected test
// account. Every moderation change is removed in finally; existing bans abort.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';
import 'package:showrunner_flutter/plugins/twitch/actions.dart';
import 'package:showrunner_flutter/plugins/twitch/event_worker.dart';
import 'package:showrunner_flutter/plugins/variables/manifest.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/runtime/expression.dart';
import 'package:showrunner_flutter/graph/runtime/graph_execution_engine.dart';
import '../support/graph_fixtures.dart';
import 'package:showrunner_flutter/services/http_provider_transports.dart';
import 'package:showrunner_flutter/services/plugin_event_hub.dart';

void main() {
  final configPath = Platform.environment['SHOWRUNNER_LIVE_CONFIG'];
  final targetLogin = Platform.environment['SHOWRUNNER_TWITCH_TEST_ACCOUNT'];
  test(
    'live chat sends, reconnect, burst graphs and reversible moderation',
    () async {
      final yaml = loadYaml(await File(configPath!).readAsString()) as Map;
      final settings = yaml['plugin_settings']['twitch'] as Map;
      String value(String key) {
        final v = '${settings[key] ?? ''}';
        return v.startsWith('env:')
            ? Platform.environment[v.substring(4)] ?? ''
            : v;
      }

      final channel = value('broadcasterId');
      final token = value('accessToken');
      final client = value('clientId');
      final http = JsonHttpTransport(
        baseUrl: 'https://api.twitch.tv',
        accessToken: token,
        headers: {'Client-Id': client},
      );
      final directory = await Directory(
        '.tmp/twitch-stability-${DateTime.now().millisecondsSinceEpoch}',
      ).create(recursive: true);
      final report = <String, Object?>{};
      final hub = DartPluginEventHub();
      final registry = DartPluginRegistry()
        ..register(
          createTwitchPlugin(
            TwitchTransport.withDefaults(
              http.request,
              broadcasterId: channel,
              moderatorId: channel,
            ),
            eventHub: hub,
          ),
        )
        ..register(createVariablesPlugin());
      final sockets = <EventSubSocket>[];
      final worker = TwitchEventSubWorker(
        accessToken: token,
        clientId: client,
        broadcasterId: channel,
        request: http.request,
        eventHub: hub,
        subscriptions: [
          TwitchEventSubSubscription(
            type: 'channel.chat.message',
            version: '1',
            condition: {'broadcaster_user_id': channel, 'user_id': channel},
          ),
          TwitchEventSubSubscription(
            type: 'channel.ban',
            version: '1',
            condition: {'broadcaster_user_id': channel},
          ),
        ],
        ignoreSubscriptionErrors: false,
        socketFactory: (uri) async {
          final socket = WebSocketEventSubSocket(
            await WebSocket.connect('$uri'),
          );
          sockets.add(socket);
          return socket;
        },
      );
      final received = <RuntimeMap>[];
      final completed = <String>[];
      final executions = <Future<void>>[];
      final nonce = 'showrunner-qa-${DateTime.now().millisecondsSinceEpoch}';
      final listener = hub.stream('chat').listen((event) {
        if ('${event['message']}'.startsWith(nonce)) {
          received.add(event);
          executions.add(
            CompiledExecutionEngine()
                .executeWithRegistry(
                  automation: _graph('variables', 'set', {
                    'variable': 'proof',
                    'value': '{{message}}',
                  }),
                  context: EvaluationContext(
                    locals: Map<String, dynamic>.from(event),
                  ),
                  registry: registry,
                )
                .then((result) {
                  expect(result.completed, true);
                  completed.add('${event['message']}');
                }),
          );
        }
      });
      Future<RuntimeMap> action(String id, RuntimeMap config) async {
        final result = await CompiledExecutionEngine().executeWithRegistry(
          automation: _graph('twitch', id, config),
          context: EvaluationContext(),
          registry: registry,
        );
        expect(result.completed, true);
        return Map<String, dynamic>.from(result.nodeResults['action'] as Map);
      }

      String? targetId;
      var needsCleanup = false;
      try {
        await worker.start();
        for (var batch = 0; batch < 2; batch++) {
          if (batch == 1) {
            await sockets.last.close();
            await _until(() => sockets.length >= 2 && worker.isRunning);
            report['realSocketReconnect'] = 'PASS';
          }
          for (var i = 0; i < 3; i++) {
            final response = await action('chat', {
              'message': '$nonce batch${batch + 1}-${i + 1}',
            });
            expect((response['data'] as List).single['is_sent'], true);
          }
          await _until(() => received.length >= (batch + 1) * 3);
        }
        await Future<void>.delayed(const Duration(seconds: 2));
        await Future.wait(executions);
        expect(received, hasLength(6));
        expect(received.map((e) => e['messageId']).toSet(), hasLength(6));
        expect(received.map((e) => e['message']), [
          for (var batch = 1; batch <= 2; batch++)
            for (var i = 1; i <= 3; i++) '$nonce batch$batch-$i',
        ]);
        expect(completed, received.map((e) => e['message']).toList());
        report['sixChatSendsAndGraphsNoDuplicates'] = 'PASS';
        stdout.writeln(
          'PASS real reconnect and six ordered chat -> graph executions, no duplicate messages.',
        );
        await action('announcement', {
          'message': '$nonce announcement test',
          'color': 'blue',
        });
        report['announcement'] = 'PASS';
        final users = await http.request('GET', '/helix/users', {
          'login': targetLogin,
        }, {});
        expect(users['data'], hasLength(1));
        targetId = '${(users['data'] as List).single['id']}';
        expect(targetId, isNot(channel));
        Future<List> bans() async =>
            (await http.request('GET', '/helix/moderation/banned', {
                  'broadcaster_id': channel,
                  'user_id': targetId,
                }, {}))['data']
                as List;
        expect(
          await bans(),
          isEmpty,
          reason: 'Do not alter an existing ban or timeout.',
        );
        report['testAccount'] = targetLogin;
        for (final moderation in ['timeout', 'ban']) {
          final observed = hub
              .stream(moderation)
              .firstWhere((event) => event['viewerId'] == targetId);
          // Attach the timeout handler before sending so a failed mutation cannot
          // leave a later unhandled timeout in the test zone.
          final event = observed.timeout(const Duration(seconds: 20));
          unawaited(event.then<void>((_) {}, onError: (Object _) {}));
          needsCleanup = true;
          await action(moderation, {
            'viewerId': targetId,
            'reason': 'ShowRunner test requested by channel owner',
            if (moderation == 'timeout') 'duration': 30,
          });
          final state = await bans();
          expect(state, hasLength(1));
          expect(
            '${state.single['expires_at'] ?? ''}'.isNotEmpty,
            moderation == 'timeout',
          );
          await event;
          await action('unban', {'viewerId': targetId});
          expect(await bans(), isEmpty);
          needsCleanup = false;
          report['${moderation}AndUndoWithEventSub'] = 'PASS';
          stdout.writeln(
            'PASS $moderation -> EventSub trigger -> unban on dedicated test account.',
          );
          await Future<void>.delayed(const Duration(seconds: 1));
        }
      } finally {
        if (needsCleanup && targetId != null) {
          try {
            await action('unban', {'viewerId': targetId});
            report['emergencyCleanup'] = 'PASS';
          } catch (error) {
            report['emergencyCleanup'] = '$error';
          }
        }
        await worker.stop();
        await listener.cancel();
        await registry.close();
        await hub.dispose();
        await File(
          '${directory.path}/report.json',
        ).writeAsString(const JsonEncoder.withIndent('  ').convert(report));
        stdout.writeln('Report: ${directory.absolute.path}/report.json');
      }
    },
    skip:
        configPath == null ||
        targetLogin == null ||
        Platform.environment['SHOWRUNNER_TWITCH_MUTATIONS'] != '1',
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

AutomationDocument _graph(String plugin, String action, RuntimeMap config) =>
    automationFixture(
      entryNodeId: 'action',
      nodes: [
        GraphNode(
          id: 'action',
          type: actionNodeType(plugin, action),
          data: {'config': config},
        ),
      ],
      connections: [],
    );
Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  expect(condition(), true);
}
