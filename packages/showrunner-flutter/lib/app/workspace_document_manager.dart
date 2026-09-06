import 'workspace_registry.dart';

/// Owns the open workspace documents and the active document.
///
/// The persisted representation intentionally remains a list of legacy
/// workspace indices so existing user settings continue to load without an
/// upgrade. Widgets use stable IDs instead of mutating or comparing indices.
final class WorkspaceDocumentManager {
  WorkspaceDocumentManager({
    Iterable<WorkspaceId> initial = const [WorkspaceIds.graph],
  }) {
    restore(openWorkspaces: initial);
  }

  final _openWorkspaces = <WorkspaceId>[];
  WorkspaceId _selectedWorkspace = WorkspaceIds.home;

  List<WorkspaceId> get openWorkspaces => List.unmodifiable(_openWorkspaces);

  WorkspaceId get selectedWorkspace => _selectedWorkspace;

  bool get canClose => _openWorkspaces.length > 1;

  bool get canCloseOthers => canClose;

  void open(WorkspaceId workspace) {
    if (!_openWorkspaces.contains(workspace)) {
      _openWorkspaces.add(workspace);
    }
  }

  bool select(WorkspaceId workspace) {
    if (!_openWorkspaces.contains(workspace)) return false;
    final changed = _selectedWorkspace != workspace;
    _selectedWorkspace = workspace;
    return changed;
  }

  /// Restores a session while guaranteeing that at least one document exists.
  void restore({
    required Iterable<WorkspaceId> openWorkspaces,
    WorkspaceId? selected,
  }) {
    _openWorkspaces
      ..clear()
      ..addAll(openWorkspaces.toSet());
    if (_openWorkspaces.isEmpty) _openWorkspaces.add(WorkspaceIds.graph);
    _selectedWorkspace =
        selected != null && _openWorkspaces.contains(selected)
        ? selected
        : _openWorkspaces.first;
  }

  bool close(WorkspaceId workspace) {
    if (!canClose) return false;
    final closingPosition = _openWorkspaces.indexOf(workspace);
    if (closingPosition < 0) return false;
    final wasSelected = _selectedWorkspace == workspace;
    _openWorkspaces.removeAt(closingPosition);
    if (wasSelected) {
      final nextPosition = closingPosition > 0 ? closingPosition - 1 : 0;
      _selectedWorkspace = _openWorkspaces[nextPosition];
    }
    return true;
  }

  bool closeOthers() {
    if (!canClose || !_openWorkspaces.contains(_selectedWorkspace)) {
      return false;
    }
    _openWorkspaces
      ..clear()
      ..add(_selectedWorkspace);
    return true;
  }

  /// Reorders an open document by its final tab position.
  bool reorder(int oldPosition, int newPosition) {
    if (oldPosition < 0 || oldPosition >= _openWorkspaces.length) {
      return false;
    }
    if (newPosition < 0 || newPosition >= _openWorkspaces.length) {
      return false;
    }
    if (oldPosition == newPosition) return false;
    final document = _openWorkspaces.removeAt(oldPosition);
    _openWorkspaces.insert(newPosition, document);
    return true;
  }

  Map<String, dynamic> toSettings() => {
    'openWorkspaceTabs': openWorkspaces
        .map(WorkspaceIds.legacyIndex)
        .toList(growable: false),
    'selectedWorkspace': WorkspaceIds.legacyIndex(selectedWorkspace),
  };
}
