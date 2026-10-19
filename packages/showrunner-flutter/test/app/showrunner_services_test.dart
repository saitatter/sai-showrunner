import 'package:showrunner_flutter/features/chat/configured_chat_action.dart';
import 'dart:io';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/app/bootstrap/showrunner_services.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';
import 'package:showrunner_flutter/features/chat/chat_command.dart';
import 'package:showrunner_flutter/features/chat/chat_message.dart';
import 'package:showrunner_flutter/persistence/automation_repository.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import '../support/graph_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'managed commands run saved graphs through the real queue with event, argument and counter context',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'showrunner-command-graph-',
      );
      final data = ShowRunnerDataService(root);
      await data.savePluginSettings('showrunner-flutter', {
        'disabledPlugins': ['obs', 'aitum', 'advss', 'input'],
      });
      final services = ShowRunnerServices.create(
        dataService: data,
        onVariableChanged: (_, _) {},
        smokeMode: true,
      );
      addTearDown(() async {
        await services.shutdown();
        await root.delete(recursive: true);
      });
      await services.start();
      final registry = await services.pluginRegistryFuture;
      var captured = Completer<Map<String, dynamic>>();
      registry.register(
        DartPluginManifest(
          id: const PluginId('capture'),
          name: 'Isolated command capture',
          actions: [
            ActionSpec<Map<String, dynamic>, Object?>(
              pluginId: const PluginId('capture'),
              actionId: const ActionId('receive'),
              invoke: (config, context) async {
                captured.complete(config);
                return null;
              },
            ),
          ],
        ),
      );
      final automation = eventFixture(
        id: 'event',
        plugin: 'twitch',
        next: 'record',
        nodes: [
          actionFixture(
            'record',
            plugin: 'capture',
            action: 'receive',
            config: {
              'name': '{{ viewerName }}',
              'first': '{{ arguments.0 }}',
              'count': '{{ commandCount }}',
              'text': '{{ trigger.message }}',
            },
          ),
        ],
      );
      await AutomationRepository(
        File('${root.path}/automations/capture.yaml'),
      ).save(automation);
      await services.chatRuntime.commands.save(
        ChatCommand(
          id: 'capture',
          name: 'Capture',
          pattern: '!capture',
          aliases: ['!cap'],
          automationFile: 'capture.yaml',
        ),
      );
      await services.chatRuntime.commands.handle(
        ChatMessage(
          platform: ChatPlatform.youtube,
          id: 'message',
          channelId: 'live',
          userId: 'viewer',
          userName: 'Ada',
          text: '!cap "first argument"',
          receivedAt: DateTime.utc(2026),
        ),
      );
      final result = await captured.future.timeout(const Duration(seconds: 5));
      expect(result, {
        'name': 'Ada',
        'first': 'first argument',
        'count': 1,
        'text': '!cap "first argument"',
      });
      await services.queueManager.drain('default');
      expect(services.actionQueue.history.single.status, 'completed');
      expect(
        services.actionQueue.history.single.source['sourceType'],
        'chat-command',
      );
      expect(
        services.chatRuntime.commands.countersFor('capture').dispatched,
        1,
      );
      captured = Completer<Map<String, dynamic>>();
      await AutomationRepository(
        File('${root.path}/automations/quick.yaml'),
      ).save(
        eventFixture(
          id: 'event',
          plugin: 'twitch',
          next: 'record',
          nodes: [
            actionFixture(
              'record',
              plugin: 'capture',
              action: 'receive',
              config: {
                'scope': '{{ chatActionScope }}',
                'name': '{{ viewerName }}',
                'mode': '{{ actionArguments.mode }}',
                'text': '{{ trigger.message }}',
              },
            ),
          ],
        ),
      );
      await services.chatRuntime.saveActions([
        ConfiguredChatAction(
          id: 'quick',
          label: 'Quick',
          automationFile: 'quick.yaml',
          scope: ChatActionScope.user,
          arguments: {'mode': 'probe'},
        ),
      ]);
      services.chatRuntime.ingest(
        ChatMessage(
          platform: ChatPlatform.twitch,
          id: 'quick-target',
          channelId: 'channel',
          userId: 'viewer',
          userName: 'Ada',
          text: 'Selected message',
          receivedAt: DateTime.now(),
        ),
      );
      await services.chatRuntime.runConfiguredAction(
        'quick',
        platform: ChatPlatform.twitch,
        messageIdentity: services.chatRuntime.messages.single.identity,
      );
      expect(await captured.future.timeout(const Duration(seconds: 5)), {
        'scope': 'user',
        'name': 'Ada',
        'mode': 'probe',
        'text': 'Selected message',
      });
      await services.queueManager.drain('default');
      expect(services.actionQueue.history, hasLength(2));
      expect(
        services.actionQueue.history
            .where((item) => item.source['sourceType'] == 'chat-quick-action')
            .single
            .status,
        'completed',
      );
    },
  );

  test(
    'composes configured runtime services and shuts them down cleanly',
    () async {
      final root = Directory(
        '${Directory.current.path}/.tmp/showrunner-services-test',
      );
      await root.create(recursive: true);
      addTearDown(() => root.delete(recursive: true));
      const inputChannel = MethodChannel('showrunner/input');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(inputChannel, (_) async => null);
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(inputChannel, null),
      );
      final endpointProbe = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final endpointPort = endpointProbe.port;
      await endpointProbe.close();
      final dataService = ShowRunnerDataService(root);
      await dataService.savePluginSettings('ShowRunner', {
        'port': endpointPort,
      });
      final services = ShowRunnerServices.create(
        dataService: dataService,
        onVariableChanged: (_, _) {},
      );

      await services.start();
      final registry = await services.pluginRegistryFuture;
      expect(registry.findPlugin('obs'), isNotNull);
      expect(registry.findPlugin('twitch'), isNotNull);
      expect(await services.profileManagerFuture, isNotNull);

      await services.shutdown();
      await services.shutdown();
    },
  );
}
