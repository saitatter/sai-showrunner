import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/features/chat/chat_command.dart';
import 'package:showrunner_flutter/features/chat/chat_message.dart';
import 'package:showrunner_flutter/features/chat/command_manager.dart';

void main() {
  late Directory root;
  late ChatCommandManager manager;
  late List<Map<String, dynamic>> calls;
  late List<String> events;
  late Set<String> memberships;
  late DateTime now;
  ChatMessage message({
    String text = '!probe',
    String user = 'one',
    ChatPlatform platform = ChatPlatform.twitch,
    ChatOrigin origin = ChatOrigin.chat,
    bool bot = false,
    bool owner = false,
    bool moderator = false,
  }) => ChatMessage(
    platform: platform,
    id: 'message',
    channelId: 'channel',
    userId: user,
    userName: user,
    text: text,
    origin: origin,
    isBot: bot,
    isBroadcaster: owner,
    isModerator: moderator,
    receivedAt: now,
  );
  ChatCommand command([Map<String, dynamic> values = const {}]) =>
      ChatCommand.fromJson({
        ...ChatCommand(
          id: 'probe',
          name: 'Probe',
          pattern: '!probe',
          automationFile: 'probe.yaml',
        ).toJson(),
        ...values,
      });
  setUp(() async {
    root = await Directory.systemTemp.createTemp(
      'showrunner-advanced-commands-',
    );
    calls = [];
    events = [];
    memberships = {};
    now = DateTime.utc(2026);
    manager = ChatCommandManager(
      repository: CommandRepository(root),
      execute: (_, context) async => calls.add(context),
      now: () => now,
      groupMemberships: (_, _) async => memberships,
      onEvent: (event, _) => events.add(event),
    );
    await manager.load();
  });
  tearDown(() async {
    await manager.close();
    await root.delete(recursive: true);
  });

  test(
    'Allow and Deny combine provider roles, stable identities and custom groups',
    () async {
      await manager.save(
        command({
          'roles': ['moderator'],
          'users': ['youtube:two'],
          'groups': ['trusted'],
        }),
      );
      await manager.handle(message());
      expect(calls, isEmpty);
      await manager.handle(message(moderator: true));
      await manager.handle(
        message(platform: ChatPlatform.youtube, user: 'two'),
      );
      await manager.handle(message(user: 'two'));
      expect(calls.length, 2);
      memberships = {'trusted'};
      await manager.handle(message());
      expect(calls.length, 3);
      await manager.save(
        command({
          'grant': 'deny',
          'users': ['twitch:one'],
        }),
      );
      await manager.handle(message());
      expect(calls.length, 3);
      await manager.handle(message(platform: ChatPlatform.youtube));
      expect(calls.length, 4);
      await manager.save(command({'grant': 'deny'}));
      await manager.handle(message(owner: true));
      expect(calls.length, 5);
      await manager.save(command({'grant': 'deny', 'broadcasterBypass': true}));
      await manager.handle(message(owner: true));
      expect(calls.length, 6);
    },
  );

  test(
    'explicit Allow/Deny roles use actual badges while minimum permission keeps its hierarchy',
    () async {
      await manager.save(
        command({
          'grant': 'deny',
          'roles': ['subscriber'],
        }),
      );
      await manager.handle(message(moderator: true));
      await manager.handle(message(owner: true));
      expect(calls, hasLength(2));
      await manager.save(
        command({
          'roles': ['moderator'],
        }),
      );
      await manager.handle(message(owner: true));
      expect(calls, hasLength(2));
      await manager.save(command({'permission': 'moderator'}));
      await manager.handle(message(owner: true));
      expect(calls, hasLength(3));
      expect(command({'grant': 'deny'}).grants(message(), {}), isTrue);
      expect(command({'grant': 'allow'}).grants(message(), {}), isTrue);
    },
  );

  test(
    'group lookup failure fails closed without consuming counters',
    () async {
      await manager.close();
      manager = ChatCommandManager(
        repository: CommandRepository(root),
        execute: (_, context) async => calls.add(context),
        groupMemberships: (_, _) async => throw StateError('Group is missing'),
      );
      await manager.load();
      await manager.save(
        command({
          'grant': 'deny',
          'groups': ['missing'],
        }),
      );
      await manager.handle(message());
      expect(calls, isEmpty);
      expect(manager.error, isStateError);
      expect(manager.countersFor('probe').accepted, 0);
    },
  );

  test(
    'regex captures numbered/named arguments and rejects malformed expressions',
    () async {
      await manager.save(
        command({
          'matchMode': 'regex',
          'pattern': r'^!probe (?<name>\S+) (\d+)$',
        }),
      );
      await manager.handle(message(text: '!probe Ada 42'));
      expect(calls.single['arguments'], ['Ada', '42']);
      expect((calls.single['captures'] as Map)['name'], 'Ada');
      expect((calls.single['captures'] as Map)['2'], '42');
      await manager.handle(message(text: 'unrelated !probe Ada 42'));
      expect(calls, hasLength(1));
      expect(
        () => command({'matchMode': 'regex', 'pattern': '['}),
        throwsFormatException,
      );
    },
  );

  test(
    'pathological regex cannot block the UI isolate or enqueue work',
    () async {
      await manager.save(
        command({'matchMode': 'regex', 'pattern': r'^(a+)+$'}),
      );
      var ticks = 0;
      final timer = Timer.periodic(
        const Duration(milliseconds: 10),
        (_) => ticks++,
      );
      try {
        await manager
            .handle(message(text: '${'a' * 500}!'))
            .timeout(const Duration(seconds: 5));
      } finally {
        timer.cancel();
      }
      expect(ticks, greaterThan(0));
      expect(manager.error, isA<TimeoutException>());
      expect(calls, isEmpty);
    },
  );

  test(
    'source selection and bot/internal opt-ins remain independent',
    () async {
      await manager.save(command());
      for (final origin in ChatOrigin.values.where(
        (o) => o != ChatOrigin.chat,
      )) {
        await manager.handle(message(origin: origin));
      }
      await manager.handle(message(bot: true));
      expect(calls, isEmpty);
      await manager.save(
        command({
          'origins': [
            'sharedChat',
            'whisper',
            'botWhisper',
            'subscription',
            'internal',
          ],
          'ignoreBots': false,
          'ignoreInternal': false,
        }),
      );
      for (final origin in ChatOrigin.values.where(
        (o) => o != ChatOrigin.chat,
      )) {
        await manager.handle(message(origin: origin, bot: true));
      }
      expect(calls.length, ChatOrigin.values.length - 1);
    },
  );

  test('reset cooldowns and user counters do not erase total counts', () async {
    await manager.save(
      command({'globalCooldownMs': 10000, 'userCooldownMs': 20000}),
    );
    await manager.handle(message());
    await manager.handle(message());
    expect(events, contains('chatCommands.cooldown'));
    expect(calls, hasLength(1));
    await manager.resetCounters('probe');
    await manager.handle(message());
    expect(calls, hasLength(1));
    await manager.resetCooldowns('probe');
    await manager.handle(message());
    expect(calls, hasLength(2));
    await manager.resetUserCounters('probe', userIdentity: 'twitch:one');
    expect(manager.countersFor('probe').accepted, 1);
    expect(manager.countersFor('probe').users, isEmpty);
    await manager.setEnabled('probe', false);
    await manager.handle(message());
    expect(calls, hasLength(2));
    expect(
      events,
      containsAll([
        'chatCommands.added',
        'chatCommands.triggered',
        'chatCommands.updated',
        'chatCommands.countersReset',
        'chatCommands.cooldownReset',
      ]),
    );
  });

  test(
    'persistence switches preserve session counts while omitting restart state',
    () async {
      await manager.save(
        command({'persistCounter': false, 'persistUserCounter': false}),
      );
      await manager.handle(message());
      expect(manager.countersFor('probe').accepted, 1);
      final counters = await CommandRepository(root).loadCounters();
      expect(counters['probe']!.accepted, 0);
      expect(counters['probe']!.users, isEmpty);
      await manager.close();
      manager = ChatCommandManager(
        repository: CommandRepository(root),
        execute: (_, _) async {},
      );
      await manager.load();
      expect(manager.countersFor('probe').accepted, 0);
    },
  );
}
