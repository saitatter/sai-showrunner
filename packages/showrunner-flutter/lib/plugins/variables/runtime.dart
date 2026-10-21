import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../persistence/resource_repository.dart';
import '../../schema/resource.dart';

typedef DartVariableChanged = void Function(String id, dynamic value);

final class DartVariableDefinition {
  DartVariableDefinition({
    required this.id,
    required this.type,
    required this.defaultValue,
    required this.currentValue,
    required this.persistent,
    this.name,
  });

  final String id;
  final String? name;
  String type;
  dynamic defaultValue;
  dynamic currentValue;
  bool persistent;
}

/// Runtime-backed variables shared by all graph executions.
///
/// Flutter stores one resource per variable so the resource editor and runtime
/// share the same persistence boundary.
final class DartVariableRuntime extends ChangeNotifier {
  DartVariableRuntime({
    required this.directory,
    ResourceRepository? repository,
    this.onChanged,
  }) : _repository = repository ?? ResourceRepository(directory);

  final ResourceRepository _repository;

  final Directory directory;
  final DartVariableChanged? onChanged;
  final Map<String, DartVariableDefinition> _definitions = {};
  bool _loaded = false;
  Future<void>? _loading;
  final _variableTails = <String, Future<void>>{};
  bool _disposed = false;
  Future<void>? _closing;
  final _pending = <Future<void>>{};

  Iterable<DartVariableDefinition> get definitions =>
      _definitions.values.toList(growable: false);

  dynamic valueOf(String id) => _find(id)?.currentValue;

  DartVariableDefinition? definitionOf(String id) => _find(id);

  Future<void> load() => _track(_load);
  Future<void> _load() async {
    await _loadFromDisk();
    _loaded = true;
    _publishAll();
  }

  /// Reloads definitions after an editor or another process changes a file.
  Future<void> reload() => _track(_load);

  Future<T> _track<T>(Future<T> Function() operation) {
    if (_disposed || _closing != null) {
      return Future.error(StateError('Variable runtime is closed.'));
    }
    final result = Future<T>.sync(operation);
    final pending = result.then<void>((_) {});
    _pending.add(pending);
    pending.then<void>(
      (_) {
        _pending.remove(pending);
      },
      onError: (Object _, StackTrace _) {
        _pending.remove(pending);
      },
    );
    return result;
  }

  /// Flush caller-owned edits before their registry/notifier dependencies close.
  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    try {
      while (_pending.isNotEmpty) {
        await Future.wait(_pending.toList());
      }
    } finally {
      dispose();
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    super.dispose();
  }

  Future<dynamic> setValue(String id, dynamic value) =>
      _trackVariable(id, (key) => _setValue(key, value));
  Future<dynamic> _setValue(String id, dynamic value) async {
    await _ensureLoaded();
    final definition = _find(id);
    if (definition == null) return null;
    definition.currentValue = _normalizeValue(definition.type, value);
    await _persist(definition);
    _publish(definition);
    return definition.currentValue;
  }

  Future<dynamic> offsetValue(
    String id,
    num offset, {
    num? minimum,
    num? maximum,
  }) => _trackVariable(
    id,
    (key) => _offsetValue(key, offset, minimum: minimum, maximum: maximum),
  );

  Future<dynamic> _offsetValue(
    String id,
    num offset, {
    num? minimum,
    num? maximum,
  }) async {
    await _ensureLoaded();
    final definition = _find(id);
    if (definition == null) return null;
    final current = definition.currentValue;
    if (current is! num) return current;
    var value = current + offset;
    if (minimum != null && value < minimum) value = minimum;
    if (maximum != null && value > maximum) value = maximum;
    definition.currentValue = _normalizeValue(definition.type, value);
    await _persist(definition);
    _publish(definition);
    return definition.currentValue;
  }

  Future<dynamic> resetValue(String id) =>
      _trackVariable(id, (key) => _setValue(key, _find(key)?.defaultValue));

  Future<dynamic> _trackVariable(
    String id,
    Future<dynamic> Function(String key) operation,
  ) => _track(() async {
    await _ensureLoaded();
    final key = _find(id)?.id;
    if (key == null) return null;
    final previous = _variableTails[key] ?? Future<void>.value();
    final result = previous.then((_) => operation(key));
    final tail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _variableTails[key] = tail;
    try {
      return await result;
    } finally {
      if (identical(_variableTails[key], tail)) _variableTails.remove(key);
    }
  });

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final loading = _loading ??= _load();
    try {
      await loading;
    } finally {
      if (identical(_loading, loading)) _loading = null;
    }
  }

  Future<void> _loadFromDisk() async {
    final next = <String, DartVariableDefinition>{};
    for (final resource in await _repository.list()) {
      if (resource.id == 'variables' && resource.config['type'] == null) {
        continue;
      }
      final definition = _fromResource(resource, _definitions[resource.id]);
      if (definition != null) next[definition.id] = definition;
    }

    _definitions
      ..clear()
      ..addAll(next);
  }

  DartVariableDefinition? _fromResource(
    ResourceData resource,
    DartVariableDefinition? previous,
  ) {
    final type = resource.config['type']?.toString().trim();
    if (type == null || type.isEmpty) return null;
    final defaultValue = _normalizeValue(type, resource.config['defaultValue']);
    final persistent = resource.config['persistent'] != false;
    final rawCurrent = resource.state.containsKey('value')
        ? resource.state['value']
        : defaultValue;
    final currentValue = persistent
        ? _normalizeValue(type, rawCurrent)
        : previous?.type == type
        ? previous!.currentValue
        : defaultValue;
    return DartVariableDefinition(
      id: resource.id,
      name: resource.config['name']?.toString(),
      type: type,
      defaultValue: defaultValue,
      currentValue: currentValue,
      persistent: persistent,
    );
  }

  DartVariableDefinition? _find(String id) {
    final normalized = id.trim();
    if (normalized.isEmpty) return null;
    final exact = _definitions[normalized];
    if (exact != null) return exact;
    return _definitions.values
        .where((definition) => definition.name?.trim() == normalized)
        .firstOrNull;
  }

  Future<void> _persist(DartVariableDefinition definition) async {
    if (!definition.persistent) return;
    await _repository.updateRuntimeState(
      definition.id,
      {'value': definition.currentValue},
      writeIf: (current) =>
          current.config['persistent'] != false &&
          current.config['type']?.toString().trim().toLowerCase() ==
              definition.type.trim().toLowerCase(),
    );
  }

  void _publishAll() {
    if (_disposed) return;
    for (final definition in _definitions.values) {
      _publish(definition, notify: false);
    }
    notifyListeners();
  }

  void _publish(DartVariableDefinition definition, {bool notify = true}) {
    if (_disposed) return;
    onChanged?.call(definition.id, definition.currentValue);
    if (notify) notifyListeners();
  }
}

dynamic _normalizeValue(String type, dynamic value) {
  if (value is String) {
    final normalized = type.trim().toLowerCase();
    if (normalized == 'number' || normalized == 'duration') {
      return num.tryParse(value) ?? value;
    }
    if (normalized == 'boolean') return value.toLowerCase() == 'true';
    if (normalized == 'dynamic' ||
        normalized == 'json' ||
        normalized == 'object' ||
        normalized == 'map' ||
        normalized == 'array' ||
        normalized == 'list') {
      try {
        return jsonDecode(value);
      } on FormatException {
        return value;
      }
    }
  }
  return value;
}
