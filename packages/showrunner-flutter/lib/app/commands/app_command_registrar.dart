import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../workspace_registry.dart';
import 'app_command.dart';

/// Application-owned callbacks used to assemble the command surface.
///
/// The registrar knows command IDs, labels, shortcuts, and availability. The
/// page that owns the live application state supplies the effects. This keeps
/// menus, keyboard routing, and future toolbars on the same command registry
/// without making the composition root contain every command definition.
final class AppCommandRegistrar {
  const AppCommandRegistrar({
    required this.selectedWorkspace,
    required this.graphEditorVisible,
    required this.hasActiveAutomation,
    required this.hasDirtyAutomation,
    required this.canCloseWorkspace,
    required this.canCloseOthers,
    required this.onNewAutomation,
    required this.onNewAutomationFromStarter,
    required this.onNewProfile,
    required this.onSave,
    required this.onSaveAll,
    required this.onOpenDestination,
    required this.onCloseWorkspace,
    required this.onCloseOthers,
    required this.onExit,
    required this.canUndo,
    required this.canRedo,
    required this.onUndo,
    required this.onRedo,
    required this.onCopy,
    required this.onPaste,
    required this.onCut,
    required this.onFrameSelection,
    required this.onFitGraph,
    required this.onResetSample,
    required this.onRunAutomation,
    required this.onOpenExternal,
    required this.onOpenLogFolder,
  });

  final WorkspaceId Function() selectedWorkspace;
  final bool graphEditorVisible;
  final bool Function() hasActiveAutomation;
  final bool Function() hasDirtyAutomation;
  final bool Function() canCloseWorkspace;
  final bool Function() canCloseOthers;

  final FutureOr<void> Function() onNewAutomation;
  final FutureOr<void> Function() onNewAutomationFromStarter;
  final FutureOr<void> Function() onNewProfile;
  final FutureOr<void> Function() onSave;
  final FutureOr<void> Function() onSaveAll;
  final FutureOr<void> Function(WorkspaceId workspace) onOpenDestination;
  final FutureOr<void> Function(WorkspaceId workspace) onCloseWorkspace;
  final FutureOr<void> Function() onCloseOthers;
  final FutureOr<void> Function() onExit;
  final bool Function() canUndo;
  final bool Function() canRedo;
  final FutureOr<void> Function() onUndo;
  final FutureOr<void> Function() onRedo;
  final FutureOr<void> Function(BuildContext context) onCopy;
  final FutureOr<void> Function(BuildContext context) onPaste;
  final FutureOr<void> Function(BuildContext context) onCut;
  final FutureOr<void> Function() onFrameSelection;
  final FutureOr<void> Function() onFitGraph;
  final FutureOr<void> Function() onResetSample;
  final FutureOr<void> Function() onRunAutomation;
  final FutureOr<void> Function(Uri uri) onOpenExternal;
  final FutureOr<void> Function() onOpenLogFolder;

  bool get _isGraphWorkspace =>
      selectedWorkspace() == WorkspaceIds.graph && graphEditorVisible;

  AppCommandRegistry build() => AppCommandRegistry([
    AppCommand(
      id: 'file.newAutomation',
      label: 'New automation',
      icon: Icons.bolt,
      execute: (_) => onNewAutomation(),
    ),
    AppCommand(
      id: 'file.newAutomationFromStarter',
      label: 'New automation from starter',
      icon: Icons.auto_awesome,
      execute: (_) => onNewAutomationFromStarter(),
    ),
    AppCommand(
      id: 'file.newProfile',
      label: 'New profile',
      icon: Icons.people_alt,
      execute: (_) => onNewProfile(),
    ),
    AppCommand(
      id: 'file.save',
      label: 'Save automation',
      icon: Icons.save,
      shortcut: const SingleActivator(LogicalKeyboardKey.keyS, control: true),
      additionalShortcuts: const [
        SingleActivator(LogicalKeyboardKey.keyS, meta: true),
      ],
      canExecute: (_) => hasActiveAutomation(),
      execute: (_) => onSave(),
    ),
    AppCommand(
      id: 'file.saveAll',
      label: 'Save all',
      icon: Icons.save_as,
      shortcut: const SingleActivator(
        LogicalKeyboardKey.keyS,
        control: true,
        shift: true,
      ),
      additionalShortcuts: const [
        SingleActivator(LogicalKeyboardKey.keyS, meta: true, shift: true),
      ],
      canExecute: (_) => hasDirtyAutomation(),
      execute: (_) => onSaveAll(),
    ),
    AppCommand(
      id: 'file.settings',
      label: 'Settings',
      icon: Icons.settings,
      execute: (_) => onOpenDestination(WorkspaceIds.settings),
    ),
    AppCommand(
      id: 'file.close',
      label: 'Close workspace',
      icon: Icons.close,
      shortcut: const SingleActivator(LogicalKeyboardKey.keyW, control: true),
      additionalShortcuts: const [
        SingleActivator(LogicalKeyboardKey.keyW, meta: true),
      ],
      canExecute: (_) => canCloseWorkspace(),
      execute: (_) => onCloseWorkspace(selectedWorkspace()),
    ),
    AppCommand(
      id: 'file.closeOthers',
      label: 'Close other workspaces',
      icon: Icons.tab_unselected,
      canExecute: (_) => canCloseOthers(),
      execute: (_) => onCloseOthers(),
    ),
    AppCommand(
      id: 'file.exit',
      label: 'Exit',
      icon: Icons.exit_to_app,
      execute: (_) => onExit(),
    ),
    AppCommand(
      id: 'edit.undo',
      label: 'Undo',
      icon: Icons.undo,
      shortcut: const SingleActivator(LogicalKeyboardKey.keyZ, control: true),
      additionalShortcuts: const [
        SingleActivator(LogicalKeyboardKey.keyZ, meta: true),
      ],
      canExecute: (_) => _isGraphWorkspace && canUndo(),
      execute: (_) => onUndo(),
    ),
    AppCommand(
      id: 'edit.redo',
      label: 'Redo',
      icon: Icons.redo,
      shortcut: const SingleActivator(
        LogicalKeyboardKey.keyZ,
        control: true,
        shift: true,
      ),
      additionalShortcuts: const [
        SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true),
      ],
      canExecute: (_) => _isGraphWorkspace && canRedo(),
      execute: (_) => onRedo(),
    ),
    AppCommand(
      id: 'edit.copy',
      label: 'Copy selected nodes',
      icon: Icons.copy,
      shortcut: const SingleActivator(LogicalKeyboardKey.keyC, control: true),
      additionalShortcuts: const [
        SingleActivator(LogicalKeyboardKey.keyC, meta: true),
      ],
      canExecute: (_) => _isGraphWorkspace,
      execute: (context) {
        final buildContext = context.buildContext;
        if (buildContext != null) return onCopy(buildContext);
      },
    ),
    AppCommand(
      id: 'edit.paste',
      label: 'Paste nodes',
      icon: Icons.content_paste,
      shortcut: const SingleActivator(LogicalKeyboardKey.keyV, control: true),
      additionalShortcuts: const [
        SingleActivator(LogicalKeyboardKey.keyV, meta: true),
      ],
      canExecute: (_) => _isGraphWorkspace,
      execute: (context) {
        final buildContext = context.buildContext;
        if (buildContext != null) return onPaste(buildContext);
      },
    ),
    AppCommand(
      id: 'edit.cut',
      label: 'Cut selected nodes',
      icon: Icons.content_cut,
      shortcut: const SingleActivator(LogicalKeyboardKey.keyX, control: true),
      additionalShortcuts: const [
        SingleActivator(LogicalKeyboardKey.keyX, meta: true),
      ],
      canExecute: (_) => _isGraphWorkspace,
      execute: (context) {
        final buildContext = context.buildContext;
        if (buildContext != null) return onCut(buildContext);
      },
    ),
    AppCommand(
      id: 'edit.frameSelection',
      label: 'Frame selected nodes',
      icon: Icons.crop_free,
      canExecute: (_) => _isGraphWorkspace,
      execute: (_) => onFrameSelection(),
    ),
    AppCommand(
      id: 'view.fitGraph',
      label: 'Fit graph',
      icon: Icons.fit_screen,
      shortcut: const SingleActivator(LogicalKeyboardKey.home),
      canExecute: (_) => _isGraphWorkspace,
      execute: (_) => onFitGraph(),
    ),
    AppCommand(
      id: 'view.resetSample',
      label: 'Reset sample graph',
      icon: Icons.refresh,
      canExecute: (_) => _isGraphWorkspace,
      execute: (_) => onResetSample(),
    ),
    AppCommand(
      id: 'run.automation',
      label: 'Run automation',
      icon: Icons.play_arrow,
      shortcut: const SingleActivator(LogicalKeyboardKey.f6),
      canExecute: (_) => hasActiveAutomation(),
      execute: (_) => onRunAutomation(),
    ),
    AppCommand(
      id: 'help.about',
      label: 'About ShowRunner',
      icon: Icons.info,
      execute: (_) => onOpenDestination(WorkspaceIds.about),
    ),
    AppCommand(
      id: 'help.updates',
      label: 'Updates',
      icon: Icons.system_update_alt,
      execute: (_) => onOpenDestination(WorkspaceIds.updates),
    ),
    AppCommand(
      id: 'help.discord',
      label: 'Discord',
      icon: Icons.forum,
      execute: (_) =>
          onOpenExternal(Uri.parse('https://discord.gg/txt4DUzYJM')),
    ),
    AppCommand(
      id: 'help.openLogFolder',
      label: 'Open log folder',
      icon: Icons.folder,
      execute: (_) => onOpenLogFolder(),
    ),
  ]);
}
