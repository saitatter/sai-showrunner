import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart' show SqliteException;
import 'package:sqlite_async/native.dart';
import 'package:sqlite_async/sqlite_async.dart';
import 'package:yaml/yaml.dart';

import '../schema/json.dart';
import '../schema/viewer_data.dart';
import 'document_codec.dart';
import 'document_revision.dart';
import 'filesystem/file_transaction.dart';
import 'filesystem/atomic_file.dart';
import 'filesystem/persistence_directory.dart';
import 'filesystem/safe_path.dart';
import 'viewer_data_repository.dart';

part 'viewer_store/database.dart';
part 'viewer_store/legacy_import.dart';
part 'viewer_store/values.dart';
part 'viewer_store/archive.dart';

/// An owned handle to an asynchronous SQLite pool. Handles for the same canonical
/// path share a pool; closing one never closes another owner's accepted work.
final class SqliteViewerDataRepository implements ViewerDataRepository {
  SqliteViewerDataRepository(this.directory, {this.location});

  final Directory directory;
  final PersistenceDirectory? location;
  Future<_ViewerDatabase>? _lease;
  Future<void>? _closeFuture;
  int _active = 0;
  Completer<void>? _drained;

  Future<File> _file(List<String> names) =>
      location?.file(names) ?? containedFile(directory, names);

  Future<_ViewerDatabase> _acquire() async {
    final file = await _file(['viewers.sqlite']);
    for (final suffix in ['-wal', '-shm', '-journal']) {
      await _file(['viewers.sqlite$suffix']);
    }
    await file.parent.create(recursive: true);
    await _checkDatabaseOwner(file);
    final path = await canonicalPath(file.path);
    return _acquireViewerDatabase(
      path,
      (db) =>
          FileTransaction(
            directory: directory,
            location: location,
            id: 'viewer-database-init',
            targets: const {},
          ).locked(() async {
            await _checkDatabaseOwner(file);
            await _initializeViewerDatabase(
              db,
              (tx) => _importLegacyViewerFiles(this, tx),
            );
            final marker = await _file(['viewers.sqlite-owner']);
            if (!await marker.exists()) {
              await writeAtomicText(marker, _viewerOwnerMarker);
            }
          }),
    );
  }

  Future<void> _checkDatabaseOwner(File file) async {
    final marker = await _file(['viewers.sqlite-owner']);
    if (!await marker.exists()) return;
    if (await marker.length() > 64 ||
        await marker.readAsString() != _viewerOwnerMarker) {
      throw const FormatException('Unsupported viewer store ownership marker.');
    }
    if (!await file.exists() || await file.length() < 100) {
      throw const FormatException(
        'Viewer database is missing or incomplete. Restore a verified backup.',
      );
    }
  }

  Future<T> _run<T>(Future<T> Function(SqliteDatabase db) operation) async {
    if (_closeFuture != null) throw StateError('Viewer data store is closed.');
    _active++;
    try {
      final store = await (_lease ??= _acquire());
      if (!await (await _file(['viewers.sqlite'])).exists()) {
        throw const FormatException(
          'Viewer database is missing. Restore a verified backup.',
        );
      }
      // Do not allow a changed directory junction to redirect a live owner.
      if (_poolKey(
            await canonicalPath((await _file(['viewers.sqlite'])).path),
          ) !=
          _poolKey(store.path)) {
        throw StateError('Viewer data directory changed while open.');
      }
      return await operation(store.db);
    } on SqliteException {
      throw const FormatException(
        'Viewer database operation failed. Stored data was preserved.',
      );
    } finally {
      _active--;
      if (_active == 0) _drained?.complete();
    }
  }

  Future<void> initialize() => _run((_) async {});

  Future<void> close() => _closeFuture ??= _close();
  Future<void> _close() async {
    if (_active != 0) await (_drained ??= Completer<void>()).future;
    final lease = _lease;
    if (lease == null) return;
    final _ViewerDatabase store;
    try {
      store = await lease;
    } catch (_) {
      return; // Failed acquisitions already release their reference.
    }
    await _releaseViewerDatabase(store);
  }

  @override
  Future<List<ViewerVariableDefinition>> loadDefinitions() =>
      _run((db) => db.readTransaction(_definitions));

  @override
  Future<void> saveDefinitions(
    Iterable<ViewerVariableDefinition> definitions, {
    DocumentRevision? expectedRevision,
  }) {
    final values = definitions.toList(growable: false);
    return _run(
      (db) => db.writeTransaction((tx) async {
        final current = await _definitions(tx);
        if (expectedRevision != null &&
            DocumentRevision.of(current.map((d) => d.toJson()).toList()) !=
                expectedRevision) {
          throw PersistenceConflictException('viewer-definitions');
        }
        await _saveDefinitions(tx, values);
      }),
    );
  }

  @override
  Future<JsonMap> getDefaultViewerData() async => {
    for (final definition in await loadDefinitions())
      definition.name: definition.constructedDefault,
  };

  @override
  Future<ViewerDataRow> loadViewer(
    String provider,
    ViewerIdentity viewer,
  ) async {
    _validateIdentity(provider, viewer);
    return _run(
      (db) => db.readTransaction((tx) => _read(tx, provider, viewer)),
    );
  }

  Future<ViewerDataRow> _read(
    SqliteReadContext tx,
    String provider,
    ViewerIdentity viewer,
  ) async {
    final identity = await tx.getOptional(
      'SELECT display_name FROM viewers WHERE provider = ? AND viewer_id = ?',
      [provider, viewer.id],
    );
    final definitions = await _definitions(tx);
    final values = <String, dynamic>{
      for (final definition in definitions)
        definition.name: definition.constructedDefault,
    };
    if (identity != null) {
      for (final row in await tx.getAll(
        '''
        SELECT v.variable_name, v.value_json FROM viewer_values v
        JOIN viewer_variable_definitions d ON d.name = v.variable_name
        WHERE v.provider = ? AND v.viewer_id = ?
      ''',
        [provider, viewer.id],
      )) {
        final definition = definitions.firstWhere(
          (d) => d.name == row['variable_name'],
        );
        values[definition.name] = _storedValue(
          definition,
          row['value_json'] as String,
        );
      }
    }
    return ViewerDataRow(
      provider: provider,
      viewer: identity == null
          ? viewer
          : ViewerIdentity(
              id: viewer.id,
              displayName: identity['display_name'] as String,
            ),
      values: values,
      persisted: identity != null,
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
    _validateProvider(provider);
    final from = start < 0 ? 0 : start;
    final count = end == null ? -1 : (end < from ? 0 : end - from);
    return _run(
      (db) => db.readTransaction((tx) async {
        final direction = descending ? 'DESC' : 'ASC';
        final defined = await tx.getOptional(
          'SELECT name FROM viewer_variable_definitions WHERE name = ?',
          [sortBy],
        );
        final String sql;
        final List<Object?> args;
        if (sortBy != 'id' && sortBy != 'displayName' && defined != null) {
          sql =
              '''WITH page AS MATERIALIZED (
          SELECT provider, viewer_id, sort_rank, sort_number, sort_text, id_sort
          FROM viewer_values INDEXED BY viewer_values_sort
          WHERE provider = ? AND variable_name = ?
          ORDER BY sort_rank $direction, sort_number $direction,
            sort_text $direction, id_sort $direction, viewer_id $direction
          LIMIT ? OFFSET ?)
          SELECT v.viewer_id, v.display_name FROM page s
          JOIN viewers v ON v.provider = s.provider AND v.viewer_id = s.viewer_id
          ORDER BY s.sort_rank $direction, s.sort_number $direction,
            s.sort_text $direction, s.id_sort $direction, s.viewer_id $direction
          ''';
          args = [provider, sortBy, count, from];
        } else {
          final column = sortBy == 'displayName'
              ? 'name_sort $direction, '
              : '';
          sql =
              '''SELECT viewer_id, display_name FROM viewers WHERE provider = ?
          ORDER BY ${column}id_sort $direction, viewer_id $direction
          LIMIT ? OFFSET ?''';
          args = [provider, count, from];
        }
        final page = await tx.getAll(sql, args);
        final definitions = await _definitions(tx);
        final rows = <ViewerDataRow>[];
        // Only hydrate the requested page, never the rest of the viewer catalog.
        for (final identity in page) {
          final values = <String, dynamic>{};
          final stored = await tx.getAll(
            '''SELECT variable_name, value_json
          FROM viewer_values WHERE provider = ? AND viewer_id = ?''',
            [provider, identity['viewer_id']],
          );
          final byName = {
            for (final value in stored) value['variable_name']: value,
          };
          for (final definition in definitions) {
            final encoded = byName[definition.name]?['value_json'] as String?;
            values[definition.name] = encoded == null
                ? definition.constructedDefault
                : _storedValue(definition, encoded);
          }
          rows.add(
            ViewerDataRow(
              provider: provider,
              viewer: ViewerIdentity(
                id: identity['viewer_id'] as String,
                displayName: identity['display_name'] as String,
              ),
              values: values,
            ),
          );
        }
        return rows;
      }),
    );
  }

  @override
  Future<ViewerDataRow> setViewerValue(
    String provider,
    ViewerIdentity viewer,
    String variable,
    dynamic value,
  ) async {
    _validateIdentity(provider, viewer);
    return _run(
      (db) => db.writeTransaction((tx) async {
        final definition = await _definition(tx, variable);
        final normalized = normalizeViewerVariableValue(
          definition.normalizedType,
          value,
        );
        await _ensureViewer(tx, provider, viewer);
        await _putValue(tx, provider, viewer.id, variable, normalized);
        return _read(tx, provider, viewer);
      }),
    );
  }

  @override
  Future<ViewerDataRow> offsetViewerValue(
    String provider,
    ViewerIdentity viewer,
    String variable,
    num offset,
  ) async {
    _validateIdentity(provider, viewer);
    if (!offset.isFinite) throw ArgumentError('Offset must be finite.');
    return _run(
      (db) => db.writeTransaction((tx) async {
        final definition = await _definition(tx, variable);
        if (definition.normalizedType != 'number') {
          throw StateError('Cannot offset a non-number viewer variable.');
        }
        await _ensureViewer(tx, provider, viewer);
        final value = await tx.get(
          '''SELECT value_json FROM viewer_values
        WHERE provider = ? AND viewer_id = ? AND variable_name = ?''',
          [provider, viewer.id, variable],
        );
        final decoded = _storedValue(definition, value['value_json'] as String);
        final base = decoded is num ? decoded : 0;
        if (base is int && offset is int) {
          final sum = BigInt.from(base) + BigInt.from(offset);
          if (sum < BigInt.parse('-9223372036854775808') ||
              sum > BigInt.parse('9223372036854775807')) {
            throw ArgumentError(
              'Viewer numeric update is outside the supported range.',
            );
          }
        }
        final next = base + offset;
        if (!next.isFinite) {
          throw ArgumentError('Viewer numeric update must be finite.');
        }
        await _putValue(tx, provider, viewer.id, variable, next);
        return _read(tx, provider, viewer);
      }),
    );
  }

  @override
  Future<bool> importViewerRow(
    ViewerDataRow row, {
    bool overwrite = false,
  }) async {
    _validateIdentity(row.provider, row.viewer);
    return _run(
      (db) => db.writeTransaction((tx) => _importRow(tx, row, overwrite)),
    );
  }

  @override
  Future<ViewerDataSyncResult> syncViewerIdentity(
    String provider,
    ViewerIdentity viewer,
  ) async {
    _validateIdentity(provider, viewer);
    return _run(
      (db) => db.writeTransaction((tx) async {
        final current = await tx.getOptional(
          'SELECT display_name FROM viewers WHERE provider = ? AND viewer_id = ?',
          [provider, viewer.id],
        );
        final changed =
            current == null || current['display_name'] != viewer.displayName;
        if (current == null) {
          await _ensureViewer(tx, provider, viewer);
        } else if (changed) {
          await tx.execute(
            '''UPDATE viewers SET display_name = ?, name_sort = ?
          WHERE provider = ? AND viewer_id = ?''',
            [
              viewer.displayName,
              viewer.displayName.toLowerCase(),
              provider,
              viewer.id,
            ],
          );
          await tx.execute(
            'UPDATE viewer_values SET is_default = 0 WHERE provider = ? AND viewer_id = ?',
            [provider, viewer.id],
          );
        }
        return ViewerDataSyncResult(
          row: await _read(tx, provider, viewer),
          created: current == null,
          changed: changed,
        );
      }),
    );
  }
}
