import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/app/workspace_document_manager.dart';

void main() {
  test('opens and selects each workspace once', () {
    final manager = WorkspaceDocumentManager();

    manager.open(4);
    manager.open(4);
    expect(manager.openWorkspaceIndices, [0, 4]);
    expect(manager.select(4), isTrue);
    expect(manager.selectedWorkspaceIndex, 4);
    expect(manager.select(4), isFalse);
  });

  test('closes the active workspace and selects its predecessor', () {
    final manager = WorkspaceDocumentManager(initial: [0, 4, 8]);
    manager.select(4);

    expect(manager.close(4), isTrue);
    expect(manager.openWorkspaceIndices, [0, 8]);
    expect(manager.selectedWorkspaceIndex, 0);
    expect(manager.close(0), isTrue);
    expect(manager.openWorkspaceIndices, [8]);
    expect(manager.selectedWorkspaceIndex, 8);
    expect(manager.close(8), isFalse);
  });

  test('closes other workspaces without losing the active one', () {
    final manager = WorkspaceDocumentManager(initial: [0, 4, 8]);
    manager.select(8);

    expect(manager.closeOthers(), isTrue);
    expect(manager.openWorkspaceIndices, [8]);
    expect(manager.selectedWorkspaceIndex, 8);
    expect(manager.closeOthers(), isFalse);
  });

  test('restores a valid selection and falls back to the first workspace', () {
    final manager = WorkspaceDocumentManager();

    manager.restore(openWorkspaceIndices: [4, 4, 8], selected: 8);
    expect(manager.openWorkspaceIndices, [4, 8]);
    expect(manager.selectedWorkspaceIndex, 8);
    expect(manager.toSettings(), {
      'openWorkspaceTabs': [4, 8],
      'selectedWorkspace': 8,
    });

    manager.restore(openWorkspaceIndices: const [], selected: 99);
    expect(manager.openWorkspaceIndices, [0]);
    expect(manager.selectedWorkspaceIndex, 0);
  });
}
