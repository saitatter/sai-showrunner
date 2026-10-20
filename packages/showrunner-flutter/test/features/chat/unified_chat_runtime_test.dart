import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/features/chat/chat_command.dart';
import 'package:showrunner_flutter/features/chat/chat_preferences.dart';
import 'package:showrunner_flutter/features/chat/configured_chat_action.dart';
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
  late List<Map<String, dynamic>> actionCalls;
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
    actionCalls = [];
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
      executeAction: (action, values) async => actionCalls.add(values),
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
    'local deletion changes only the selected channel when provider IDs overlap',
    () async {
      for (final channel in ['channel', 'other-channel']) {
        runtime.ingest(
          ChatMessage(
            platform: ChatPlatform.twitch,
            id: 'same-id',
            channelId: channel,
            userId: 'viewer',
            userName: 'Viewer',
            text: 'hello',
            receivedAt: DateTime.now(),
          ),
        );
      }
      await runtime.quickAction(
        runtime.messages.first,
        ChatQuickAction.deleteMessage,
      );
      expect(runtime.messages.map((m) => m.deleted), [true, false]);
      expect((calls.single['query'] as Map)['broadcaster_id'], 'channel');
    },
  );
  test(
    'moderation arriving before a message prevents display recovery and command execution',
    () async {
      await runtime.commands.save(
        ChatCommand(
          id: 'late',
          name: 'Late',
          pattern: '!late',
          automationFile: 'a.yaml',
        ),
      );
      hub.emit('twitchChatDeleted', {
        'broadcaster_user_id': 'channel',
        'message_id': 'late-deleted',
      });
      hub.emit('chat', twitch('late-deleted', text: '!late'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(runtime.messages.single.deleted, isTrue);
      expect(runtime.commands.countersFor('late').accepted, 0);
      runtime.clearHistory();
      hub.emit('twitchUserChatCleared', {
        'broadcaster_user_id': 'channel',
        'target_user_id': 'viewer',
        'providerTime': '2026-01-02T00:00:00Z',
      });
      hub.emit('chat', {
        ...twitch('late-cleared'),
        'providerTime': '2026-01-01T00:00:00Z',
      });
      hub.emit('chat', {
        ...twitch('new'),
        'providerTime': '2026-01-03T00:00:00Z',
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(runtime.messages.map((m) => m.deleted), [true, false]);
      hub.emit('twitchUserChatCleared', {'broadcaster_user_id': 'channel'});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(runtime.messages.last.deleted, isFalse);
    },
  );
  test(
    'YouTube bans target the banned user rather than the moderator or another live chat',
    () async {
      for (final user in ['banned', 'moderator']) {
        runtime.ingest(
          ChatMessage(
            platform: ChatPlatform.youtube,
            id: user,
            channelId: 'live-chat',
            userId: user,
            userName: user,
            text: 'hello',
            receivedAt: DateTime.now(),
          ),
        );
      }
      hub.emit('chatMessage', {
        'id': 'ban',
        'snippet': {
          'type': 'userBannedEvent',
          'liveChatId': 'live-chat',
          'authorChannelId': 'moderator',
          'userBannedDetails': {
            'bannedUserDetails': {'channelId': 'banned'},
            'banType': 'permanent',
          },
        },
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(runtime.messages.first.deleted, isTrue);
      expect(runtime.messages.last.deleted, isFalse);
      hub.emit('chatMessage', {
        'id': 'moderator',
        'snippet': {'type': 'tombstone', 'liveChatId': 'other-live'},
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(runtime.messages.last.deleted, isFalse);
      hub.emit('chatMessage', {
        'id': 'moderator',
        'snippet': {'type': 'tombstone', 'liveChatId': 'live-chat'},
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(runtime.messages.last.deleted, isTrue);
    },
  );
  test(
    'configured actions validate scope and dispatch trusted message/event context',
    () async {
      await runtime.saveActions([
        for (final scope in ChatActionScope.values)
          ConfiguredChatAction(
            id: scope.name,
            label: scope.name,
            automationFile: 'a.yaml',
            scope: scope,
            platforms: {ChatPlatform.twitch},
            arguments: {'mode': 'probe'},
          ),
      ]);
      hub.emit('chat', twitch('target'));
      hub.emit('follow', {
        'id': 'event-1',
        'user_id': 'follower',
        'user_name': 'Follower',
        'message': 'hello',
        'accessToken': 'never-export',
      });
      hub.emit('twitchWhisper', {
        'whisper_id': 'private',
        'from_user_id': 'private-user',
        'to_user_id': 'channel',
        'whisper': {'text': 'keep private'},
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(runtime.events, hasLength(1));
      expect(
        runtime.events.single.context.toString(),
        isNot(contains('never-export')),
      );
      await runtime.send(ChatPlatform.twitch, '/action:global extra text');
      for (final scope in [ChatActionScope.message, ChatActionScope.user]) {
        await runtime.runConfiguredAction(
          scope.name,
          platform: ChatPlatform.twitch,
          messageIdentity: runtime.messages.single.identity,
        );
      }
      await runtime.runConfiguredAction(
        'event',
        platform: ChatPlatform.twitch,
        eventId: runtime.events.single.id,
      );
      expect(actionCalls, hasLength(4));
      expect(actionCalls.first['actionInput'], 'extra text');
      expect(actionCalls[1]['viewerId'], 'viewer');
      expect(actionCalls[2]['chatActionScope'], 'user');
      expect(actionCalls.last['viewerId'], 'follower');
      expect(actionCalls.last['actionArguments'], {'mode': 'probe'});
      await expectLater(
        runtime.runConfiguredAction('global', platform: ChatPlatform.youtube),
        throwsStateError,
      );
      await expectLater(
        runtime.send(ChatPlatform.twitch, '/action:message'),
        throwsStateError,
      );
      runtime.clearHistory();
      await expectLater(
        runtime.runConfiguredAction(
          'message',
          platform: ChatPlatform.twitch,
          messageIdentity: 'twitch:channel:target',
        ),
        throwsStateError,
      );
      await expectLater(
        runtime.runConfiguredAction(
          'event',
          platform: ChatPlatform.twitch,
          eventId: 'gone',
        ),
        throwsStateError,
      );
      expect((await data.loadPluginSettings('chat-actions'))['version'], 1);
      expect(calls, isEmpty);
    },
  );
  test(
    'unsupported persisted preferences remain intact and cannot be overwritten',
    () async {
      await data.savePluginSettings('chat', {'version': 99, 'unknown': 'keep'});
      final second = UnifiedChatRuntime(
        eventHub: hub,
        dataService: data,
        registryFuture: Future.value(registry),
        commands: ChatCommandManager(
          repository: CommandRepository(
            await Directory('${root.path}/other').create(),
          ),
          execute: (_, _) async {},
        ),
      );
      await second.start();
      expect(second.error, isFormatException);
      await expectLater(
        second.savePreferences(ChatPreferences()),
        throwsStateError,
      );
      expect(await data.loadPluginSettings('chat'), {
        'version': 99,
        'unknown': 'keep',
      });
      await second.close();
    },
  );
  test(
    'ignores hide by stable identity without blocking commands unless selected',
    () async {
      await runtime.commands.save(
        ChatCommand(
          id: 'probe',
          name: 'Probe',
          pattern: '!probe',
          automationFile: 'a.yaml',
        ),
      );
      await runtime.savePreferences(
        ChatPreferences(ignoredUsers: {'twitch:viewer'}),
      );
      final dispatched = Completer<void>();
      void commandChanged() {
        if (runtime.commands.countersFor('probe').dispatched == 1 &&
            !dispatched.isCompleted) {
          dispatched.complete();
        }
      }

      runtime.commands.addListener(commandChanged);
      try {
        hub.emit('chat', twitch('hidden', text: '!probe'));
        await runtime.filtersSettled;
        await dispatched.future.timeout(const Duration(seconds: 5));
      } finally {
        runtime.commands.removeListener(commandChanged);
      }
      expect(runtime.messages, isEmpty);
      expect(runtime.commands.countersFor('probe').dispatched, 1);
      await runtime.savePreferences(
        ChatPreferences(
          ignoredUsers: {'twitch:viewer'},
          preventIgnoredCommands: true,
        ),
      );
      final delivered = hub.stream('chat').first;
      hub.emit('chat', twitch('blocked', text: '!probe'));
      await delivered;
      await runtime.filtersSettled;
      expect(runtime.commands.countersFor('probe').accepted, 1);
      await runtime.savePreferences(
        ChatPreferences(
          highlightTerms: ['!PROBE'],
          fontSize: 18,
          timestamps: true,
        ),
      );
      expect(runtime.messages, hasLength(2));
      expect(runtime.preferences.highlights(runtime.messages.first), isTrue);
      expect((await data.loadPluginSettings('chat'))['fontSize'], 18);
    },
  );
  test(
    'bounded ignore regex and command detection are shared with public history',
    () async {
      await runtime.commands.save(
        ChatCommand(
          id: 'probe',
          name: 'Probe',
          pattern: '!probe',
          automationFile: 'a.yaml',
        ),
      );
      await runtime.savePreferences(
        ChatPreferences(
          hideCommands: true,
          ignoreRules: [ChatIgnoreRule(ChatRuleMode.regex, r'^spam\d+$')],
        ),
      );
      hub.emit('chat', twitch('spam', text: 'spam42'));
      hub.emit('chat', twitch('command', text: '!probe'));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await runtime.filtersSettled;
      expect(runtime.messages, isEmpty);
      await runtime.savePreferences(ChatPreferences());
      expect(runtime.messages.map((m) => m.text), ['spam42', '!probe']);
    },
  );
  test(
    'command menus respect visibility, platform, enabled state and sources',
    () async {
      for (final command in [
        ChatCommand(
          id: 'visible',
          name: 'Visible',
          pattern: '!hello',
          aliases: ['!hi'],
          automationFile: 'a.yaml',
          platforms: {ChatPlatform.twitch},
        ),
        ChatCommand(
          id: 'hidden',
          name: 'Hidden',
          pattern: '!hidden',
          automationFile: 'a.yaml',
          includeInList: false,
        ),
        ChatCommand(
          id: 'disabled',
          name: 'Disabled',
          pattern: '!disabled',
          automationFile: 'a.yaml',
          enabled: false,
        ),
        ChatCommand(
          id: 'private',
          name: 'Private',
          pattern: '!secret',
          automationFile: 'a.yaml',
          origins: {ChatOrigin.whisper},
        ),
        ChatCommand(
          id: 'regex',
          name: 'Regex',
          pattern: '!regex.*',
          automationFile: 'a.yaml',
          matchMode: CommandMatchMode.regex,
        ),
      ]) {
        await runtime.commands.save(command);
      }
      expect(
        runtime
            .composerCompletions(ChatPlatform.twitch)
            .where((s) => s.kind == 'command')
            .map((s) => s.text),
        ['!hello', '!hi'],
      );
      expect(
        runtime
            .composerCompletions(ChatPlatform.youtube)
            .where((s) => s.kind == 'command'),
        isEmpty,
      );
      expect(
        runtime
            .composerCompletions(ChatPlatform.youtube)
            .where((s) => s.kind == 'action')
            .map((s) => s.text),
        ['/clear', '/pause', '/resume'],
      );
    },
  );
  test('external Twitch moderation is scoped by channel and viewer', () async {
    hub.emit('chat', twitch('one'));
    hub.emit('chat', {
      ...twitch('two'),
      'broadcaster_user_id': 'other-channel',
    });
    await Future<void>.delayed(Duration.zero);
    hub.emit('twitchChatDeleted', {
      'broadcaster_user_id': 'channel',
      'message_id': 'one',
    });
    await Future<void>.delayed(Duration.zero);
    expect(runtime.messages.first.deleted, isTrue);
    expect(runtime.messages.last.deleted, isFalse);
    hub.emit('twitchChatCleared', {'broadcaster_user_id': 'other-channel'});
    await Future<void>.delayed(Duration.zero);
    expect(runtime.messages.last.deleted, isTrue);
  });
  test(
    'whispers can trigger opted-in commands without entering public history',
    () async {
      await runtime.close();
      final contexts = <Map<String, dynamic>>[];
      runtime = UnifiedChatRuntime(
        eventHub: hub,
        dataService: data,
        registryFuture: Future.value(registry),
        commands: ChatCommandManager(
          repository: CommandRepository(root),
          execute: (_, context) async => contexts.add(context),
        ),
      );
      await runtime.start();
      await runtime.commands.save(
        ChatCommand(
          id: 'private',
          name: 'Private',
          pattern: '!private',
          automationFile: 'private.yaml',
          origins: {ChatOrigin.whisper, ChatOrigin.botWhisper},
        ),
      );
      for (final recipient in ['channel', 'bot']) {
        hub.emit('twitchWhisper', {
          'whisper_id': recipient,
          'to_user_id': recipient,
          'from_user_id': 'viewer',
          'from_user_name': 'Viewer',
          'whisper': {'text': '!private'},
        });
      }
      for (var i = 0; i < 100 && contexts.length < 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(contexts.map((c) => c['origin']), ['whisper', 'botWhisper']);
      expect(contexts.map((c) => c['channelId']), ['channel', 'channel']);
      expect(runtime.messages, isEmpty);
    },
  );
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
