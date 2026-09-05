import '../schema/automation.dart';

/// An automation resource that is open in the graph workspace.
///
/// [data] is always the latest in-memory representation. It is intentionally
/// kept separate from the editor widget so switching documents cannot discard
/// edits that have not been written to disk yet.
final class AutomationDocumentSession {
  AutomationDocumentSession({
    required this.fileName,
    required this.data,
    this.dirty = false,
  });

  final String fileName;
  AutomationData data;
  bool dirty;
}

/// Owns graph-resource documents independently of the visual editor.
///
/// The application currently renders one canvas and swaps its contents when
/// the active document changes. Keeping all sessions here gives that canvas
/// proper document semantics today and leaves room for multiple mounted
/// canvases later without changing persistence or close behavior.
final class AutomationDocumentManager {
  final _documents = <AutomationDocumentSession>[];
  String? _activeFileName;

  List<AutomationDocumentSession> get documents =>
      List<AutomationDocumentSession>.unmodifiable(_documents);

  String? get activeFileName => _activeFileName;

  AutomationDocumentSession? get active =>
      _activeFileName == null ? null : _find(_activeFileName!);

  AutomationDocumentSession? find(String fileName) => _find(fileName);

  bool get hasDocuments => _documents.isNotEmpty;

  bool get hasDirtyDocuments => _documents.any((document) => document.dirty);

  AutomationDocumentSession? _find(String fileName) =>
      _documents.where((document) => document.fileName == fileName).firstOrNull;

  /// Opens [fileName], preserving an existing in-memory session if it is
  /// already open, and makes it active.
  AutomationDocumentSession open(
    AutomationData data,
    String fileName, {
    bool dirty = false,
  }) {
    final existing = _find(fileName);
    if (existing != null) {
      _activeFileName = fileName;
      return existing;
    }
    final session = AutomationDocumentSession(
      fileName: fileName,
      data: data,
      dirty: dirty,
    );
    _documents.add(session);
    _activeFileName = fileName;
    return session;
  }

  bool activate(String fileName) {
    if (_find(fileName) == null) return false;
    final changed = _activeFileName != fileName;
    _activeFileName = fileName;
    return changed;
  }

  /// Synchronizes the active session with the mounted editor before a switch,
  /// save, run, or close operation.
  bool updateActive(AutomationData data) {
    final session = active;
    if (session == null) return false;
    session.data = data;
    return true;
  }

  bool setActiveDirty(bool dirty) {
    final session = active;
    if (session == null || session.dirty == dirty) return false;
    session.dirty = dirty;
    return true;
  }

  bool markActiveSaved(AutomationData data) {
    final session = active;
    if (session == null) return false;
    session
      ..data = data
      ..dirty = false;
    return true;
  }

  bool markSaved(String fileName, AutomationData data) {
    final session = _find(fileName);
    if (session == null) return false;
    session
      ..data = data
      ..dirty = false;
    return true;
  }

  /// Reorders an open resource tab by its final position.
  bool reorder(int oldPosition, int newPosition) {
    if (oldPosition < 0 || oldPosition >= _documents.length) return false;
    if (newPosition < 0 || newPosition >= _documents.length) return false;
    if (oldPosition == newPosition) return false;
    final document = _documents.removeAt(oldPosition);
    _documents.insert(newPosition, document);
    return true;
  }

  bool close(String fileName) {
    final position = _documents.indexWhere(
      (document) => document.fileName == fileName,
    );
    if (position < 0) return false;
    final wasActive = _activeFileName == fileName;
    _documents.removeAt(position);
    if (!wasActive) return true;
    if (_documents.isEmpty) {
      _activeFileName = null;
    } else {
      final nextPosition = position > 0 ? position - 1 : 0;
      _activeFileName = _documents[nextPosition].fileName;
    }
    return true;
  }

  void clear() {
    _documents.clear();
    _activeFileName = null;
  }

  Map<String, dynamic> toSettings() => {
    'openAutomationTabs': _documents
        .map((document) => document.fileName)
        .toList(),
    if (_activeFileName != null) 'selectedAutomationTab': _activeFileName,
  };
}
