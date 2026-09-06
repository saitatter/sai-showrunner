import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/app/workspace_document_manager.dart';
import 'package:showrunner_flutter/app/workspace_registry.dart';

void main() {
  test('opens and selects each workspace once', () {
    final manager = WorkspaceDocumentManager();

    manager.open(WorkspaceIds.profiles);
    manager.open(WorkspaceIds.profiles);
    expect(manager.openWorkspaces, [WorkspaceIds.graph, WorkspaceIds.profiles]);
    expect(manager.select(WorkspaceIds.profiles), isTrue);
    expect(manager.selectedWorkspace, WorkspaceIds.profiles);
    expect(manager.select(WorkspaceIds.profiles), isFalse);
  });

  test('closes the active workspace and selects its predecessor', () {
    final manager = WorkspaceDocumentManager(
      initial: [WorkspaceIds.graph, WorkspaceIds.profiles, WorkspaceIds.about],
    );
    manager.select(WorkspaceIds.profiles);

    expect(manager.close(WorkspaceIds.profiles), isTrue);
    expect(manager.openWorkspaces, [WorkspaceIds.graph, WorkspaceIds.about]);
    expect(manager.selectedWorkspace, WorkspaceIds.graph);
    expect(manager.close(WorkspaceIds.graph), isTrue);
    expect(manager.openWorkspaces, [WorkspaceIds.about]);
    expect(manager.selectedWorkspace, WorkspaceIds.about);
    expect(manager.close(WorkspaceIds.about), isFalse);
  });

  test('closes other workspaces without losing the active one', () {
    final manager = WorkspaceDocumentManager(
      initial: [WorkspaceIds.graph, WorkspaceIds.profiles, WorkspaceIds.about],
    );
    manager.select(WorkspaceIds.about);

    expect(manager.closeOthers(), isTrue);
    expect(manager.openWorkspaces, [WorkspaceIds.about]);
    expect(manager.selectedWorkspace, WorkspaceIds.about);
    expect(manager.closeOthers(), isFalse);
  });

  test('reorders workspaces while preserving the active selection', () {
    final manager = WorkspaceDocumentManager(
      initial: [WorkspaceIds.graph, WorkspaceIds.profiles, WorkspaceIds.about],
    );
    manager.select(WorkspaceIds.about);

    expect(manager.reorder(2, 0), isTrue);
    expect(manager.openWorkspaces, [WorkspaceIds.about, WorkspaceIds.graph, WorkspaceIds.profiles]);
    expect(manager.selectedWorkspace, WorkspaceIds.about);
    expect(manager.reorder(0, 2), isTrue);
    expect(manager.openWorkspaces, [WorkspaceIds.graph, WorkspaceIds.profiles, WorkspaceIds.about]);
    expect(manager.reorder(-1, 0), isFalse);
    expect(manager.reorder(0, 8), isFalse);
  });

  test('restores a valid selection and falls back to the first workspace', () {
    final manager = WorkspaceDocumentManager();

    manager.restore(
      openWorkspaces: [
        WorkspaceIds.profiles,
        WorkspaceIds.profiles,
        WorkspaceIds.about,
      ],
      selected: WorkspaceIds.about,
    );
    expect(manager.openWorkspaces, [WorkspaceIds.profiles, WorkspaceIds.about]);
    expect(manager.selectedWorkspace, WorkspaceIds.about);
    expect(manager.toSettings(), {
      'openWorkspaceTabs': [4, 8],
      'selectedWorkspace': 8,
    });

    manager.restore(openWorkspaces: const [], selected: WorkspaceIds.updates);
    expect(manager.openWorkspaces, [WorkspaceIds.graph]);
    expect(manager.selectedWorkspace, WorkspaceIds.graph);
  });
}
