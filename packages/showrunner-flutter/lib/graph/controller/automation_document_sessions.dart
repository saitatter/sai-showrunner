import '../../plugins/registry/plugin_registry.dart';
import '../domain/automation_document.dart';
import 'automation_editor_controller.dart';

/// A tab owns its controller, including history, selection and camera. Data is
/// always read from that controller rather than synchronized into another model.
final class AutomationEditorSession {
  AutomationEditorSession({required this.fileName, required this.editor});
  final String fileName;
  final AutomationEditorController editor;
  AutomationDocument get data => editor.document;
  bool get dirty => editor.isDirty;
}

final class AutomationDocumentSessions {
  AutomationDocumentSessions({this._registry});
  DartPluginRegistry? _registry;
  final List<AutomationEditorSession> _documents = [];
  String? _activeFileName;
  final Set<void Function()> _listeners = {};
  final Map<AutomationEditorSession, (bool, String?)> _tabStates = {};
  List<AutomationEditorSession> get documents => List.unmodifiable(_documents);
  String? get activeFileName => _activeFileName;
  AutomationEditorSession? get active => find(_activeFileName ?? '');
  AutomationEditorSession? find(String fileName) =>
      _documents.where((document) => document.fileName == fileName).firstOrNull;
  bool get hasDocuments => _documents.isNotEmpty;
  bool get hasDirtyDocuments => _documents.any((document) => document.dirty);
  void addListener(void Function() listener) => _listeners.add(listener);
  void removeListener(void Function() listener) => _listeners.remove(listener);
  void _changed() {
    _tabStates
      ..clear()
      ..addEntries(
        _documents.map((session) => MapEntry(session, _tabState(session))),
      );
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }

  (bool, String?) _tabState(AutomationEditorSession session) {
    final host =
        session.editor.graph.document.metadata[automationHostMetadata] as Map;
    return (session.dirty, (host['metadata'] as Map)['name']?.toString());
  }

  void _sessionChanged() {
    if (_documents.any(
      (session) => _tabStates[session] != _tabState(session),
    )) {
      _changed();
    }
  }

  void bindRegistry(DartPluginRegistry registry) {
    _registry = registry;
    for (final session in _documents) {
      session.editor.bindRegistry(registry);
    }
  }

  AutomationEditorSession open(
    AutomationDocument document,
    String fileName, {
    bool unsaved = false,
  }) {
    final existing = find(fileName);
    if (existing != null) {
      activate(fileName);
      return existing;
    }
    final editor = AutomationEditorController(
      document: document,
      registry: _registry,
    );
    if (unsaved) editor.graph.markUnsaved();
    final session = AutomationEditorSession(fileName: fileName, editor: editor);
    _documents.add(session);
    editor.addListener(_sessionChanged);
    _activeFileName = fileName;
    _changed();
    return session;
  }

  bool activate(String fileName) {
    if (find(fileName) == null || _activeFileName == fileName) return false;
    _activeFileName = fileName;
    _changed();
    return true;
  }

  bool markSaved(String fileName, {required int revision}) {
    final session = find(fileName);
    if (session == null) return false;
    session.editor.graph.markSaved(revision: revision);
    return true;
  }

  bool reorder(int oldPosition, int newPosition) {
    if (oldPosition < 0 ||
        newPosition < 0 ||
        oldPosition >= _documents.length ||
        newPosition >= _documents.length ||
        oldPosition == newPosition) {
      return false;
    }
    _documents.insert(newPosition, _documents.removeAt(oldPosition));
    _changed();
    return true;
  }

  bool close(String fileName) {
    final position = _documents.indexWhere(
      (document) => document.fileName == fileName,
    );
    if (position < 0) return false;
    final session = _documents.removeAt(position);
    session.editor.removeListener(_sessionChanged);
    session.editor.dispose();
    if (_activeFileName == fileName) {
      _activeFileName = _documents.isEmpty
          ? null
          : _documents[position > 0 ? position - 1 : 0].fileName;
    }
    _changed();
    return true;
  }

  void clear() {
    for (final session in _documents) {
      session.editor.removeListener(_sessionChanged);
      session.editor.dispose();
    }
    _documents.clear();
    _activeFileName = null;
    _changed();
  }

  Map<String, Object?> toSettings() => {
    'openAutomationTabs': _documents
        .map((document) => document.fileName)
        .toList(),
    if (_activeFileName != null) 'selectedAutomationTab': _activeFileName,
  };
  void dispose() {
    _listeners.clear();
    clear();
  }
}
