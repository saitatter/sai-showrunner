import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:yaml/yaml.dart';

import '../../persistence/migrations/legacy_import_service.dart';
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

  ResourceData toResource() => ResourceData(
    id: id,
    config: {
      'name': name ?? id,
      'type': type,
      'defaultValue': defaultValue,
      'persistent': persistent,
    },
    state: {'value': currentValue},
  );
}

/// Runtime-backed variables shared by all graph executions.
///
/// The Electron implementation stores definitions in one YAML map. Flutter
/// uses one resource per variable so the resource editor and runtime share a
/// persistence boundary. A legacy YAML file is imported once, backed up, and
/// converted to those resources before it is removed.
final class DartVariableRuntime extends ChangeNotifier {
  DartVariableRuntime({required this.directory, this.onChanged});

  final Directory directory;
  final DartVariableChanged? onChanged;
  final Map<String, DartVariableDefinition> _definitions = {};
  bool _loaded = false;

  Iterable<DartVariableDefinition> get definitions =>
      _definitions.values.toList(growable: false);

  dynamic valueOf(String id) => _find(id)?.currentValue;

  DartVariableDefinition? definitionOf(String id) => _find(id);

  Future<void> load() async {
    await _loadFromDisk();
    _loaded = true;
    _publishAll();
  }

  /// Reloads definitions after an editor or another process changes a file.
  Future<void> reload() async {
    await _loadFromDisk();
    _loaded = true;
    _publishAll();
  }

  Future<dynamic> setValue(String id, dynamic value) async {
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
      setValue(id, _find(id)?.defaultValue);

  Future<void> _ensureLoaded() async {
    if (!_loaded) await load();
  }

  Future<void> _loadFromDisk() async {
    final next = <String, DartVariableDefinition>{};
    final repository = ResourceRepository(directory);
    for (final resource in await repository.list()) {
      if (resource.id == 'variables' && resource.config['type'] == null) {
        continue;
      }
      final definition = _fromResource(resource);
      if (definition != null) next[definition.id] = definition;
    }

    final legacy = File('${directory.path}/variables.yaml');
    if (await legacy.exists()) {
      final imported = await _readLegacy(legacy, next);
      if (imported.isNotEmpty) {
        final backup = await backupOriginalFile(legacy);
        for (final definition in imported) {
          await repository.save(definition.toResource());
          next[definition.id] = definition;
        }
        // The backup is the recovery path; the active directory contains
        // only the canonical Flutter resource representation after import.
        await legacy.delete();
        if (!await backup.exists()) {
          throw StateError('Variable migration backup was not created.');
        }
      }
    }

    _definitions
      ..clear()
      ..addAll(next);
  }

  Future<List<DartVariableDefinition>> _readLegacy(
    File file,
    Map<String, DartVariableDefinition> existing,
  ) async {
    final parsed = loadYaml(await file.readAsString());
    if (parsed is! YamlMap) return const [];
    final imported = <DartVariableDefinition>[];
    for (final entry in parsed.entries) {
      final id = entry.key.toString().trim();
      if (!_isSafeId(id) ||
          existing.containsKey(id) ||
          entry.value is! YamlMap) {
        continue;
      }
      final value = _yamlToDart(entry.value);
      if (value is! Map) continue;
      final map = Map<String, dynamic>.from(value);
      final type = map['type']?.toString() ?? 'dynamic';
      final defaultValue = _normalizeValue(type, map['defaultValue']);
      final persistent = map['serialized'] != false;
      final currentValue = persistent && map.containsKey('savedValue')
          ? _normalizeValue(type, map['savedValue'])
          : defaultValue;
      imported.add(
        DartVariableDefinition(
          id: id,
          type: type,
          defaultValue: defaultValue,
          currentValue: currentValue,
          persistent: persistent,
        ),
      );
    }
    return imported;
  }

  DartVariableDefinition? _fromResource(ResourceData resource) {
    final type = resource.config['type']?.toString().trim();
    if (type == null || type.isEmpty) return null;
    final defaultValue = _normalizeValue(type, resource.config['defaultValue']);
    final persistent = resource.config['persistent'] != false;
    final rawCurrent = resource.state.containsKey('value')
        ? resource.state['value']
        : defaultValue;
    return DartVariableDefinition(
      id: resource.id,
      name: resource.config['name']?.toString(),
      type: type,
      defaultValue: defaultValue,
      currentValue: persistent
          ? _normalizeValue(type, rawCurrent)
          : defaultValue,
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
    await ResourceRepository(directory).save(definition.toResource());
  }

  void _publishAll() {
    for (final definition in _definitions.values) {
      _publish(definition, notify: false);
    }
    notifyListeners();
  }

  void _publish(DartVariableDefinition definition, {bool notify = true}) {
    onChanged?.call(definition.id, definition.currentValue);
    if (notify) notifyListeners();
  }
}

bool _isSafeId(String value) =>
    value.isNotEmpty &&
    !value.contains('/') &&
    !value.contains('\\') &&
    value != '.' &&
    value != '..';

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

dynamic _yamlToDart(dynamic value) {
  if (value is YamlMap) {
    return <String, dynamic>{
      for (final entry in value.entries)
        entry.key.toString(): _yamlToDart(entry.value),
    };
  }
  if (value is YamlList) return value.map(_yamlToDart).toList();
  return value;
}
