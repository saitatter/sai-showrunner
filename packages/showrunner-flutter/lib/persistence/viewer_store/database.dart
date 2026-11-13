part of '../sqlite_viewer_data_repository.dart';

const _viewerApplicationId = 1398167364; // SVWD
const _viewerSchemaVersion = 1;
const _viewerOwnerMarker = 'showrunner-viewer-sqlite-v1\n';
final _viewerDatabases = <String, _ViewerDatabase>{};
String _poolKey(String path) => Platform.isWindows ? path.toLowerCase() : path;

final class _ViewerOpenFactory extends NativeSqliteOpenFactory {
  _ViewerOpenFactory(String path)
    : super(
        path: path,
        sqliteOptions: const SqliteOptions(
          journalMode: null,
          maxReaders: 2,
          synchronous: SqliteSynchronous.full,
          lockTimeout: Duration(seconds: 15),
        ),
      );
  @override
  List<String> pragmaStatements(SqliteOpenOptions options) => [
    ...super.pragmaStatements(options),
    'PRAGMA foreign_keys = ON',
  ];
}

final class _ViewerDatabase {
  _ViewerDatabase(this.path, Future<void> Function(SqliteDatabase) initialize)
    : db = SqliteDatabase.withFactory(_ViewerOpenFactory(path)) {
    ready = initialize(db);
  }
  final String path;
  final SqliteDatabase db;
  late final Future<void> ready;
  int owners = 0;
  Future<void>? closing;
}

Future<_ViewerDatabase> _acquireViewerDatabase(
  String path,
  Future<void> Function(SqliteDatabase) initialize,
) async {
  final key = _poolKey(path);
  while (true) {
    final previous = _viewerDatabases[key];
    if (previous?.closing != null) {
      await previous!.closing;
      continue;
    }
    final store = _viewerDatabases.putIfAbsent(
      key,
      () => _ViewerDatabase(path, initialize),
    );
    store.owners++;
    try {
      await store.ready;
      return store;
    } catch (_) {
      await _releaseViewerDatabase(store);
      rethrow;
    }
  }
}

Future<void> _releaseViewerDatabase(_ViewerDatabase store) async {
  if (--store.owners != 0) return;
  final closing = store.closing = store.db.close();
  try {
    await closing;
  } finally {
    final key = _poolKey(store.path);
    if (identical(_viewerDatabases[key], store)) _viewerDatabases.remove(key);
  }
}

Future<void> _initializeViewerDatabase(
  SqliteDatabase db,
  Future<void> Function(SqliteWriteContext) importFiles,
) async {
  // Validate ownership/version before changing the persistent journal mode.
  await db.writeTransaction((tx) async {
    final version = (await tx.get('PRAGMA user_version')).values.first as int;
    final application =
        (await tx.get('PRAGMA application_id')).values.first as int;
    if (version == 0 && application == 0) {
      final objects = await tx.getAll(
        "SELECT name FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'",
      );
      if (objects.isNotEmpty) {
        throw const FormatException(
          'Unrecognized viewer database. Stored data was preserved.',
        );
      }
      for (final statement in _viewerSchema) {
        await tx.execute(statement);
      }
      await tx.execute('PRAGMA application_id = $_viewerApplicationId');
      await tx.execute('PRAGMA user_version = $_viewerSchemaVersion');
    } else if (version != _viewerSchemaVersion ||
        application != _viewerApplicationId) {
      throw const FormatException(
        'Unsupported viewer database version. Stored data was preserved.',
      );
    }
  });
  await db.writeLock((tx) async {
    final mode = (await tx.get('PRAGMA journal_mode = WAL')).values.first;
    if (mode != 'wal') throw StateError('Viewer database requires WAL mode.');
  });
  await db.writeTransaction((tx) async {
    final state = await tx.getOptional(
      'SELECT imported FROM viewer_store_metadata WHERE id = 1',
    );
    if (state == null) {
      throw const FormatException('Invalid viewer database metadata.');
    }
    if (state['imported'] == 0) {
      await importFiles(tx);
      await tx.execute(
        'UPDATE viewer_store_metadata SET imported = 1 WHERE id = 1',
      );
    }
  });
}

const _viewerSchema = [
  '''CREATE TABLE viewer_store_metadata (
    id INTEGER PRIMARY KEY CHECK(id = 1), imported INTEGER NOT NULL CHECK(imported IN (0,1)))''',
  'INSERT INTO viewer_store_metadata VALUES(1, 0)',
  '''CREATE TABLE viewers (
    provider TEXT NOT NULL, viewer_id TEXT NOT NULL, display_name TEXT NOT NULL,
    id_sort TEXT NOT NULL, name_sort TEXT NOT NULL,
    PRIMARY KEY(provider, viewer_id)) WITHOUT ROWID''',
  'CREATE INDEX viewers_by_id ON viewers(provider, id_sort, viewer_id)',
  'CREATE INDEX viewers_by_name ON viewers(provider, name_sort, id_sort, viewer_id)',
  '''CREATE TABLE viewer_variable_definitions (
    name TEXT PRIMARY KEY NOT NULL, ordinal INTEGER NOT NULL,
    definition_json TEXT NOT NULL CHECK(json_valid(definition_json)),
    value_json TEXT NOT NULL CHECK(json_valid(value_json)),
    value_type TEXT NOT NULL, sort_rank INTEGER NOT NULL,
    sort_number NOT NULL, sort_text TEXT NOT NULL)''',
  '''CREATE TABLE viewer_values (
    provider TEXT NOT NULL, viewer_id TEXT NOT NULL, variable_name TEXT NOT NULL,
    value_json TEXT NOT NULL CHECK(json_valid(value_json)),
    value_type TEXT NOT NULL CHECK(value_type IN ('null','number','boolean','string','json')),
    sort_rank INTEGER NOT NULL CHECK(sort_rank BETWEEN 0 AND 4),
    sort_number NOT NULL CHECK(typeof(sort_number) IN ('integer','real')),
    sort_text TEXT NOT NULL, id_sort TEXT NOT NULL,
    is_default INTEGER NOT NULL CHECK(is_default IN (0,1)),
    PRIMARY KEY(provider, viewer_id, variable_name),
    FOREIGN KEY(provider, viewer_id) REFERENCES viewers(provider, viewer_id) ON DELETE CASCADE) WITHOUT ROWID''',
  '''CREATE INDEX viewer_values_sort ON viewer_values(
    provider, variable_name, sort_rank, sort_number, sort_text, id_sort, viewer_id)''',
  'CREATE INDEX viewer_values_by_definition ON viewer_values(variable_name, is_default, value_type)',
];
