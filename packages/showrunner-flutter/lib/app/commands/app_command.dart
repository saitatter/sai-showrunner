import 'dart:async';

import 'package:flutter/widgets.dart';

final class AppCommandContext {
  const AppCommandContext({this.buildContext});

  final BuildContext? buildContext;
}

typedef AppCommandAction = FutureOr<void> Function(AppCommandContext context);
typedef AppCommandAvailability = bool Function(AppCommandContext context);

/// A single application operation shared by menus, toolbars and shortcuts.
///
/// Commands deliberately own no widget state. They receive the current UI
/// context only when executed, while the page that owns the application state
/// supplies the action and availability callbacks.
final class AppCommand {
  const AppCommand({
    required this.id,
    required this.label,
    required this.execute,
    this.icon,
    this.shortcut,
    this.additionalShortcuts = const [],
    this.canExecute = _alwaysAvailable,
  });

  final String id;
  final String label;
  final IconData? icon;
  final ShortcutActivator? shortcut;
  final List<ShortcutActivator> additionalShortcuts;
  final AppCommandAction execute;
  final AppCommandAvailability canExecute;

  Iterable<ShortcutActivator> get activators => [
    ...(shortcut == null
        ? const <ShortcutActivator>[]
        : <ShortcutActivator>[shortcut!]),
    ...additionalShortcuts,
  ];

  static bool _alwaysAvailable(AppCommandContext context) => true;
}

final class AppCommandRegistry {
  AppCommandRegistry(Iterable<AppCommand> commands) {
    for (final command in commands) {
      register(command);
    }
  }

  final _commands = <String, AppCommand>{};

  Iterable<AppCommand> get commands => _commands.values;

  Iterable<AppCommand> get shortcutCommands =>
      _commands.values.where((command) => command.activators.isNotEmpty);

  void register(AppCommand command) {
    if (_commands.containsKey(command.id)) {
      throw ArgumentError.value(
        command.id,
        'command.id',
        'Already registered.',
      );
    }
    _commands[command.id] = command;
  }

  AppCommand? find(String id) => _commands[id];

  bool canExecute(String id, AppCommandContext context) {
    final command = _commands[id];
    return command != null && command.canExecute(context);
  }

  Future<void> run(String id, AppCommandContext context) async {
    final command = _commands[id];
    if (command == null || !command.canExecute(context)) return;
    await command.execute(context);
  }
}
