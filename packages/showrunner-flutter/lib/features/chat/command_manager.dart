import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../persistence/filesystem/atomic_file.dart';
import '../../persistence/filesystem/safe_path.dart';
import 'chat_command.dart';
import 'chat_message.dart';

typedef CommandExecutor =
    Future<void> Function(ChatCommand command, Map<String, dynamic> context);

final class CommandCounters {
  CommandCounters({
    this.accepted = 0,
    this.dispatched = 0,
    this.failed = 0,
    Map<String, int> users = const {},
  }) : users = Map.of(users);
  int accepted, dispatched, failed;
  final Map<String, int> users;
  Map<String, dynamic> toJson() => {
    'accepted': accepted,
    'dispatched': dispatched,
    'failed': failed,
    'users': users,
  };
  factory CommandCounters.fromJson(Map<String, dynamic> data) {
    final counters = CommandCounters(
      accepted: data['accepted'] as int,
      dispatched: data['dispatched'] as int,
      failed: data['failed'] as int,
      users: Map<String, int>.from(data['users'] as Map),
    );
    if ([
      counters.accepted,
      counters.dispatched,
      counters.failed,
      ...counters.users.values,
    ].any((v) => v < 0)) {
      throw const FormatException('Invalid command counters.');
    }
    return counters;
  }
}

final class CommandRepository {
  const CommandRepository(this.directory);
  final Directory directory;

  Future<List<ChatCommand>> load() async {
    final file = await containedFile(directory, ['chat-commands.json']);
    if (!await file.exists()) return [];
    final data = jsonDecode(await file.readAsString());
    if (data is! Map || data['version'] != 1 || data['commands'] is! List) {
      throw const FormatException('Unsupported chat command document.');
    }
    return (data['commands'] as List)
        .map((c) => ChatCommand.fromJson(Map<String, dynamic>.from(c as Map)))
        .toList();
  }

  Future<void> save(List<ChatCommand> commands) async {
    final file = await containedFile(directory, ['chat-commands.json']);
    await withFileLock('${file.path}.transaction', () async {
      await load(); // Reject unsupported documents changed while the workspace was open.
      await writeAtomicText(
        file,
        jsonEncode({
          'version': 1,
          'commands': commands.map((c) => c.toJson()).toList(),
        }),
      );
    });
  }

  Future<Map<String, CommandCounters>> loadCounters() async {
    final file = await containedFile(directory, [
      'state',
      'chat-command-counters.json',
    ]);
    if (!await file.exists()) return {};
    final data = jsonDecode(await file.readAsString());
    if (data is! Map || data['version'] != 1 || data['counters'] is! Map) {
      throw const FormatException('Unsupported command counter state.');
    }
    return (data['counters'] as Map).map(
      (key, value) => MapEntry(
        key as String,
        CommandCounters.fromJson(Map<String, dynamic>.from(value as Map)),
      ),
    );
  }

  Future<void> saveCounters(Map<String, CommandCounters> counters) async {
    final file = await containedFile(directory, [
      'state',
      'chat-command-counters.json',
    ]);
    await withFileLock('${file.path}.transaction', () async {
      await loadCounters();
      await writeAtomicText(
        file,
        jsonEncode({
          'version': 1,
          'counters': counters.map(
            (key, value) => MapEntry(key, value.toJson()),
          ),
        }),
      );
    });
  }
}

/// Owns matching/permissions/cooldown reservations and persistent counters.
/// Definitions never contain execution callbacks or mutable runtime state.
final class ChatCommandManager extends ChangeNotifier {
  ChatCommandManager({
    required this.repository,
    required this.execute,
    DateTime Function()? now,
    this.groupMemberships,
    this.onEvent,
    this.isEnabled,
  }) : now = now ?? DateTime.now;
  final CommandRepository repository;
  final CommandExecutor execute;
  final Future<bool> Function()? isEnabled;
  final Future<Set<String>> Function(ChatMessage message, Set<String> groups)?
  groupMemberships;
  final void Function(String eventId, Map<String, dynamic> values)? onEvent;

  void _emit(
    String event,
    ChatCommand command, [
    Map<String, dynamic> values = const {},
  ]) => onEvent?.call('chatCommands.$event', {
    'commandId': command.id,
    'command': command.pattern,
    ...values,
  });

  ChatCommand commandById(String id) => _commands.firstWhere(
    (c) => c.id == id,
    orElse: () => throw StateError('Unknown command: $id'),
  );

  Future<void> setEnabled(String id, bool enabled) => save(
    ChatCommand.fromJson({...commandById(id).toJson(), 'enabled': enabled}),
  );

  Map<String, CommandCounters> _persistedCounters(
    Map<String, CommandCounters> values,
  ) => {
    for (final entry in values.entries)
      entry.key: CommandCounters(
        accepted:
            _commands
                    .where((c) => c.id == entry.key)
                    .firstOrNull
                    ?.persistCounter ==
                false
            ? 0
            : entry.value.accepted,
        dispatched:
            _commands
                    .where((c) => c.id == entry.key)
                    .firstOrNull
                    ?.persistCounter ==
                false
            ? 0
            : entry.value.dispatched,
        failed:
            _commands
                    .where((c) => c.id == entry.key)
                    .firstOrNull
                    ?.persistCounter ==
                false
            ? 0
            : entry.value.failed,
        users:
            _commands
                    .where((c) => c.id == entry.key)
                    .firstOrNull
                    ?.persistUserCounter ==
                false
            ? {}
            : entry.value.users,
      ),
  };

  Future<void> resetUserCounters(String id, {String? userIdentity}) =>
      _serialize(() async {
        _ensureReady();
        final command = commandById(id);
        final current = countersFor(id);
        final users = {...current.users};
        if (userIdentity == null) {
          users.clear();
        } else {
          users.remove(userIdentity);
        }
        final next = {
          ..._counters,
          id: CommandCounters(
            accepted: current.accepted,
            dispatched: current.dispatched,
            failed: current.failed,
            users: users,
          ),
        };
        await repository.saveCounters(_persistedCounters(next));
        _counters = next;
        _emit('countersReset', command, {
          'userIdentity': userIdentity,
          'usersOnly': true,
        });
        notifyListeners();
      });

  Future<void> resetCooldowns(String id, {String? userIdentity}) =>
      _serialize(() async {
        _ensureReady();
        final command = commandById(id);
        if (userIdentity == null) {
          _globalReady.remove(id);
          _userReady.removeWhere((key, _) => key.startsWith('$id:'));
        } else {
          _userReady.remove('$id:$userIdentity');
        }
        _emit('cooldownReset', command, {'userIdentity': userIdentity});
        notifyListeners();
      });
  final DateTime Function() now;
  List<ChatCommand> _commands = [];
  Map<String, CommandCounters> _counters = {};
  final _globalReady = <String, DateTime>{};
  final _userReady = <String, DateTime>{};
  Future<void> _tail = Future.value();
  bool _loaded = false, _closed = false;
  Object? error;
  String? lastDecision;
  List<ChatCommand> get commands => List.unmodifiable(_commands);
  bool get loaded => _loaded;
  CommandCounters countersFor(String id) => _counters[id] ?? CommandCounters();

  Future<void> load() async {
    try {
      final commands = await repository.load();
      _validate(commands);
      final counters = await repository.loadCounters();
      _commands = commands;
      _counters = _persistedCounters(counters);
      _loaded = true;
      error = null;
    } catch (failure) {
      error = failure;
      _loaded = false;
    }
    if (!_closed) notifyListeners();
  }

  void _validate(List<ChatCommand> commands) {
    if (commands.map((c) => c.id).toSet().length != commands.length) {
      throw const FormatException('Duplicate command IDs.');
    }
    for (var a = 0; a < commands.length; a++) {
      final left = commands[a];
      for (var b = a + 1; b < commands.length; b++) {
        final right = commands[b];
        if (!left.enabled ||
            !right.enabled ||
            left.matchMode != right.matchMode ||
            !left.platforms.any(right.platforms.contains) ||
            !left.origins.any(right.origins.contains)) {
          continue;
        }
        for (final name in [left.pattern, ...left.aliases]) {
          if ([right.pattern, ...right.aliases].any(
            (other) => left.caseSensitive && right.caseSensitive
                ? name == other
                : name.toLowerCase() == other.toLowerCase(),
          )) {
            throw FormatException(
              'The pattern "$name" is already used on this platform.',
            );
          }
        }
      }
    }
  }

  Future<void> save(ChatCommand command) => _serialize(() async {
    _ensureReady();
    final next = [..._commands];
    final index = next.indexWhere((c) => c.id == command.id);
    if (index < 0) {
      next.add(command);
    } else {
      next[index] = command;
    }
    _validate(next);
    await repository.save(next);
    _commands = next;
    _emit(index < 0 ? 'added' : 'updated', command);
    notifyListeners();
  });

  Future<void> delete(String id) => _serialize(() async {
    _ensureReady();
    final command = commandById(id);
    final next = _commands.where((c) => c.id != id).toList();
    await repository.save(next);
    _commands = next;
    _emit('deleted', command);
    // Historical counters are intentionally retained when a definition is deleted.
    notifyListeners();
  });

  Future<void> resetCounters(String id) => _serialize(() async {
    _ensureReady();
    final command = commandById(id);
    final next = {..._counters, id: CommandCounters()};
    await repository.saveCounters(_persistedCounters(next));
    _counters = next;
    _emit('countersReset', command, {'usersOnly': false});
    notifyListeners();
  });

  Future<void> move(String id, int offset) => _serialize(() async {
    _ensureReady();
    final index = _commands.indexWhere((command) => command.id == id);
    final target = index + offset;
    if (index < 0 || target < 0 || target >= _commands.length) return;
    final next = [..._commands];
    next.insert(target, next.removeAt(index));
    await repository.save(next);
    _commands = next;
    notifyListeners();
  });

  Future<void> handle(ChatMessage message) => _serialize(() async {
    if (!_loaded || _closed || message.deleted || message.userId.isEmpty) {
      return;
    }
    if (isEnabled != null && !await isEnabled!()) {
      lastDecision = 'Chat Commands plugin is disabled';
      notifyListeners();
      return;
    }
    for (final command in _commands) {
      if (!command.enabled || !command.platforms.contains(message.platform)) {
        continue;
      }
      if (!command.origins.contains(message.origin) ||
          (command.ignoreBots && message.isBot) ||
          (command.ignoreInternal && message.origin == ChatOrigin.internal)) {
        continue;
      }
      CommandMatch? match;
      Set<String> memberships = {};
      try {
        match = await command.matchAsync(message.text);
        if (match == null) continue;
        if (command.groups.isNotEmpty) {
          final resolver = groupMemberships;
          if (resolver == null) {
            throw StateError('Viewer group storage is unavailable.');
          }
          memberships = await resolver(message, command.groups);
        }
      } catch (failure) {
        error = failure;
        lastDecision = '${command.name}: matching or group lookup failed';
        _emit('rejected', command, {
          ...message.context,
          'reason': 'configuration',
        });
        break;
      }
      if (!command.grants(message, memberships)) {
        lastDecision = '${command.name}: permission denied';
        _emit('rejected', command, {
          ...message.context,
          'reason': 'permission',
        });
        break;
      }
      if (match.arguments.length < command.minimumArguments) {
        lastDecision = '${command.name}: missing arguments';
        _emit('rejected', command, {...message.context, 'reason': 'arguments'});
        break;
      }
      final instant = now();
      final userKey = '${command.id}:${message.userIdentity}';
      if (!(command.broadcasterBypass && message.isBroadcaster) &&
          ((_globalReady[command.id]?.isAfter(instant) ?? false) ||
              (_userReady[userKey]?.isAfter(instant) ?? false))) {
        lastDecision = '${command.name}: cooldown';
        _emit('cooldown', command, {
          ...message.context,
          'globalRemainingMs':
              (_globalReady[command.id]?.difference(instant).inMilliseconds ??
                      0)
                  .clamp(0, 86400000),
          'userRemainingMs':
              (_userReady[userKey]?.difference(instant).inMilliseconds ?? 0)
                  .clamp(0, 86400000),
        });
        break;
      }
      // Reserve both cooldowns before any asynchronous file/queue operation.
      _globalReady[command.id] = instant.add(command.globalCooldown);
      _userReady.removeWhere((_, deadline) => !deadline.isAfter(instant));
      if (command.userCooldown > Duration.zero) {
        _userReady[userKey] = instant.add(command.userCooldown);
      }
      final counters = _counters.putIfAbsent(command.id, CommandCounters.new);
      counters.accepted++;
      counters.users.update(
        message.userIdentity,
        (n) => n + 1,
        ifAbsent: () => 1,
      );
      try {
        await repository.saveCounters(_persistedCounters(_counters));
        final values = <String, dynamic>{
          ...message.context,
          'command': command.pattern,
          'commandId': command.id,
          'matchedCommand': match.matchedText,
          'arguments': match.arguments,
          'captures': match.captures,
          'argumentText': match.argumentText,
          'commandCount': counters.accepted,
          'userCommandCount': counters.users[message.userIdentity],
        };
        _emit('triggered', command, values);
        await execute(command, values);
        counters.dispatched++;
        lastDecision = '${command.name}: queued';
        error = null;
      } catch (failure) {
        counters.failed++;
        lastDecision = '${command.name}: failed';
        _emit('failed', command, {...message.context});
        error = failure;
      }
      try {
        await repository.saveCounters(_persistedCounters(_counters));
      } catch (failure) {
        error = failure;
      }
      break; // A message dispatches at most one command, in visible list order.
    }
    if (!_closed) notifyListeners();
  });

  Future<void> _serialize(Future<void> Function() action) {
    if (_closed) return Future.error(StateError('Command manager is closed.'));
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  void _ensureReady() {
    if (!_loaded) {
      throw StateError(
        'Commands could not be loaded; existing files are preserved.',
      );
    }
  }

  Future<void> close() async {
    _closed = true;
    await _tail;
    dispose();
  }
}
