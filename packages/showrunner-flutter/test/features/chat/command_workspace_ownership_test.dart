import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/features/chat/commands_workspace.dart';
import 'package:showrunner_flutter/features/chat/command_editor_dialog.dart';
import 'package:showrunner_flutter/features/chat/chat_command.dart';
import 'package:showrunner_flutter/features/chat/command_manager.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';

void main() {
  testWidgets('a command dialog cannot save through a replacement manager', (
    tester,
  ) async {
    final root = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('command-view-'),
    ))!;
    final (first, second) = (await tester.runAsync(() async {
      final first = ChatCommandManager(
        repository: CommandRepository(Directory('${root.path}/first')),
        execute: (_, _) async {},
      );
      final second = ChatCommandManager(
        repository: CommandRepository(Directory('${root.path}/second')),
        execute: (_, _) async {},
      );
      await first.load();
      await second.load();
      return (first, second);
    }))!;
    final data = ShowRunnerDataService(root);
    addTearDown(
      () => tester.runAsync(() async {
        await first.close();
        await second.close();
        await root.delete(recursive: true);
      }),
    );
    Widget app(ChatCommandManager manager) => MaterialApp(
      home: Scaffold(
        body: CommandsWorkspace(manager: manager, dataService: data),
      ),
    );
    await tester.pumpWidget(app(first));
    await tester.runAsync(() => tester.tap(find.text('New command')));
    for (var i = 0; i < 200; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 50));
      if (find.byType(CommandEditorDialog).evaluate().isNotEmpty) break;
    }
    expect(find.byType(CommandEditorDialog), findsOneWidget);
    await tester.pumpWidget(app(second));
    Navigator.of(tester.element(find.byType(CommandEditorDialog))).pop(
      ChatCommand(
        id: 'new',
        name: 'Old draft',
        pattern: '!old',
        automationFile: 'example.yaml',
      ),
    );
    await tester.pumpAndSettle();
    expect(first.commands, isEmpty);
    expect(second.commands, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
