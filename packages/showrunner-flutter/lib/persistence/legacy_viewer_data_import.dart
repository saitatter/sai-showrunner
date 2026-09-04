import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import '../schema/viewer_data.dart';
import 'viewer_data_repository.dart';

final class ViewerDataImportReport {
  const ViewerDataImportReport({
    required this.imported,
    required this.skipped,
    required this.invalid,
  });

  final int imported;
  final int skipped;
  final int invalid;

  int get processed => imported + skipped + invalid;
}

/// Imports rows from the Electron viewer-data database without modifying it.
final class LegacyViewerDataImporter {
  const LegacyViewerDataImporter();

  Future<ViewerDataImportReport> importFile({
    required File databaseFile,
    required ViewerDataRepository target,
    String provider = 'twitch',
    bool overwrite = false,
  }) async {
    if (!await databaseFile.exists()) {
      throw StateError('Legacy viewer data database was not found.');
    }
    final database = sqlite3.open(databaseFile.path, mode: OpenMode.readOnly);
    try {
      final tables = database.select(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
        ['ViewerData'],
      );
      if (tables.isEmpty) {
        throw const FormatException(
          'The legacy database does not contain a ViewerData table.',
        );
      }
      final rows = database.select('SELECT * FROM ViewerData');
      final definitions = {
        for (final definition in await target.loadDefinitions())
          definition.name: definition,
      };
      var imported = 0;
      var skipped = 0;
      var invalid = 0;
      final idColumn = provider.trim();
      final nameColumn = '${provider.trim()}_name';
      for (final row in rows) {
        final id = row[idColumn]?.toString().trim() ?? '';
        if (id.isEmpty) {
          invalid++;
          continue;
        }
        final displayName = row[nameColumn]?.toString() ?? id;
        final values = <String, dynamic>{};
        for (final column in rows.columnNames) {
          if (column == idColumn || column == nameColumn) continue;
          final value = row[column];
          if (value == null) continue;
          values[column] = _normalizeLegacyValue(
            definitions[column]?.normalizedType,
            value,
          );
        }
        final didImport = await target.importViewerRow(
          ViewerDataRow(
            provider: provider,
            viewer: ViewerIdentity(id: id, displayName: displayName),
            values: values,
          ),
          overwrite: overwrite,
        );
        if (didImport) {
          imported++;
        } else {
          skipped++;
        }
      }
      return ViewerDataImportReport(
        imported: imported,
        skipped: skipped,
        invalid: invalid,
      );
    } finally {
      database.close();
    }
  }
}

dynamic _decodeLegacyValue(dynamic value) {
  if (value is! String) return value;
  final trimmed = value.trim();
  if (trimmed.isEmpty) return value;
  if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
    try {
      return jsonDecode(trimmed);
    } on FormatException {
      return value;
    }
  }
  return value;
}

dynamic _normalizeLegacyValue(String? type, dynamic value) {
  final decoded = _decodeLegacyValue(value);
  switch (type) {
    case 'number':
      if (decoded is num) return decoded;
      return num.tryParse('$decoded') ?? decoded;
    case 'boolean':
      if (decoded is bool) return decoded;
      if (decoded is num && (decoded == 0 || decoded == 1)) {
        return decoded == 1;
      }
      if (decoded is String) {
        final normalized = decoded.toLowerCase();
        if (normalized == 'true' || normalized == '1') return true;
        if (normalized == 'false' || normalized == '0') return false;
      }
    case 'json':
    case 'object':
    case 'list':
    case 'twitchviewer':
      return decoded;
  }
  return decoded;
}
