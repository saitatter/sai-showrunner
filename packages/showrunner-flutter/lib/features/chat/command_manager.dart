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
  }) : now = now ?? DateTime.now;
  final CommandRepository repository;
  final CommandExecutor execute;
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
      _counters = counters;
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
            !left.platforms.any(right.platforms.contains)) {
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
    notifyListeners();
  });

  Future<void> delete(String id) => _serialize(() async {
    _ensureReady();
    final next = _commands.where((c) => c.id != id).toList();
    await repository.save(next);
    _commands = next;
    // Historical counters are intentionally retained when a definition is deleted.
    notifyListeners();
  });

  Future<void> resetCounters(String id) => _serialize(() async {
    _ensureReady();
    final next = {..._counters, id: CommandCounters()};
    await repository.saveCounters(next);
    _counters = next;
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
    if (!_loaded ||
        _closed ||
        message.deleted ||
        message.isBot ||
        message.userId.isEmpty) {
      return;
    }
    for (final command in _commands) {
      if (!command.enabled || !command.platforms.contains(message.platform)) {
        continue;
      }
      final match = command.match(message.text);
      if (match == null) continue;
      if (!message.permits(command.permission)) {
        lastDecision = '${command.name}: permission denied';
        break;
      }
      if (match.arguments.length < command.minimumArguments) {
        lastDecision = '${command.name}: missing arguments';
        break;
      }
      final instant = now();
      final userKey = '${command.id}:${message.userIdentity}';
      if ((_globalReady[command.id]?.isAfter(instant) ?? false) ||
          (_userReady[userKey]?.isAfter(instant) ?? false)) {
        lastDecision = '${command.name}: cooldown';
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
        await repository.saveCounters(_counters);
        await execute(command, {
          ...message.context,
          'command': command.pattern,
          'commandId': command.id,
          'matchedCommand': match.matchedText,
          'arguments': match.arguments,
          'argumentText': match.argumentText,
          'commandCount': counters.accepted,
          'userCommandCount': counters.users[message.userIdentity],
        });
        counters.dispatched++;
        lastDecision = '${command.name}: queued';
        error = null;
      } catch (failure) {
        counters.failed++;
        lastDecision = '${command.name}: failed';
        error = failure;
      }
      try {
        await repository.saveCounters(_counters);
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
