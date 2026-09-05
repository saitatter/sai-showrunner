/// Owns the open workspace documents and the active document.
///
/// The persisted representation intentionally remains a list of workspace
/// indices so existing user settings continue to load without an upgrade.
/// Widgets should use this manager instead of mutating the tab list directly.
final class WorkspaceDocumentManager {
  WorkspaceDocumentManager({Iterable<int> initial = const [0]}) {
    restore(openWorkspaceIndices: initial);
  }

  final _openWorkspaceIndices = <int>[];
  int _selectedWorkspaceIndex = 0;

  List<int> get openWorkspaceIndices =>
      List<int>.unmodifiable(_openWorkspaceIndices);

  int get selectedWorkspaceIndex => _selectedWorkspaceIndex;

  bool get canClose => _openWorkspaceIndices.length > 1;

  bool get canCloseOthers => canClose;

  void open(int workspaceIndex) {
    if (!_openWorkspaceIndices.contains(workspaceIndex)) {
      _openWorkspaceIndices.add(workspaceIndex);
    }
  }

  bool select(int workspaceIndex) {
    if (!_openWorkspaceIndices.contains(workspaceIndex)) return false;
    final changed = _selectedWorkspaceIndex != workspaceIndex;
    _selectedWorkspaceIndex = workspaceIndex;
    return changed;
  }

  /// Restores a session while guaranteeing that at least one document exists.
  void restore({required Iterable<int> openWorkspaceIndices, int? selected}) {
    _openWorkspaceIndices
      ..clear()
      ..addAll(openWorkspaceIndices.toSet());
    if (_openWorkspaceIndices.isEmpty) _openWorkspaceIndices.add(0);
    _selectedWorkspaceIndex =
        selected != null && _openWorkspaceIndices.contains(selected)
        ? selected
        : _openWorkspaceIndices.first;
  }

  bool close(int workspaceIndex) {
    if (!canClose) return false;
    final closingPosition = _openWorkspaceIndices.indexOf(workspaceIndex);
    if (closingPosition < 0) return false;
    final wasSelected = _selectedWorkspaceIndex == workspaceIndex;
    _openWorkspaceIndices.removeAt(closingPosition);
    if (wasSelected) {
      final nextPosition = closingPosition > 0 ? closingPosition - 1 : 0;
      _selectedWorkspaceIndex = _openWorkspaceIndices[nextPosition];
    }
    return true;
  }

  bool closeOthers() {
    if (!canClose || !_openWorkspaceIndices.contains(_selectedWorkspaceIndex)) {
      return false;
    }
    _openWorkspaceIndices
      ..clear()
      ..add(_selectedWorkspaceIndex);
    return true;
  }

  Map<String, dynamic> toSettings() => {
    'openWorkspaceTabs': openWorkspaceIndices,
    'selectedWorkspace': selectedWorkspaceIndex,
  };
}
