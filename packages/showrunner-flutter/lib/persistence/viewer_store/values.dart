part of '../sqlite_viewer_data_repository.dart';

void _validateProvider(String provider) {
  if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(provider)) {
    throw ArgumentError('Invalid viewer provider.');
  }
}

void _validateIdentity(String provider, ViewerIdentity viewer) {
  _validateProvider(provider);
  if (viewer.id.isEmpty) {
    throw const FormatException('Viewer id cannot be empty.');
  }
}

List<Object?> _encodedValue(Object? value) {
  final String encoded;
  try {
    encoded = jsonEncode(value);
  } catch (_) {
    throw const FormatException('Unsupported viewer value.');
  }
  if (value == null) return [encoded, 'null', 0, 0, ''];
  if (value is num) {
    if (!value.isFinite) {
      throw const FormatException('Viewer numbers must be finite.');
    }
    return [encoded, 'number', 1, value, ''];
  }
  if (value is bool) return [encoded, 'boolean', 2, value ? 1 : 0, ''];
  return [
    encoded,
    value is String ? 'string' : 'json',
    value is String ? 3 : 4,
    0,
    value.toString().toLowerCase(),
  ];
}

ViewerVariableDefinition _storedDefinition(String source) {
  try {
    return ViewerVariableDefinition.fromJson(jsonDecode(source) as JsonMap);
  } catch (_) {
    throw const FormatException(
      'Unsupported or malformed stored viewer definition.',
    );
  }
}

Object? _storedValue(ViewerVariableDefinition definition, String source) {
  try {
    final value = normalizeViewerVariableValue(
      definition.normalizedType,
      jsonDecode(source),
    );
    _encodedValue(value);
    return value;
  } catch (_) {
    throw const FormatException(
      'Unsupported or malformed stored viewer value.',
    );
  }
}

Future<List<ViewerVariableDefinition>> _definitions(
  SqliteReadContext tx,
) async => [
  for (final row in await tx.getAll(
    'SELECT definition_json FROM viewer_variable_definitions ORDER BY ordinal',
  ))
    _storedDefinition(row['definition_json'] as String),
];
Future<ViewerVariableDefinition> _definition(
  SqliteReadContext tx,
  String name,
) async {
  final row = await tx.getOptional(
    'SELECT definition_json FROM viewer_variable_definitions WHERE name = ?',
    [name],
  );
  if (row == null) throw StateError('Unknown viewer variable: $name');
  return _storedDefinition(row['definition_json'] as String);
}

Future<void> _saveDefinitions(
  SqliteWriteContext tx,
  List<ViewerVariableDefinition> definitions,
) async {
  final names = <String>{};
  for (final definition in definitions) {
    ViewerVariableDefinition.fromJson(definition.toJson());
    if (!names.add(definition.name)) {
      throw const FormatException('Duplicate viewer variable definition.');
    }
    _encodedValue(definition.constructedDefault);
    // A schema edit cannot silently reinterpret explicit persisted values.
    final type = definition.normalizedType;
    final allowed = switch (type) {
      'number' => "value_type IN ('null','number')",
      'boolean' => "value_type IN ('null','boolean')",
      'string' || 'color' || 'lightcolor' => "value_type IN ('null','string')",
      'object' => "value_type = 'null' OR json_type(value_json) = 'object'",
      'list' => "value_type = 'null' OR json_type(value_json) = 'array'",
      'twitchviewer' =>
        "value_type IN ('null','string') OR json_type(value_json) = 'object'",
      _ => '1',
    };
    if (await tx.getOptional(
          '''SELECT 1 FROM viewer_values
      WHERE variable_name = ? AND is_default = 0 AND NOT ($allowed) LIMIT 1''',
          [definition.name],
        ) !=
        null) {
      throw const FormatException(
        'Viewer definition conflicts with stored values.',
      );
    }
  }
  await tx.execute('DELETE FROM viewer_variable_definitions');
  for (var ordinal = 0; ordinal < definitions.length; ordinal++) {
    final definition = definitions[ordinal];
    final value = _encodedValue(definition.constructedDefault);
    await tx.execute(
      '''INSERT INTO viewer_variable_definitions
      (name, ordinal, definition_json, value_json, value_type, sort_rank, sort_number, sort_text)
      VALUES(?, ?, ?, ?, ?, ?, ?, ?)''',
      [definition.name, ordinal, jsonEncode(definition.toJson()), ...value],
    );
    await tx.execute(
      '''UPDATE viewer_values SET value_json = ?, value_type = ?,
      sort_rank = ?, sort_number = ?, sort_text = ? WHERE variable_name = ? AND is_default = 1''',
      [...value, definition.name],
    );
    await tx.execute(
      '''INSERT INTO viewer_values
      (provider, viewer_id, variable_name, value_json, value_type, sort_rank, sort_number, sort_text, id_sort, is_default)
      SELECT v.provider, v.viewer_id, ?, ?, ?, ?, ?, ?, v.id_sort, 1 FROM viewers v
      WHERE NOT EXISTS (SELECT 1 FROM viewer_values x WHERE x.provider = v.provider
        AND x.viewer_id = v.viewer_id AND x.variable_name = ?)''',
      [definition.name, ...value, definition.name],
    );
  }
}

Future<void> _ensureViewer(
  SqliteWriteContext tx,
  String provider,
  ViewerIdentity viewer,
) async {
  await tx.execute(
    '''INSERT INTO viewers(provider, viewer_id, display_name, id_sort, name_sort)
    VALUES(?, ?, ?, ?, ?) ON CONFLICT(provider, viewer_id) DO NOTHING''',
    [
      provider,
      viewer.id,
      viewer.displayName,
      viewer.id.toLowerCase(),
      viewer.displayName.toLowerCase(),
    ],
  );
  await tx.execute(
    '''INSERT INTO viewer_values
    (provider, viewer_id, variable_name, value_json, value_type, sort_rank, sort_number, sort_text, id_sort, is_default)
    SELECT ?, ?, name, value_json, value_type, sort_rank, sort_number, sort_text, ?, 0
    FROM viewer_variable_definitions WHERE NOT EXISTS (
      SELECT 1 FROM viewer_values x WHERE x.provider = ? AND x.viewer_id = ?
        AND x.variable_name = viewer_variable_definitions.name)''',
    [provider, viewer.id, viewer.id.toLowerCase(), provider, viewer.id],
  );
  await tx.execute(
    'UPDATE viewer_values SET is_default = 0 WHERE provider = ? AND viewer_id = ?',
    [provider, viewer.id],
  );
}

Future<void> _putValue(
  SqliteWriteContext tx,
  String provider,
  String id,
  String name,
  Object? value,
) => tx.execute(
  '''INSERT INTO viewer_values
    (provider, viewer_id, variable_name, value_json, value_type, sort_rank, sort_number, sort_text, id_sort, is_default)
    VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, 0)
    ON CONFLICT(provider, viewer_id, variable_name) DO UPDATE SET
      value_json = excluded.value_json, value_type = excluded.value_type,
      sort_rank = excluded.sort_rank, sort_number = excluded.sort_number,
      sort_text = excluded.sort_text, is_default = 0''',
  [provider, id, name, ..._encodedValue(value), id.toLowerCase()],
);

Future<bool> _importRow(
  SqliteWriteContext tx,
  ViewerDataRow row,
  bool overwrite,
) async {
  _validateIdentity(row.provider, row.viewer);
  final exists = await tx.getOptional(
    'SELECT 1 FROM viewers WHERE provider = ? AND viewer_id = ?',
    [row.provider, row.viewer.id],
  );
  if (exists != null && !overwrite) return false;
  await _ensureViewer(tx, row.provider, row.viewer);
  await tx.execute(
    'UPDATE viewers SET display_name = ?, name_sort = ? WHERE provider = ? AND viewer_id = ?',
    [
      row.viewer.displayName,
      row.viewer.displayName.toLowerCase(),
      row.provider,
      row.viewer.id,
    ],
  );
  final definitions = {for (final d in await _definitions(tx)) d.name: d};
  for (final entry in row.values.entries) {
    final definition = definitions[entry.key];
    final value = definition == null
        ? entry.value
        : normalizeViewerVariableValue(definition.normalizedType, entry.value);
    await _putValue(tx, row.provider, row.viewer.id, entry.key, value);
  }
  return true;
}
