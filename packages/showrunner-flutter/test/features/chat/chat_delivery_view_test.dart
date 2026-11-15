import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/features/chat/chat_workspace.dart';
import 'package:showrunner_flutter/features/chat/command_manager.dart';
import 'package:showrunner_flutter/features/chat/unified_chat_runtime.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/plugins/runtime/provider_event_workers.dart';
import 'package:showrunner_flutter/runtime/expression.dart';
import 'package:showrunner_flutter/services/plugin_event_hub.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';

void main() {
  testWidgets(
    'composer keeps partial-send draft and retries only failed destinations',
    (tester) async {
      final calls = <String>[];
      var rejectYouTube = true;
      final (
        root,
        hub,
        registry,
        runtime,
        events,
      ) = (await tester.runAsync(() async {
        final root = await Directory.systemTemp.createTemp('chat-delivery-ui-');
        final data = ShowRunnerDataService(root);
        final hub = DartPluginEventHub();
        final registry = DartPluginRegistry();
        for (final platform in ['twitch', 'youtube']) {
          registry.register(
            DartPluginManifest(
              id: PluginId(platform),
              name: platform,
              actions: [
                ActionSpec<RuntimeMap, RuntimeMap>(
                  pluginId: PluginId(platform),
                  actionId: ActionId(
                    platform == 'twitch' ? 'chat' : 'sendChatMessage',
                  ),
                  invoke: (config, context) async {
                    calls.add(platform);
                    if (platform == 'youtube' && rejectYouTube) {
                      throw StateError('private error');
                    }
                    return {};
                  },
                ),
              ],
            ),
          );
        }
        final commands = ChatCommandManager(
          repository: CommandRepository(root),
          execute: (_, _) async {},
        );
        final runtime = UnifiedChatRuntime(
          eventHub: hub,
          dataService: data,
          registryFuture: Future.value(registry),
          commands: commands,
        );
        final events = ProviderEventRuntime(dataService: data, eventHub: hub);
        await data.savePluginSettings('youtube', {'liveChatId': 'fixture'});
        await runtime.start();
        return (root, hub, registry, runtime, events);
      }))!;
      addTearDown(
        () => tester.runAsync(() async {
          await runtime.close();
          await events.stop();
          events.dispose();
          await hub.dispose();
          await registry.close();
          await root.delete(recursive: true);
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatWorkspace(runtime: runtime, providerEvents: events),
          ),
        ),
      );
      await tester.tap(find.widgetWithText(FilterChip, 'youtube'));
      final messageField = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Message',
      );
      await tester.enterText(messageField, 'Hello both');
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await (tester
                .widget<IconButton>(
                  find.byWidgetPredicate(
                    (w) => w is IconButton && w.tooltip == 'Send message',
                  ),
                )
                .onPressed!
            as Future<void> Function())();
      });
      await tester.pumpAndSettle();
      expect(calls, unorderedEquals(['twitch', 'youtube']));
      expect(find.text('twitch: sent'), findsOneWidget);
      expect(find.textContaining('youtube: failed'), findsOneWidget);
      expect(
        tester.widget<TextField>(messageField).controller!.text,
        'Hello both',
      );
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, 'twitch'))
            .selected,
        isFalse,
      );
      rejectYouTube = false;
      await tester.runAsync(() async {
        await (tester
                .widget<IconButton>(
                  find.byWidgetPredicate(
                    (w) => w is IconButton && w.tooltip == 'Send message',
                  ),
                )
                .onPressed!
            as Future<void> Function())();
      });
      await tester.pumpAndSettle();
      expect(calls.where((p) => p == 'twitch'), hasLength(1));
      expect(calls.where((p) => p == 'youtube'), hasLength(2));
      expect(tester.widget<TextField>(messageField).controller!.text, isEmpty);
      expect(find.text('private error'), findsNothing);
    },
  );
}
