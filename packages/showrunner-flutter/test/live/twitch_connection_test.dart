// Read-only Helix requests and temporary EventSub subscriptions. No chat sends,
// moderation commands, advertisements, rewards or stream settings are changed.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'twitch_chat_fixture.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';
import 'package:showrunner_flutter/plugins/twitch/actions.dart';
import 'package:showrunner_flutter/plugins/twitch/channel_runtime.dart';
import 'package:showrunner_flutter/plugins/twitch/event_worker.dart';
import 'package:showrunner_flutter/plugins/variables/manifest.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/runtime/expression.dart';
import 'package:showrunner_flutter/graph/runtime/graph_execution_engine.dart';
import '../support/graph_fixtures.dart';
import 'package:showrunner_flutter/services/http_provider_transports.dart';
import 'package:showrunner_flutter/services/plugin_event_hub.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';

void main() {
  final path = Platform.environment['SHOWRUNNER_LIVE_CONFIG'];
  test(
    'live Twitch identity, dashboard, subscriptions and optional chat graph',
    () async {
      Map yaml;
      try {
        yaml = loadYaml(await File(path!).readAsString()) as Map;
      } catch (_) {
        fail('Cannot read local YAML; credential values omitted.');
      }
      final settings = <String, dynamic>{};
      for (final entry in (yaml['plugin_settings']['twitch'] as Map).entries) {
        final value = entry.value;
        settings['${entry.key}'] = value is String && value.startsWith('env:')
            ? Platform.environment[value.substring(4)] ?? ''
            : value;
      }
      final token = settings['accessToken']?.toString() ?? '';
      if (token.isEmpty) fail('Authorize Twitch before running live tests.');
      final directory = await Directory(
        '.tmp/twitch-proof-${DateTime.now().millisecondsSinceEpoch}',
      ).create(recursive: true);
      final report = <String, Object?>{};
      final service = ShowRunnerDataService(
        Directory('${directory.path}/profile'),
      );
      await service.savePluginSettings('twitch', settings);
      final transport = JsonHttpTransport(
        baseUrl: 'https://api.twitch.tv',
        accessToken: token,
        headers: {'Client-Id': settings['clientId']},
      );
      final validationTransport = JsonHttpTransport(
        baseUrl: 'https://id.twitch.tv',
        accessToken: token,
      );
      final validation = await validationTransport.request(
        'GET',
        '/oauth2/validate',
        {},
        null,
      );
      expect(validation['client_id'], settings['clientId']);
      expect(validation['user_id'], settings['broadcasterId']);
      expect(
        validation['scopes'],
        containsAll([
          'user:read:chat',
          'user:write:chat',
          'channel:moderate',
          'bits:read',
        ]),
      );
      report['scopeCount'] = (validation['scopes'] as List).length;
      stdout.writeln(
        'PASS OAuth identity, matching client and required scopes.',
      );

      final hub = DartPluginEventHub();
      final plugin = createTwitchPlugin(
        TwitchTransport.withDefaults(
          (method, path, query, body) {
            if (method != 'GET') {
              throw StateError(
                'Live fixture only allows read-only graph actions.',
              );
            }
            return transport.request(method, path, query, body);
          },
          broadcasterId: settings['broadcasterId'],
          moderatorId: settings['moderatorId'],
        ),
        eventHub: hub,
      );
      final registry = DartPluginRegistry()
        ..register(plugin)
        ..register(createVariablesPlugin());
      final accepted = <String>[];
      final worker = TwitchEventSubWorker(
        accessToken: token,
        clientId: settings['clientId'],
        broadcasterId: settings['broadcasterId'],
        eventHub: hub,
        request: (method, path, query, body) async {
          final response = await transport.request(method, path, query, body);
          if (method == 'POST' && path == '/helix/eventsub/subscriptions') {
            accepted.add('${body['type']}');
          }
          return response;
        },
      );
      final chat = Completer<RuntimeMap>();
      final trigger = plugin.triggers.firstWhere(
        (t) => t.triggerId.value == 'chat',
      );
      final listener = trigger.listenFromRuntime().listen((event) {
        if (event['message'] == 'showrunner-test' && !chat.isCompleted) {
          chat.complete(event);
        }
      });
      try {
        final snapshot = await TwitchChannelInfoService(
          dataService: service,
        ).load();
        expect(snapshot.broadcasterId, settings['broadcasterId']);
        report['dashboard'] = 'PASS';
        report['isLive'] = snapshot.isLive;
        for (final endpoint in [
          '/helix/chat/settings',
          '/helix/channels/followers',
        ]) {
          await transport.request('GET', endpoint, {
            'broadcaster_id': settings['broadcasterId'],
          }, null);
        }
        report['chatSettingsAndFollowers'] = 'PASS';
        stdout.writeln('PASS dashboard, chat settings and followers.');
        try {
          final result = await CompiledExecutionEngine().executeWithRegistry(
            automation: automationFixture(
              entryNodeId: 'rewards',
              nodes: [
                GraphNode(
                  id: 'rewards',
                  type: actionNodeType('twitch', 'listChannelPointRewards'),
                  data: {'config': {}},
                ),
              ],
            ),
            context: EvaluationContext(),
            registry: registry,
          );
          expect(result.completed, true);
          expect(result.nodeResults['rewards']?['data'], isA<List>());
          report['rewardGraphRead'] = 'PASS';
        } on HttpException catch (error) {
          if (!'$error'.contains('(403)')) rethrow;
          report['rewardGraphRead'] =
              'UNAVAILABLE: Twitch returned 403; verify channel eligibility.';
        }
        await worker.start().timeout(const Duration(seconds: 45));
        report['acceptedSubscriptions'] = accepted;
        report['subscriptionErrors'] = worker.subscriptionErrors;
        expect(worker.subscriptionErrors, isEmpty);
        expect(
          accepted,
          hasLength(
            defaultTwitchEventSubSubscriptions(
              settings['broadcasterId'],
            ).length,
          ),
        );
        stdout.writeln(
          'PASS ${accepted.length} live EventSub subscriptions, no rejections.',
        );
        report['adScheduleRead'] = worker.adScheduleError == null
            ? 'PASS'
            : 'UNAVAILABLE';
        final waitSeconds =
            int.tryParse(
              Platform.environment['SHOWRUNNER_TWITCH_WAIT_CHAT_SECONDS'] ?? '',
            ) ??
            0;
        if (waitSeconds > 0) {
          stdout.writeln(
            'READY: type showrunner-test in ${validation['login']} chat to execute the real trigger graph.',
          );
          final event = await chat.future.timeout(
            Duration(seconds: waitSeconds),
          );
          final result = await CompiledExecutionEngine().executeWithRegistry(
            automation: twitchChatProofGraph(),
            context: EvaluationContext(
              locals: Map<String, dynamic>.from(event),
            ),
            registry: registry,
          );
          expect(result.completed, true);
          expect(result.nodeResults['matched']?['value'], 'showrunner-test');
          report['liveChatTriggerGraph'] = 'PASS';
          stdout.writeln(
            'PASS real chat -> typed Twitch trigger -> graph condition -> variable.',
          );
        } else {
          report['liveChatTriggerGraph'] =
              'NOT RUN: set SHOWRUNNER_TWITCH_WAIT_CHAT_SECONDS.';
        }
      } finally {
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
    skip: path == null || Platform.environment['SHOWRUNNER_TWITCH_LIVE'] != '1',
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
