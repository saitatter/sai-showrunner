import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/features/chat/chat_command.dart';
import 'package:showrunner_flutter/features/chat/chat_message.dart';
import 'package:showrunner_flutter/features/chat/command_manager.dart';

ChatMessage message(
  String text, {
  String user = 'viewer',
  ChatPlatform platform = ChatPlatform.twitch,
  bool mod = false,
  bool owner = false,
  bool bot = false,
  bool member = false,
}) => ChatMessage(
  platform: platform,
  id: 'message',
  channelId: 'channel',
  userId: user,
  userName: user,
  text: text,
  receivedAt: DateTime.utc(2026),
  isModerator: mod,
  isBroadcaster: owner,
  isBot: bot,
  isSubscriber: member,
);

void main() {
  late Directory directory;
  late ChatCommandManager manager;
  late List<Map<String, dynamic>> dispatched;
  late DateTime instant;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'showrunner-command-test-',
    );
    dispatched = [];
    instant = DateTime.utc(2026);
    manager = ChatCommandManager(
      repository: CommandRepository(directory),
      now: () => instant,
      execute: (command, context) async {
        dispatched.add(context);
      },
    );
    await manager.load();
  });
  tearDown(() async {
    await manager.close();
    await directory.delete(recursive: true);
  });
  ChatCommand command({
    ChatPermission permission = ChatPermission.everyone,
    Duration global = Duration.zero,
    Duration user = Duration.zero,
    int minimum = 0,
    bool enabled = true,
  }) => ChatCommand(
    id: 'hello',
    name: 'Hello',
    pattern: '!hello',
    aliases: ['!hi'],
    automationFile: 'reply.yaml',
    globalCooldown: global,
    userCooldown: user,
    permission: permission,
    minimumArguments: minimum,
    enabled: enabled,
  );

  test(
    'only command tokens and aliases match, never unrelated chat or suffixes',
    () async {
      await manager.save(command());
      for (final text in [
        'hello',
        'please !hello',
        '!helloOther',
        'unrelated',
      ]) {
        await manager.handle(message(text));
      }
      expect(dispatched, isEmpty);
      await manager.handle(message('!HI "Ada Lovelace" one\\ two'));
      expect(dispatched.single['arguments'], ['Ada Lovelace', 'one two']);
      expect(dispatched.single['matchedCommand'], '!HI');
      expect(dispatched.single['commandCount'], 1);
      expect(dispatched.single['userCommandCount'], 1);
    },
  );
  test(
    'permission checks precede cooldowns, owner and moderator satisfy member commands',
    () async {
      await manager.save(
        command(
          permission: ChatPermission.subscriber,
          global: const Duration(seconds: 5),
        ),
      );
      await manager.handle(message('!hello'));
      expect(dispatched, isEmpty);
      await manager.handle(message('!hello', mod: true));
      expect(dispatched, hasLength(1));
      instant = instant.add(const Duration(seconds: 5));
      await manager.handle(message('!hello', owner: true));
      expect(dispatched, hasLength(2));
    },
  );
  test(
    'global cooldown is shared across users and platforms and expires at its exact deadline',
    () async {
      await manager.save(command(global: const Duration(seconds: 10)));
      await Future.wait([
        manager.handle(message('!hello')),
        manager.handle(
          message('!hi', user: 'another', platform: ChatPlatform.youtube),
        ),
      ]);
      expect(dispatched, hasLength(1));
      instant = instant.add(const Duration(seconds: 10));
      await manager.handle(message('!hi', platform: ChatPlatform.youtube));
      expect(dispatched, hasLength(2));
    },
  );
  test(
    'per-user cooldown distinguishes platform identities and allows other users',
    () async {
      await manager.save(command(user: const Duration(seconds: 30)));
      await manager.handle(message('!hello'));
      await manager.handle(message('!hello'));
      await manager.handle(message('!hello', user: 'other'));
      await manager.handle(message('!hello', platform: ChatPlatform.youtube));
      expect(dispatched, hasLength(3));
      expect(manager.countersFor('hello').users['twitch:viewer'], 1);
      expect(manager.countersFor('hello').users['youtube:viewer'], 1);
    },
  );
  test(
    'excludes bot messages, disabled commands, missing identity and malformed/missing arguments',
    () async {
      await manager.save(command(minimum: 1));
      await manager.handle(message('!hello one', bot: true));
      await manager.handle(message('!hello one', user: ''));
      await manager.handle(message('!hello'));
      await manager.handle(message('!hello "unclosed'));
      expect(dispatched, isEmpty);
      await manager.save(command(enabled: false));
      await manager.handle(message('!hello one'));
      expect(dispatched, isEmpty);
    },
  );
  test(
    'persists counters separately, survives reload and resets only requested counters',
    () async {
      await manager.save(command());
      await manager.handle(message('!hello'));
      final document = await File(
        '${directory.path}/chat-commands.json',
      ).readAsString();
      expect(document, isNot(contains('accepted')));
      await manager.load();
      expect(manager.countersFor('hello').dispatched, 1);
      await manager.resetCounters('hello');
      await manager.load();
      expect(manager.countersFor('hello').accepted, 0);
      expect(manager.commands, hasLength(1));
    },
  );
  test(
    'rejects ambiguous aliases and overlapping platform definitions without writing',
    () async {
      await manager.save(command());
      await expectLater(
        manager.save(
          ChatCommand(
            id: 'duplicate',
            name: 'Duplicate',
            pattern: '!HI',
            automationFile: 'other.yaml',
          ),
        ),
        throwsFormatException,
      );
      expect(manager.commands, hasLength(1));
      expect(await manager.repository.load(), hasLength(1));
    },
  );
  test(
    'unsupported command files stay untouched and cannot be overwritten by save',
    () async {
      final file = File('${directory.path}/chat-commands.json');
      await file.writeAsString('{"version":999,"commands":[]}');
      await manager.load();
      expect(manager.loaded, isFalse);
      expect(manager.error, isFormatException);
      await expectLater(manager.save(command()), throwsStateError);
      expect(await file.readAsString(), '{"version":999,"commands":[]}');
    },
  );
  test('records enqueue failures and retains cooldown reservations', () async {
    await manager.close();
    manager = ChatCommandManager(
      repository: CommandRepository(directory),
      now: () => instant,
      execute: (_, _) => Future.error(StateError('automation missing')),
    );
    await manager.load();
    await manager.save(command(global: const Duration(seconds: 10)));
    await manager.handle(message('!hello'));
    await manager.handle(message('!hello'));
    expect(manager.countersFor('hello').accepted, 1);
    expect(manager.countersFor('hello').failed, 1);
    expect(manager.countersFor('hello').dispatched, 0);
    expect(manager.error, isStateError);
  });
  test(
    'persists command priority and rejects externally replaced definitions',
    () async {
      await manager.save(command());
      await manager.save(
        ChatCommand(
          id: 'other',
          name: 'Other',
          pattern: '!other',
          automationFile: 'reply.yaml',
        ),
      );
      await manager.move('other', -1);
      expect(manager.commands.map((command) => command.id), ['other', 'hello']);
      expect((await CommandRepository(directory).load()).first.id, 'other');
      final file = File('${directory.path}/chat-commands.json');
      const unsupported = '{"version":999,"commands":[]}';
      await file.writeAsString(unsupported);
      await expectLater(manager.save(command()), throwsFormatException);
      expect(await file.readAsString(), unsupported);
    },
  );
  test('supports literal exact/prefix/contains and three argument parsers', () {
    expect(
      matchCommandText('!go now', ['!go'], mode: CommandMatchMode.exact),
      isNull,
    );
    expect(
      matchCommandText('say !go now', [
        '!go',
      ], mode: CommandMatchMode.contains)!.arguments,
      ['now'],
    );
    expect(
      matchCommandText('!good', [
        '!go',
      ], mode: CommandMatchMode.startsWith)!.arguments,
      ['od'],
    );
    expect(
      matchCommandText('!go "a b"', [
        '!go',
      ], argumentMode: CommandArgumentMode.words)!.arguments,
      ['"a', 'b"'],
    );
    expect(
      matchCommandText('!go a b', [
        '!go',
      ], argumentMode: CommandArgumentMode.remainder)!.arguments,
      ['a b'],
    );
    expect(matchCommandText('!GO', ['!go'], caseSensitive: true), isNull);
    expect(parseCommandArguments('"" \'a b\' 😀'), ['', 'a b', '😀']);
  });
}
