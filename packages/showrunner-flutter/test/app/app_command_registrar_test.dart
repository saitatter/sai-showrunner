import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/app/commands/app_command.dart';
import 'package:showrunner_flutter/app/commands/app_command_registrar.dart';
import 'package:showrunner_flutter/app/workspace_registry.dart';

void main() {
  test('builds the shared application command surface', () async {
    var activeAutomation = false;
    var dirtyAutomation = false;
    var undoAvailable = true;
    var executed = false;
    final registry = AppCommandRegistrar(
      selectedWorkspace: () => WorkspaceIds.graph,
      graphEditorVisible: true,
      hasActiveAutomation: () => activeAutomation,
      hasDirtyAutomation: () => dirtyAutomation,
      canCloseWorkspace: () => true,
      canCloseOthers: () => true,
      onNewAutomation: () async {},
      onNewAutomationFromStarter: () async {},
      onNewProfile: () async {},
      onSave: () async {},
      onSaveAll: () async {},
      onOpenDestination: (_) async {},
      onCloseWorkspace: (_) async {},
      onCloseOthers: () async {},
      onExit: () async {},
      canUndo: () => undoAvailable,
      canRedo: () => false,
      onUndo: () async => executed = true,
      onRedo: () async {},
      onCopy: (_) async {},
      onPaste: (_) async {},
      onCut: (_) async {},
      onFrameSelection: () async {},
      onFitGraph: () async {},
      onResetSample: () async {},
      onRunAutomation: () async {},
      onOpenExternal: (_) async {},
      onOpenLogFolder: () async {},
    ).build();

    expect(registry.find('file.save'), isNotNull);
    expect(registry.find('edit.undo'), isNotNull);
    expect(registry.find('run.automation'), isNotNull);
    expect(registry.find('help.updates'), isNotNull);
    expect(registry.shortcutCommands.length, greaterThanOrEqualTo(8));

    final context = const AppCommandContext();
    expect(registry.canExecute('file.save', context), isFalse);
    expect(registry.canExecute('edit.undo', context), isTrue);
    await registry.run('edit.undo', context);
    expect(executed, isTrue);

    activeAutomation = true;
    dirtyAutomation = true;
    undoAvailable = false;
    expect(registry.canExecute('file.save', context), isTrue);
    expect(registry.canExecute('file.saveAll', context), isTrue);
    expect(registry.canExecute('edit.undo', context), isFalse);
  });
}
