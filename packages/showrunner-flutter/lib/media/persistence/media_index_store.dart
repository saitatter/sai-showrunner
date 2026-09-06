import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import '../domain/media_file.dart';

final class MediaIndexStore {
  const MediaIndexStore(this.databaseFile);

  final File databaseFile;

  Future<List<MediaIndexRecord>> loadRoot(String root) async {
    final database = await _open();
    try {
      return database
          .select(
            '''
SELECT id, root, relative_path, path_key, extension, kind, size_bytes,
       modified_at_ms, metadata_json, extractor_version,
       metadata_schema_version, last_metadata_scan_ms, scan_error
FROM media_files
WHERE root = ?
ORDER BY relative_path COLLATE NOCASE
''',
            [root],
          )
          .map(_fromRow)
          .toList(growable: false);
    } finally {
      database.close();
    }
  }

  Future<int> nextGeneration(String root) async {
    final database = await _open();
    try {
      final rows = database.select(
        'SELECT generation FROM scan_state WHERE root = ?',
        [root],
      );
      final current = rows.isEmpty ? 0 : (rows.single['generation'] as int);
      final next = current + 1;
      database.execute(
        '''
INSERT INTO scan_state (root, generation) VALUES (?, ?)
ON CONFLICT(root) DO UPDATE SET generation = excluded.generation
''',
        [root, next],
      );
      return next;
    } finally {
      database.close();
    }
  }

  Future<List<MediaIndexRecord>> reconcile({
    required String root,
    required int generation,
    required Iterable<MediaIndexRecord> records,
    required Iterable<int> removedIds,
  }) async {
    final database = await _open();
    try {
      database.execute('BEGIN');
      try {
        for (final id in removedIds) {
          database.execute('DELETE FROM media_files WHERE id = ?', [id]);
        }
        for (final record in records) {
          final values = [
            record.root,
            record.relativePath,
            record.pathKey,
            record.extension,
            record.kind.name,
            record.sizeBytes,
            record.modifiedAtMs,
            record.metadata == null
                ? null
                : jsonEncode(record.metadata!.toJson()),
            record.extractorVersion,
            record.metadataSchemaVersion,
            record.lastMetadataScanMs,
            record.scanError,
            generation,
          ];
          if (record.id == null) {
            database.execute('''
INSERT INTO media_files (
  root, relative_path, path_key, extension, kind, size_bytes,
  modified_at_ms, metadata_json, extractor_version, metadata_schema_version,
  last_metadata_scan_ms, scan_error, last_seen_generation
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
''', values);
          } else {
            database.execute(
              '''
UPDATE media_files SET
  root = ?, relative_path = ?, path_key = ?, extension = ?, kind = ?,
  size_bytes = ?, modified_at_ms = ?, metadata_json = ?,
  extractor_version = ?, metadata_schema_version = ?,
  last_metadata_scan_ms = ?, scan_error = ?, last_seen_generation = ?
WHERE id = ?
''',
              [...values, record.id],
            );
          }
        }
        database.execute('COMMIT');
      } on Object {
        database.execute('ROLLBACK');
        rethrow;
      }
      return database
          .select(
            '''
SELECT id, root, relative_path, path_key, extension, kind, size_bytes,
       modified_at_ms, metadata_json, extractor_version,
       metadata_schema_version, last_metadata_scan_ms, scan_error
FROM media_files
WHERE root = ?
ORDER BY relative_path COLLATE NOCASE
''',
            [root],
          )
          .map(_fromRow)
          .toList(growable: false);
    } finally {
      database.close();
    }
  }

  Future<Database> _open() async {
    await databaseFile.parent.create(recursive: true);
    final database = sqlite3.open(databaseFile.path);
    database.execute('PRAGMA journal_mode = WAL');
    database.execute('PRAGMA synchronous = NORMAL');
    database.execute('''
CREATE TABLE IF NOT EXISTS media_files (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  root TEXT NOT NULL,
  relative_path TEXT NOT NULL,
  path_key TEXT NOT NULL,
  extension TEXT NOT NULL,
  kind TEXT NOT NULL,
  size_bytes INTEGER NOT NULL,
  modified_at_ms INTEGER NOT NULL,
  metadata_json TEXT,
  extractor_version TEXT NOT NULL DEFAULT '',
  metadata_schema_version INTEGER NOT NULL DEFAULT 1,
  last_metadata_scan_ms INTEGER,
  scan_error TEXT,
  last_seen_generation INTEGER NOT NULL DEFAULT 0,
  UNIQUE(root, path_key)
)
''');
    database.execute('''
CREATE TABLE IF NOT EXISTS scan_state (
  root TEXT PRIMARY KEY,
  generation INTEGER NOT NULL DEFAULT 0
)
''');
    database.execute(
      'CREATE INDEX IF NOT EXISTS media_files_root_path ON media_files(root, relative_path)',
    );
    return database;
  }
}

MediaIndexRecord _fromRow(Row row) {
  final metadataValue = row['metadata_json'];
  MediaMetadata? metadata;
  if (metadataValue is String && metadataValue.isNotEmpty) {
    try {
      final decoded = jsonDecode(metadataValue);
      if (decoded is Map) {
        metadata = MediaMetadata.fromJson(Map<String, dynamic>.from(decoded));
      }
    } on Object {
      metadata = null;
    }
  }
  return MediaIndexRecord(
    id: row['id'] as int,
    root: row['root'] as String,
    relativePath: row['relative_path'] as String,
    pathKey: row['path_key'] as String,
    extension: row['extension'] as String,
    kind: MediaKind.values.byName(row['kind'] as String),
    sizeBytes: row['size_bytes'] as int,
    modifiedAtMs: row['modified_at_ms'] as int,
    metadata: metadata,
    extractorVersion: row['extractor_version'] as String,
    metadataSchemaVersion: row['metadata_schema_version'] as int,
    lastMetadataScanMs: row['last_metadata_scan_ms'] as int?,
    scanError: row['scan_error'] as String?,
  );
}
