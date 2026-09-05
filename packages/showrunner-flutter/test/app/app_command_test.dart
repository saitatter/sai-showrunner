import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/app/commands/app_command.dart';

void main() {
  test('registers stable commands and exposes shortcut commands', () {
    final registry = AppCommandRegistry([
      AppCommand(
        id: 'file.save',
        label: 'Save',
        shortcut: const SingleActivator(LogicalKeyboardKey.keyS, control: true),
        additionalShortcuts: const [
          SingleActivator(LogicalKeyboardKey.keyS, meta: true),
        ],
        execute: (_) {},
      ),
      AppCommand(id: 'help.about', label: 'About', execute: (_) {}),
    ]);

    expect(registry.find('file.save')?.label, 'Save');
    expect(registry.shortcutCommands.map((command) => command.id), [
      'file.save',
    ]);
    expect(registry.find('file.save')!.activators, hasLength(2));
  });

  test('keeps close-others as a first-class command', () {
    final registry = AppCommandRegistry([
      AppCommand(
        id: 'file.closeOthers',
        label: 'Close other workspaces',
        execute: (_) {},
      ),
    ]);

    expect(registry.find('file.closeOthers')?.label, 'Close other workspaces');
  });

  test('does not execute unavailable commands', () async {
    var executions = 0;
    final registry = AppCommandRegistry([
      AppCommand(
        id: 'file.save',
        label: 'Save',
        canExecute: (_) => false,
        execute: (_) => executions++,
      ),
    ]);

    await registry.run('file.save', const AppCommandContext());

    expect(executions, 0);
  });

  test('rejects duplicate command ids', () {
    expect(
      () => AppCommandRegistry([
        AppCommand(id: 'duplicate', label: 'One', execute: (_) {}),
        AppCommand(id: 'duplicate', label: 'Two', execute: (_) {}),
      ]),
      throwsArgumentError,
    );
  });
}
