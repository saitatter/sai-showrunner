import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/features/chat/chat_workspace.dart';
import 'package:showrunner_flutter/features/chat/chat_message.dart';
import 'package:showrunner_flutter/features/chat/command_manager.dart';
import 'package:showrunner_flutter/features/chat/unified_chat_runtime.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/plugins/twitch/chat_profiles.dart';
import 'package:showrunner_flutter/plugins/runtime/provider_event_workers.dart';
import 'package:showrunner_flutter/services/plugin_event_hub.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';

void main() {
  Future<(UnifiedChatRuntime, ProviderEventRuntime)> fixture(
    WidgetTester tester, {
    bool publicProfiles = false,
  }) async {
    return (await tester.runAsync(() async {
      final root = await Directory.systemTemp.createTemp('chat-view-');
      final data = ShowRunnerDataService(root);
      final hub = DartPluginEventHub();
      final registry = DartPluginRegistry();
      final events = ProviderEventRuntime(dataService: data, eventHub: hub);
      final commands = ChatCommandManager(
        repository: CommandRepository(root),
        execute: (_, _) async {},
      );
      await commands.load();
      final runtime = UnifiedChatRuntime(
        eventHub: hub,
        dataService: data,
        registryFuture: Future.value(registry),
        commands: commands,
        twitchProfiles: publicProfiles
            ? TwitchChatMetadataSource(
                dataService: data,
                request: (_, path, _, _) async => {
                  'data': path == '/helix/users'
                      ? [
                          {
                            'id': 'viewer',
                            'display_name': 'Public viewer',
                            'login': 'viewer',
                            'profile_image_url':
                                'https://static-cdn.jtvnw.net/avatar.png',
                          },
                        ]
                      : [],
                },
              )
            : null,
      );
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
      return (runtime, events);
    }))!;
  }

  testWidgets(
    'public profile dialog loads safely after build and retains platform identity',
    (tester) async {
      final (runtime, events) = await fixture(tester, publicProfiles: true);
      await tester.runAsync(() async {
        runtime.ingest(
          ChatMessage(
            platform: ChatPlatform.twitch,
            id: 'profile',
            channelId: 'channel',
            userId: 'viewer',
            userName: 'Viewer',
            text: 'hello',
            receivedAt: DateTime.utc(2026),
            isModerator: true,
          ),
        );
        await runtime.filtersSettled;
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatWorkspace(runtime: runtime, providerEvents: events),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Message and user actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('User profile'));
      await tester.pumpAndSettle();
      expect(find.text('Public viewer'), findsOneWidget);
      expect(find.text('twitch: viewer'), findsOneWidget);
      expect(
        find.text('1 message in retained session history'),
        findsOneWidget,
      );
      expect(find.byTooltip('moderator'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'incoming chat updates the timeline without rebuilding workspace or search',
    (tester) async {
      final (runtime, events) = await fixture(tester);
      var roots = 0, searches = 0;
      final previous = debugOnRebuildDirtyWidget;
      debugOnRebuildDirtyWidget = (element, once) {
        if (element.widget is ChatWorkspace) roots++;
        if (element.widget case TextField(
          decoration: InputDecoration(labelText: 'Search messages or users'),
        )) {
          searches++;
        }
        previous?.call(element, once);
      };
      addTearDown(() => debugOnRebuildDirtyWidget = previous);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatWorkspace(runtime: runtime, providerEvents: events),
          ),
        ),
      );
      final initial = (roots, searches);
      for (var i = 0; i < 30; i++) {
        await tester.runAsync(() async {
          runtime.ingest(
            ChatMessage(
              platform: ChatPlatform.twitch,
              id: '$i',
              channelId: 'channel',
              userId: 'viewer',
              userName: 'Viewer',
              text: 'message $i',
              receivedAt: DateTime.now(),
            ),
          );
          await Future<void>.delayed(Duration.zero);
        });
        await tester.pump();
      }
      expect((roots, searches), initial);
      expect(find.textContaining('message 29'), findsWidgets);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  for (final size in [
    const Size(1024, 640),
    const Size(1280, 720),
    const Size(1440, 900),
    const Size(1920, 1080),
  ]) {
    for (final dpr in [1.0, 1.5]) {
      testWidgets('chat at $size DPR $dpr and enlarged text', (tester) async {
        tester.view.devicePixelRatio = dpr;
        tester.view.physicalSize = size * dpr;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final (runtime, events) = await fixture(tester);
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.5)),
              child: child!,
            ),
            home: Scaffold(
              body: Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  width: size.width - 300,
                  child: ChatWorkspace(
                    runtime: runtime,
                    providerEvents: events,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.byTooltip('Send message').hitTestable(), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
