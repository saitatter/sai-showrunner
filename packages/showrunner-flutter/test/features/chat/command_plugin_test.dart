import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/features/chat/chat_command.dart';
import 'package:showrunner_flutter/features/chat/chat_message.dart';
import 'package:showrunner_flutter/features/chat/command_manager.dart';
import 'package:showrunner_flutter/features/chat/command_plugin.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/services/plugin_event_hub.dart';

void main() {
  test(
    'graph command actions manage definitions, counters and filtered lifecycle events',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'showrunner-command-plugin-',
      );
      final hub = DartPluginEventHub();
      final manager = ChatCommandManager(
        repository: CommandRepository(root),
        execute: (_, _) async {},
        onEvent: hub.emit,
      );
      final registry = DartPluginRegistry()
        ..register(
          createChatCommandsPlugin(manager: () async => manager, eventHub: hub),
        );
      addTearDown(() async {
        await manager.close();
        await registry.close();
        await hub.dispose();
        await root.delete(recursive: true);
      });
      await manager.load();
      await manager.save(
        ChatCommand(
          id: 'probe',
          name: 'Probe',
          pattern: '!probe',
          automationFile: 'probe.yaml',
          globalCooldown: const Duration(seconds: 30),
        ),
      );
      Future<Object?> action(String key, Map<String, dynamic> config) =>
          registry.invokeActionKey(
            ActionKey(plugin: PluginId('chatCommands'), action: ActionId(key)),
            config,
          );
      final trigger = registry.trigger(
        TriggerKey(
          plugin: PluginId('chatCommands'),
          trigger: TriggerId('triggered'),
        ),
      )!;
      final event = trigger.listenFromRuntime().first;
      final message = ChatMessage(
        platform: ChatPlatform.twitch,
        id: 'm',
        channelId: 'channel',
        userId: 'u',
        userName: 'User',
        text: '!probe',
        receivedAt: DateTime.now(),
      );
      await manager.handle(message);
      final context = await event;
      expect(context['commandId'], 'probe');
      expect(context['commandCount'], 1);
      expect(trigger.matchesRuntime({'commandId': 'other'}, context), isFalse);
      await manager.handle(message);
      expect(manager.countersFor('probe').accepted, 1);
      await action('resetCooldowns', {'commandId': 'probe'});
      await manager.handle(message);
      expect(manager.countersFor('probe').accepted, 2);
      await action('resetUserCounters', {
        'commandId': 'probe',
        'userIdentity': 'twitch:u',
      });
      expect(manager.countersFor('probe').users, isEmpty);
      await action('setEnabled', {'commandId': 'probe', 'enabled': false});
      expect(manager.commands.single.enabled, isFalse);
      expect(
        (await action('get', {'commandId': 'probe'}) as Map)['counters'],
        containsPair('accepted', 2),
      );
      expect((await action('list', {}) as Map)['commands'], hasLength(1));
      await expectLater(
        action('delete', {'commandId': 'missing'}),
        throwsStateError,
      );
      await action('delete', {'commandId': 'probe'});
      expect(manager.commands, isEmpty);
    },
  );
}
