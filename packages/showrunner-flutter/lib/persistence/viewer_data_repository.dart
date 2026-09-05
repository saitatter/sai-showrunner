import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

import '../schema/automation.dart';
import '../schema/viewer_data.dart';

final class ViewerDataSyncResult {
  const ViewerDataSyncResult({
    required this.row,
    required this.created,
    required this.changed,
  });

  final ViewerDataRow row;
  final bool created;
  final bool changed;
}

abstract interface class ViewerDataRepository {
  Future<List<ViewerVariableDefinition>> loadDefinitions();

  Future<void> saveDefinitions(Iterable<ViewerVariableDefinition> definitions);

  Future<JsonMap> getDefaultViewerData();

  Future<ViewerDataRow> loadViewer(String provider, ViewerIdentity viewer);

  Future<List<ViewerDataRow>> queryViewers(
    String provider, {
    int start = 0,
    int? end,
    String sortBy = 'id',
    bool descending = false,
  });

  Future<ViewerDataRow> setViewerValue(
    String provider,
    ViewerIdentity viewer,
    String variable,
    dynamic value,
  );

  Future<ViewerDataRow> offsetViewerValue(
    String provider,
    ViewerIdentity viewer,
    String variable,
    num offset,
  );

  Future<bool> importViewerRow(ViewerDataRow row, {bool overwrite = false});

  Future<ViewerDataSyncResult> syncViewerIdentity(
    String provider,
    ViewerIdentity viewer,
  );
}

final class FileViewerDataRepository implements ViewerDataRepository {
  FileViewerDataRepository(this.directory);

  final Directory directory;
  final Map<String, Future<void>> _viewerLocks = {};

  File get definitionsFile => File('${directory.path}/variables.yaml');

  @override
  Future<List<ViewerVariableDefinition>> loadDefinitions() async {
    if (!await definitionsFile.exists()) return const [];
    final parsed = loadYaml(await definitionsFile.readAsString());
    if (parsed is! YamlList) return const [];

    final definitions = <ViewerVariableDefinition>[];
    for (final item in parsed) {
      if (item is! YamlMap) continue;
      try {
        definitions.add(ViewerVariableDefinition.fromJson(_yamlMap(item)));
      } on ArgumentError {
        continue;
      } on FormatException {
        continue;
      }
    }
    return definitions;
  }

  @override
  Future<void> saveDefinitions(
    Iterable<ViewerVariableDefinition> definitions,
  ) async {
    final values = definitions.toList(growable: false);
    await directory.create(recursive: true);
    final temporaryFile = File('${definitionsFile.path}.tmp');
    await temporaryFile.writeAsString(_encodeDefinitions(values));
    await temporaryFile.rename(definitionsFile.path);
  }

  @override
  Future<JsonMap> getDefaultViewerData() async {
    final definitions = await loadDefinitions();
    return {
      for (final definition in definitions)
        definition.name: definition.constructedDefault,
    };
  }

  @override
  Future<ViewerDataRow> loadViewer(String provider, ViewerIdentity viewer) {
    return _withViewerLock(
      _viewerKey(provider, viewer.id),
      () => _readViewer(provider, viewer),
    );
  }

  @override
  Future<List<ViewerDataRow>> queryViewers(
    String provider, {
    int start = 0,
    int? end,
    String sortBy = 'id',
    bool descending = false,
  }) async {
    final viewerDirectory = _providerDirectory(provider);
    if (!await viewerDirectory.exists()) return const [];
    final rows = <ViewerDataRow>[];
    await for (final entity in viewerDirectory.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final row = ViewerDataRow.fromJson(
          jsonDecode(await entity.readAsString()) as JsonMap,
        );
        if (row.provider == provider) rows.add(row);
      } on FormatException {
        // Ignore corrupted rows, matching the resource catalog behavior.
      } on TypeError {
        // Ignore malformed JSON objects.
      }
    }
    rows.sort((left, right) {
      final result = _compareViewerRows(left, right, sortBy);
      return descending ? -result : result;
    });
    final from = start.clamp(0, rows.length).toInt();
    final to = (end ?? rows.length).clamp(from, rows.length).toInt();
    return rows.sublist(from, to);
  }

  @override
  Future<ViewerDataRow> setViewerValue(
    String provider,
    ViewerIdentity viewer,
    String variable,
    dynamic value,
  ) {
    return _withViewerLock(_viewerKey(provider, viewer.id), () async {
      final definition = await _findDefinition(variable);
      if (definition == null) {
        throw StateError('Unknown viewer variable: $variable');
      }
      final normalizedValue = normalizeViewerVariableValue(
        definition.normalizedType,
        value,
      );
      final current = await _readViewer(provider, viewer);
      final next = ViewerDataRow(
        provider: provider,
        viewer: current.persisted ? current.viewer : viewer,
        values: {...current.values, variable: normalizedValue},
      );
      await _writeViewer(next);
      return next;
    });
  }

  @override
  Future<ViewerDataRow> offsetViewerValue(
    String provider,
    ViewerIdentity viewer,
    String variable,
    num offset,
  ) {
    return _withViewerLock(_viewerKey(provider, viewer.id), () async {
      if (!offset.isFinite) {
        throw ArgumentError.value(offset, 'offset', 'Offset must be finite.');
      }
      final definition = await _findDefinition(variable);
      if (definition == null) {
        throw StateError('Unknown viewer variable: $variable');
      }
      if (definition.normalizedType != 'number') {
        throw StateError(
          "Can't offset a non-number viewer variable: $variable",
        );
      }

      final current = await _readViewer(provider, viewer);
      final storedValue = current.values[variable];
      final base = current.persisted
          ? storedValue is num
                ? storedValue
                : 0
          : definition.constructedDefault is num
          ? definition.constructedDefault as num
          : 0;
      final next = ViewerDataRow(
        provider: provider,
        viewer: current.persisted ? current.viewer : viewer,
        values: {...current.values, variable: base + offset},
      );
      await _writeViewer(next);
      return next;
    });
  }

  @override
  Future<bool> importViewerRow(
    ViewerDataRow row, {
    bool overwrite = false,
  }) async {
    if (row.provider.isEmpty || row.viewer.id.isEmpty) {
      throw const FormatException(
        'Imported viewer rows require provider and id.',
      );
    }
    final file = _viewerFile(row.provider, row.viewer.id);
    if (!overwrite && await file.exists()) return false;
    final current = await _readViewer(row.provider, row.viewer);
    await _writeViewer(
      ViewerDataRow(
        provider: row.provider,
        viewer: row.viewer,
        values: {...current.values, ...row.values},
      ),
    );
    return true;
  }

  @override
  Future<ViewerDataSyncResult> syncViewerIdentity(
    String provider,
    ViewerIdentity viewer,
  ) {
    if (provider.isEmpty || viewer.id.isEmpty) {
      throw const FormatException(
        'Synchronized viewer rows require provider and id.',
      );
    }
    return _withViewerLock(_viewerKey(provider, viewer.id), () async {
      final current = await _readViewer(provider, viewer);
      if (current.persisted &&
          current.viewer.displayName == viewer.displayName) {
        return ViewerDataSyncResult(
          row: current,
          created: false,
          changed: false,
        );
      }
      final next = ViewerDataRow(
        provider: provider,
        viewer: viewer,
        values: current.values,
      );
      await _writeViewer(next);
      return ViewerDataSyncResult(
        row: next,
        created: !current.persisted,
        changed: true,
      );
    });
  }

  Future<ViewerVariableDefinition?> _findDefinition(String name) async {
    for (final definition in await loadDefinitions()) {
      if (definition.name == name) return definition;
    }
    return null;
  }

  Future<ViewerDataRow> _readViewer(
    String provider,
    ViewerIdentity viewer,
  ) async {
    final definitions = await loadDefinitions();
    final defaults = {
      for (final definition in definitions)
        definition.name: definition.constructedDefault,
    };
    final file = _viewerFile(provider, viewer.id);
    if (!await file.exists()) {
      return ViewerDataRow(
        provider: provider,
        viewer: viewer,
        values: defaults,
        persisted: false,
      );
    }

    final stored = ViewerDataRow.fromJson(
      jsonDecode(await file.readAsString()) as JsonMap,
    );
    if (stored.provider != provider || stored.viewer.id != viewer.id) {
      throw FormatException('Viewer data row does not match its file path.');
    }
    final values = <String, dynamic>{...defaults};
    for (final definition in definitions) {
      if (!stored.values.containsKey(definition.name)) continue;
      values[definition.name] = normalizeViewerVariableValue(
        definition.normalizedType,
        stored.values[definition.name],
      );
    }
    return ViewerDataRow(
      provider: provider,
      viewer: stored.viewer,
      values: values,
    );
  }

  Future<void> _writeViewer(ViewerDataRow row) async {
    final file = _viewerFile(row.provider, row.viewer.id);
    await file.parent.create(recursive: true);
    final temporaryFile = File('${file.path}.tmp');
    const encoder = JsonEncoder.withIndent('  ');
    await temporaryFile.writeAsString(encoder.convert(row.toJson()));
    await temporaryFile.rename(file.path);
  }

  File _viewerFile(String provider, String viewerId) {
    final encodedId = base64Url
        .encode(utf8.encode(viewerId))
        .replaceAll('=', '');
    return File('${_providerDirectory(provider).path}/$encodedId.json');
  }

  Directory _providerDirectory(String provider) {
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(provider)) {
      throw ArgumentError.value(provider, 'provider');
    }
    return Directory('${directory.path}/$provider');
  }

  Future<T> _withViewerLock<T>(String key, Future<T> Function() operation) {
    final previous = _viewerLocks[key] ?? Future<void>.value();
    final result = previous.then((_) => operation());
    _viewerLocks[key] = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  String _viewerKey(String provider, String viewerId) =>
      '${provider.length}:$provider:$viewerId';
}

final class InMemoryViewerDataRepository implements ViewerDataRepository {
  InMemoryViewerDataRepository({
    Iterable<ViewerVariableDefinition> definitions =
        const <ViewerVariableDefinition>[],
  }) : _definitions = List.of(definitions);

  List<ViewerVariableDefinition> _definitions;
  final Map<String, ViewerDataRow> _rows = {};

  @override
  Future<List<ViewerVariableDefinition>> loadDefinitions() async =>
      List.unmodifiable(_definitions);

  @override
  Future<void> saveDefinitions(
    Iterable<ViewerVariableDefinition> definitions,
  ) async {
    _definitions = List.of(definitions);
  }

  @override
  Future<JsonMap> getDefaultViewerData() async => {
    for (final definition in _definitions)
      definition.name: definition.constructedDefault,
  };

  @override
  Future<ViewerDataRow> loadViewer(String provider, ViewerIdentity viewer) {
    final row = _rows[_viewerKey(provider, viewer.id)];
    if (row != null) return Future.value(row);
    return getDefaultViewerData().then(
      (values) => ViewerDataRow(
        provider: provider,
        viewer: viewer,
        values: values,
        persisted: false,
      ),
    );
  }

  @override
  Future<List<ViewerDataRow>> queryViewers(
    String provider, {
    int start = 0,
    int? end,
    String sortBy = 'id',
    bool descending = false,
  }) async {
    final rows = _rows.values.where((row) => row.provider == provider).toList();
    rows.sort((left, right) {
      final result = _compareViewerRows(left, right, sortBy);
      return descending ? -result : result;
    });
    final from = start.clamp(0, rows.length).toInt();
    final to = (end ?? rows.length).clamp(from, rows.length).toInt();
    return rows.sublist(from, to);
  }

  @override
  Future<ViewerDataRow> setViewerValue(
    String provider,
    ViewerIdentity viewer,
    String variable,
    dynamic value,
  ) async {
    final definition = _findDefinition(variable);
    if (definition == null) {
      throw StateError('Unknown viewer variable: $variable');
    }
    final current = await loadViewer(provider, viewer);
    final next = ViewerDataRow(
      provider: provider,
      viewer: current.persisted ? current.viewer : viewer,
      values: {
        ...current.values,
        variable: normalizeViewerVariableValue(
          definition.normalizedType,
          value,
        ),
      },
    );
    _rows[_viewerKey(provider, viewer.id)] = next;
    return next;
  }

  @override
  Future<ViewerDataRow> offsetViewerValue(
    String provider,
    ViewerIdentity viewer,
    String variable,
    num offset,
  ) async {
    if (!offset.isFinite) {
      throw ArgumentError.value(offset, 'offset', 'Offset must be finite.');
    }
    final definition = _findDefinition(variable);
    if (definition == null) {
      throw StateError('Unknown viewer variable: $variable');
    }
    if (definition.normalizedType != 'number') {
      throw StateError("Can't offset a non-number viewer variable: $variable");
    }
    final current = await loadViewer(provider, viewer);
    final currentValue = current.values[variable];
    final base = current.persisted
        ? currentValue is num
              ? currentValue
              : 0
        : definition.constructedDefault is num
        ? definition.constructedDefault as num
        : 0;
    final next = ViewerDataRow(
      provider: provider,
      viewer: current.persisted ? current.viewer : viewer,
      values: {...current.values, variable: base + offset},
    );
    _rows[_viewerKey(provider, viewer.id)] = next;
    return next;
  }

  @override
  Future<bool> importViewerRow(
    ViewerDataRow row, {
    bool overwrite = false,
  }) async {
    if (row.provider.isEmpty || row.viewer.id.isEmpty) {
      throw const FormatException(
        'Imported viewer rows require provider and id.',
      );
    }
    final key = _viewerKey(row.provider, row.viewer.id);
    if (!overwrite && _rows.containsKey(key)) return false;
    final current = await loadViewer(row.provider, row.viewer);
    _rows[key] = ViewerDataRow(
      provider: row.provider,
      viewer: row.viewer,
      values: {...current.values, ...row.values},
    );
    return true;
  }

  @override
  Future<ViewerDataSyncResult> syncViewerIdentity(
    String provider,
    ViewerIdentity viewer,
  ) async {
    if (provider.isEmpty || viewer.id.isEmpty) {
      throw const FormatException(
        'Synchronized viewer rows require provider and id.',
      );
    }
    final key = _viewerKey(provider, viewer.id);
    final current = await loadViewer(provider, viewer);
    if (current.persisted && current.viewer.displayName == viewer.displayName) {
      return ViewerDataSyncResult(row: current, created: false, changed: false);
    }
    final next = ViewerDataRow(
      provider: provider,
      viewer: viewer,
      values: current.values,
    );
    _rows[key] = next;
    return ViewerDataSyncResult(
      row: next,
      created: !current.persisted,
      changed: true,
    );
  }

  ViewerVariableDefinition? _findDefinition(String name) {
    for (final definition in _definitions) {
      if (definition.name == name) return definition;
    }
    return null;
  }

  String _viewerKey(String provider, String viewerId) =>
      '${provider.length}:$provider:$viewerId';
}

JsonMap _yamlMap(YamlMap value) => {
  for (final entry in value.entries)
    entry.key.toString(): _yamlValue(entry.value),
};

dynamic _yamlValue(dynamic value) {
  if (value is YamlMap) return _yamlMap(value);
  if (value is YamlList) return value.map(_yamlValue).toList();
  return value;
}

String _encodeDefinitions(List<ViewerVariableDefinition> definitions) {
  final lines = <String>[];
  for (final definition in definitions) {
    lines.add('- name: ${_yamlScalar(definition.name)}');
    lines.add('  type: ${_yamlScalar(definition.type)}');
    if (definition.defaultValue != null) {
      lines.add('  defaultValue: ${_yamlScalar(definition.defaultValue)}');
    }
    lines.add('  required: ${definition.required}');
  }
  return '${lines.join('\n')}\n';
}

String _yamlScalar(dynamic value) {
  if (value == null) return 'null';
  if (value is bool || value is num) return value.toString();
  if (value is Map || value is List) return jsonEncode(value);
  return jsonEncode(value.toString());
}

int _compareViewerRows(ViewerDataRow left, ViewerDataRow right, String sortBy) {
  final leftValue = _viewerSortValue(left, sortBy);
  final rightValue = _viewerSortValue(right, sortBy);
  if (leftValue is num && rightValue is num) {
    return leftValue.compareTo(rightValue);
  }
  return leftValue.toString().toLowerCase().compareTo(
    rightValue.toString().toLowerCase(),
  );
}

dynamic _viewerSortValue(ViewerDataRow row, String sortBy) {
  switch (sortBy) {
    case 'displayName':
      return row.viewer.displayName;
    case 'id':
      return row.viewer.id;
    default:
      return row.values[sortBy] ?? '';
  }
}
