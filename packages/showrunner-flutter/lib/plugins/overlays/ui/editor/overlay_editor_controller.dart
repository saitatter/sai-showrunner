import 'dart:convert';
import 'package:flutter/foundation.dart';

import '../../../../features/resources/overlay/overlay_document.dart';
import '../../../../persistence/document_revision.dart';
import '../../../../schema/json.dart';
import '../../../../schema/resource.dart';

typedef _EditorSnapshot = ({ResourceData resource, List<Object> keys});

/// Owns authoring commands/history; selection keys and save status are view state.
/// No network, filesystem, text controllers or canvas geometry live here.
final class OverlayEditorController extends ChangeNotifier {
  OverlayEditorController(ResourceData resource) {
    final document = OverlayDocument(resource);
    final overlay = OverlayResource.fromResource(resource);
    _current = _freeze(
      document.snapshot(
        name: overlay.name,
        width: overlay.width,
        height: overlay.height,
        widgets: document.initialWidgets,
        preview: resource.config['preview'] is Map
            ? Map<String, dynamic>.from(resource.config['preview'] as Map)
            : null,
      ),
    );
    // Shipped documents can omit layer IDs. Their view-only tokens must never
    // become migration IDs in saved resources. Valid unique IDs remain stable.
    final used = <String>{};
    _keys = List.unmodifiable(
      widgets.map((layer) {
        final id = layer['id'];
        return id is String && id.isNotEmpty && used.add(id) ? id : Object();
      }),
    );
    _signature = DocumentRevision.of(_current.toJson());
    _saved = _signature;
  }

  late ResourceData _current;
  late List<Object> _keys;
  late DocumentRevision _signature, _saved;
  final selection = ValueNotifier<Object?>(null);
  final _undo = <_EditorSnapshot>[];
  final _redo = <_EditorSnapshot>[];
  _EditorSnapshot? _transaction;
  Future<void>? _saveOperation;
  bool _disposed = false;
  int _revision = 0;
  int get revision => _revision;
  ResourceData get resource => _current;
  List<JsonMap> get widgets =>
      (_current.config['widgets'] as List).cast<JsonMap>();
  bool get dirty => _signature != _saved;
  bool get saving => _saveOperation != null;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  Object keyAt(int index) => _keys[index];
  int? get selectedIndex {
    final index = _keys.indexOf(selection.value ?? const _NoSelection());
    return index < 0 ? null : index;
  }

  void selectIndex(int? index) {
    if (_disposed) return;
    selection.value = index == null ? null : _keys[index];
  }

  ResourceData compose({
    required String name,
    required int width,
    required int height,
    JsonMap? preview,
  }) => OverlayDocument(_current).snapshot(
    name: name,
    width: width,
    height: height,
    widgets: widgets,
    preview: preview,
  );

  _EditorSnapshot get _snapshot => (resource: _current, keys: _keys);
  bool replace(ResourceData value, {List<Object>? keys}) {
    if (_disposed) return false;
    if (value.id != _current.id) {
      throw ArgumentError('A command cannot change resource identity.');
    }
    final next = _freeze(value);
    final signature = DocumentRevision.of(next.toJson());
    if (signature == _signature) return false;
    final nextKeys = List<Object>.unmodifiable(keys ?? _keys);
    if (nextKeys.length != (next.config['widgets'] as List).length) {
      throw StateError('Layer identity count mismatch.');
    }
    if (_transaction == null) _remember(_snapshot);
    _redo.clear();
    _current = next;
    _signature = signature;
    _keys = nextKeys;
    if (!_keys.contains(selection.value)) selection.value = null;
    _revision++;
    notifyListeners();
    return true;
  }

  void _remember(_EditorSnapshot value) {
    _undo.add(value);
    if (_undo.length > 100) _undo.removeAt(0);
  }

  bool updateWidget(Object key, JsonMap patch) {
    final index = _keys.indexOf(key);
    if (_disposed || index < 0) return false;
    final next = [...widgets];
    next[index] = {...next[index], ...patch};
    return replace(
      ResourceData(
        id: _current.id,
        config: {..._current.config, 'widgets': next},
        state: _current.state,
      ),
    );
  }

  void addWidget(JsonMap widget) {
    final id = widget['id'];
    final key = id is String && id.isNotEmpty && !_keys.contains(id)
        ? id
        : Object();
    replace(
      ResourceData(
        id: _current.id,
        config: {
          ..._current.config,
          'widgets': [...widgets, widget],
        },
        state: _current.state,
      ),
      keys: [..._keys, key],
    );
    selection.value = key;
  }

  void deleteWidget(int index) {
    final removed = _keys[index];
    final next = [...widgets]..removeAt(index);
    final keys = [..._keys]..removeAt(index);
    final selected = selection.value;
    replace(
      ResourceData(
        id: _current.id,
        config: {..._current.config, 'widgets': next},
        state: _current.state,
      ),
      keys: keys,
    );
    if (selected == removed && keys.isNotEmpty) {
      selection.value = keys[index.clamp(0, keys.length - 1)];
    }
  }

  void reorder(int from, int to) {
    if (from == to) return;
    final next = [...widgets], keys = [..._keys];
    next.insert(to, next.removeAt(from));
    keys.insert(to, keys.removeAt(from));
    replace(
      ResourceData(
        id: _current.id,
        config: {..._current.config, 'widgets': next},
        state: _current.state,
      ),
      keys: keys,
    );
  }

  void beginTransaction() => _transaction ??= _snapshot;
  void endTransaction() {
    final before = _transaction;
    _transaction = null;
    if (before != null &&
        DocumentRevision.of(before.resource.toJson()) != _signature) {
      _remember(before);
      notifyListeners();
    }
  }

  void undo() => _restore(_undo, _redo);
  void redo() => _restore(_redo, _undo);
  void _restore(List<_EditorSnapshot> from, List<_EditorSnapshot> to) {
    endTransaction();
    if (_disposed || from.isEmpty) return;
    to.add(_snapshot);
    final previous = from.removeLast();
    _current = previous.resource;
    _keys = previous.keys;
    _signature = DocumentRevision.of(_current.toJson());
    if (!_keys.contains(selection.value)) selection.value = null;
    _revision++;
    notifyListeners();
  }

  Future<void> save(Future<void> Function(ResourceData) writer) {
    if (_disposed) return Future.error(StateError('Overlay editor is closed.'));
    if (_saveOperation case final pending?) return pending;
    // Assign ownership before invoking arbitrary writer code.
    final snapshot = _current;
    final operation = Future<void>.microtask(() => writer(snapshot));
    final signature = _signature;
    final owned = operation
        .then((_) {
          if (!_disposed) _saved = signature;
        })
        .whenComplete(() {
          _saveOperation = null;
          if (!_disposed) notifyListeners();
        });
    _saveOperation = owned;
    notifyListeners();
    return owned;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    selection.dispose();
    super.dispose();
  }
}

class _NoSelection {
  const _NoSelection();
}

ResourceData _freeze(ResourceData resource) {
  dynamic freeze(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.unmodifiable(
        value.map((key, value) => MapEntry(key as String, freeze(value))),
      );
    }
    if (value is List) return List<dynamic>.unmodifiable(value.map(freeze));
    return value;
  }

  final frozen = freeze(jsonDecode(jsonEncode(resource.toJson()))) as JsonMap;
  return ResourceData(
    id: frozen['id'] as String,
    config: frozen['config'] as JsonMap,
    state: frozen['state'] as JsonMap,
  );
}
