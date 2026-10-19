import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/features/chat/chat_command.dart';
import 'package:showrunner_flutter/features/chat/chat_message.dart';
import 'package:showrunner_flutter/features/chat/command_manager.dart';
import 'package:showrunner_flutter/features/chat/unified_chat_runtime.dart';
import 'package:showrunner_flutter/persistence/secret_settings_store.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/plugins/twitch/actions.dart';
import 'package:showrunner_flutter/plugins/youtube/actions.dart';
import 'package:showrunner_flutter/services/plugin_event_hub.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';
import 'package:showrunner_flutter/schema/data_input.dart';

void main() {
  late Directory root;
  late ShowRunnerDataService data;
  late DartPluginEventHub hub;
  late DartPluginRegistry registry;
  late UnifiedChatRuntime runtime;
  late List<Map<String, dynamic>> calls;
  String? activeYouTubeChat;
  setUp(() async {
    activeYouTubeChat = null;
    root = await Directory.systemTemp.createTemp('showrunner-chat-runtime-');
    data = ShowRunnerDataService(
      root,
      secretSettings: SecretSettingsStore(
        directory: Directory('${root.path}/secrets'),
        encrypt: (bytes) async => bytes,
        decrypt: (bytes) async => bytes,
      ),
    );
    await data.savePluginSettings('twitch', {
      'broadcasterId': 'channel',
      'moderatorId': 'bot',
      'accessToken': 'fixture-token',
    });
    await data.savePluginSettings('youtube', {
      'liveChatId': 'live-chat',
      'channelId': 'yt-bot',
    });
    hub = DartPluginEventHub();
    calls = [];
    registry = DartPluginRegistry()
      ..register(
        createTwitchPlugin(
          TwitchTransport.withDefaults(
            (method, path, query, body) async {
              calls.add({
                'method': method,
                'path': path,
                'query': query,
                'body': body,
              });
              return {};
            },
            broadcasterId: 'channel',
            moderatorId: 'bot',
          ),
        ),
      )
      ..register(
        createYouTubePlugin(
          YouTubeTransport((method, path, query, body) async {
            calls.add({
              'method': method,
              'path': path,
              'query': query,
              'body': body,
            });
            return {};
          }),
        ),
      );
    runtime = UnifiedChatRuntime(
      eventHub: hub,
      dataService: data,
      registryFuture: Future.value(registry),
      commands: ChatCommandManager(
        repository: CommandRepository(root),
        execute: (_, _) async {},
      ),
      historyLimit: 2,
      youtubeLiveChatId: () => activeYouTubeChat,
    );
    await runtime.start();
  });
  tearDown(() async {
    await runtime.close();
    await hub.dispose();
    await registry.close();
    await root.delete(recursive: true);
  });
  Map<String, dynamic> twitch(
    String id, {
    String user = 'viewer',
    String text = 'hello',
  }) => {
    'message_id': id,
    'broadcaster_user_id': 'channel',
    'chatter_user_id': user,
    'chatter_user_name': 'Viewer',
    'message': {'text': text},
    'badges': [
      {'set_id': 'moderator'},
    ],
  };
  Map<String, dynamic> youtube(String id) => {
    'id': id,
    'snippet': {
      'type': 'textMessageEvent',
      'displayMessage': 'YouTube message',
      'liveChatId': 'live-chat',
    },
    'authorDetails': {
      'channelId': 'yt-viewer',
      'displayName': 'YT Viewer',
      'isChatSponsor': true,
    },
  };
  test(
    'includes paid YouTube messages from their dedicated event streams',
    () async {
      for (final entry in {
        'superChat': 'superChatEvent',
        'superSticker': 'superStickerEvent',
      }.entries) {
        final event = youtube(entry.key);
        (event['snippet'] as Map)['type'] = entry.value;
        hub.emit(entry.key, event);
      }
      await Future<void>.delayed(Duration.zero);
      expect(runtime.messages.map((message) => message.id), [
        'superChat',
        'superSticker',
      ]);
    },
  );
  test(
    'merges providers, deduplicates per platform/channel and bounds history',
    () async {
      hub.emit('chat', twitch('same'));
      hub.emit('chat', twitch('same'));
      hub.emit('chatMessage', youtube('same'));
      await Future<void>.delayed(Duration.zero);
      expect(runtime.messages, hasLength(2));
      expect(runtime.messages.map((m) => m.platform), [
        ChatPlatform.twitch,
        ChatPlatform.youtube,
      ]);
      expect(runtime.messages.first.isModerator, isTrue);
      expect(runtime.messages.last.isSubscriber, isTrue);
      hub.emit('chat', twitch('new'));
      await Future<void>.delayed(Duration.zero);
      expect(runtime.messages.map((m) => m.id), ['same', 'new']);
      runtime.clearHistory();
      expect(runtime.messages, isEmpty);
      hub.emit('chat', twitch('same'));
      await Future<void>.delayed(Duration.zero);
      expect(
        runtime.messages,
        isEmpty,
      ); // Clearing history must not replay commands.
    },
  );
  test(
    'uses the active YouTube worker chat instead of stale saved settings',
    () async {
      activeYouTubeChat = 'discovered-live-chat';
      await runtime.send(ChatPlatform.youtube, 'Current broadcast');
      expect(
        (calls.single['body'] as Map)['snippet']['liveChatId'],
        'discovered-live-chat',
      );
    },
  );
  test(
    'routes sends to exactly one provider and does not fabricate history',
    () async {
      await runtime.send(ChatPlatform.twitch, 'Hello Twitch');
      await runtime.send(ChatPlatform.youtube, 'Hello YouTube');
      expect(calls, hasLength(2));
      expect(calls.first['body'], {
        'broadcaster_id': 'channel',
        'sender_id': 'channel',
        'message': 'Hello Twitch',
      });
      expect((calls.last['body'] as Map)['snippet']['liveChatId'], 'live-chat');
      expect(calls.toString(), isNot(contains('fixture-token')));
      expect(runtime.messages, isEmpty);
      await expectLater(
        runtime.send(ChatPlatform.youtube, 'x' * 201),
        throwsFormatException,
      );
      expect(calls, hasLength(2));
    },
  );
  test(
    'uses provider message/user IDs for moderation and only marks a successful delete',
    () async {
      final message = ChatMessage.fromTwitch(twitch('message-123'))!;
      runtime.ingest(message);
      await runtime.quickAction(message, ChatQuickAction.deleteMessage);
      expect(calls.single['path'], '/helix/moderation/chat');
      expect(calls.single['query'], {
        'broadcaster_id': 'channel',
        'moderator_id': 'channel',
        'message_id': 'message-123',
      });
      expect(runtime.messages.single.deleted, isTrue);
      final yt = ChatMessage.fromYouTube(youtube('yt-message'))!;
      await runtime.quickAction(yt, ChatQuickAction.timeout);
      final snippet = (calls.last['body'] as Map)['snippet'] as Map;
      expect(snippet['type'], 'temporary');
      expect(snippet['banDurationSeconds'], 60);
      expect(snippet['bannedUserDetails'], {'channelId': 'yt-viewer'});
    },
  );
  test(
    'recognizes bot identity without trusting payload flags and handles YouTube deletion events',
    () async {
      hub.emit('chat', {...twitch('bot-message', user: 'bot'), 'isBot': false});
      hub.emit('chatMessage', youtube('yt-message'));
      await Future<void>.delayed(Duration.zero);
      expect(runtime.messages.first.isBot, isTrue);
      hub.emit('chatMessage', {
        'snippet': {
          'type': 'messageDeletedEvent',
          'messageDeletedDetails': {'deletedMessageId': 'yt-message'},
        },
      });
      await Future<void>.delayed(Duration.zero);
      expect(runtime.messages.last.deleted, isTrue);
    },
  );
  test(
    'Twitch chat command starter actually filters unrelated messages and token suffixes',
    () {
      final trigger = registry.trigger(
        const TriggerKey(
          plugin: PluginId('twitch'),
          trigger: TriggerId('chat'),
        ),
      )!;
      final config = {
        'command': {'mode': 'command', 'match': '!hello', 'hasMessage': false},
        'cooldown': null,
      };
      expect(
        trigger.matchesRuntime(config, {
          'viewerId': 'viewer',
          'message': 'not a command',
        }),
        isFalse,
      );
      expect(
        trigger.matchesRuntime(config, {
          'viewerId': 'viewer',
          'message': '!helloOther',
        }),
        isFalse,
      );
      expect(
        trigger.matchesRuntime(config, {
          'viewerId': 'viewer',
          'message': '!HELLO "Ada Lovelace"',
        }),
        isTrue,
      );
      expect(
        trigger.matchesRuntime({}, {
          'viewerId': 'viewer',
          'message': 'raw chat',
        }),
        isTrue,
      );
      final defaults = Map<String, dynamic>.from(
        constructDartDataInputDefault(trigger.configSchema!) as Map,
      );
      expect(trigger.matchesRuntime(defaults, {'message': 'raw chat'}), isTrue);
      expect(
        () => trigger.matchesRuntime({'cooldown': 10}, {'message': 'raw chat'}),
        throwsFormatException,
      );
    },
  );
  test(
    'emoji suggestions work without provider credentials on both platforms',
    () {
      expect(
        runtime.suggestEmotes(':smi', ChatPlatform.youtube).single.text,
        '😀',
      );
      expect(
        runtime.suggestEmotes(':smi', ChatPlatform.twitch).single.name,
        ':smile:',
      );
    },
  );
  test('restricts commands to selected platforms', () async {
    final received = <String>[];
    final manager = ChatCommandManager(
      repository: CommandRepository(Directory('${root.path}/separate')),
      execute: (_, context) async {
        received.add(context['platform'] as String);
      },
    );
    await manager.load();
    await manager.save(
      ChatCommand(
        id: 'hello',
        name: 'Hello',
        pattern: '!hello',
        automationFile: 'reply.yaml',
        platforms: {ChatPlatform.youtube},
      ),
    );
    await manager.handle(
      ChatMessage.fromTwitch(twitch('one', text: '!hello'))!,
    );
    await manager.handle(
      ChatMessage.fromYouTube({
        ...youtube('two'),
        'snippet': {'displayMessage': '!hello'},
      })!,
    );
    expect(received, ['youtube']);
    await manager.close();
  });
}
