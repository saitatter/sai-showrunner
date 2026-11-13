part of '../sqlite_viewer_data_repository.dart';

/// One-time import of the application's current file store. Original files are
/// never rewritten/deleted and never used as a fallback after a successful import.
Future<void> _importLegacyViewerFiles(
  SqliteViewerDataRepository repository,
  SqliteWriteContext tx,
) async {
  final definitionsFile = await repository._file(['variables.yaml']);
  final definitions = <ViewerVariableDefinition>[];
  if (await definitionsFile.exists()) {
    final source = await definitionsFile.readAsString();
    if (source.trim().isNotEmpty) {
      try {
        final parsed = loadYaml(source);
        if (parsed is! YamlList) throw const FormatException();
        for (final value in parsed) {
          if (value is! YamlMap) throw const FormatException();
          definitions.add(
            ViewerVariableDefinition.fromJson(
              decodeYamlValue(value) as JsonMap,
            ),
          );
        }
      } catch (_) {
        throw const FormatException(
          'Unsupported or malformed viewer definitions. Source files were preserved.',
        );
      }
    }
  }
  await _saveDefinitions(tx, definitions);
  final root = (await repository._file(['.scope'])).parent;
  if (!await root.exists()) return;
  await for (final entry in root.list(followLinks: false)) {
    final provider = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(provider)) continue;
    if (entry is Link) {
      throw const FormatException(
        'Linked viewer directories cannot be imported.',
      );
    }
    if (entry is! Directory) continue;
    final scopedDirectory = (await repository._file([
      provider,
      '.scope',
    ])).parent;
    await for (final entity in scopedDirectory.list(followLinks: false)) {
      if (!entity.path.endsWith('.json')) continue;
      if (entity is! File) {
        throw const FormatException('Linked viewer rows cannot be imported.');
      }
      final name = entity.uri.pathSegments.last;
      final file = await repository._file([provider, name]);
      try {
        final row = _decodeViewerRow(jsonDecode(await file.readAsString()));
        final expected =
            '${base64Url.encode(utf8.encode(row.viewer.id)).replaceAll('=', '')}.json';
        if (row.provider != provider || expected != name) {
          throw const FormatException();
        }
        await _importRow(tx, row, false);
      } catch (_) {
        throw const FormatException(
          'Viewer catalog contains an invalid row. Source files were preserved.',
        );
      }
    }
  }
}

ViewerDataRow _decodeViewerRow(Object? value) {
  if (value is! Map<String, dynamic> ||
      value['provider'] is! String ||
      value['id'] is! String ||
      value['values'] is! Map<String, dynamic> ||
      (value['displayName'] != null && value['displayName'] is! String)) {
    throw const FormatException('Unsupported viewer row.');
  }
  final row = ViewerDataRow.fromJson(value);
  _validateIdentity(row.provider, row.viewer);
  for (final entry in row.values.entries) {
    _encodedValue(entry.value);
  }
  return row;
}
