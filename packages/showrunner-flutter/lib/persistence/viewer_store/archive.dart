part of '../sqlite_viewer_data_repository.dart';

/// Explicit portable interchange and consistent online backup operations.
extension ViewerDataArchive on SqliteViewerDataRepository {
  Future<void> backupTo(File target) => _run((db) async {
    await target.parent.create(recursive: true);
    await target.create(exclusive: true);
    // VACUUM INTO snapshots the live database including committed WAL contents;
    // copying only viewers.sqlite would lose uncheckpointed transactions.
    await db.writeLock((tx) async {
      await tx.execute('VACUUM INTO ?', [target.absolute.path]);
    });
  });

  Future<void> exportTo(File target) => _run((db) async {
    await target.parent.create(recursive: true);
    await target.create(exclusive: true);
    final sink = target.openWrite();
    try {
      await db.readTransaction((tx) async {
        sink.writeln(
          jsonEncode({
            'format': 'showrunner.viewer-data',
            'version': 1,
            'definitions': (await _definitions(
              tx,
            )).map((d) => d.toJson()).toList(),
          }),
        );
        var count = 0;
        String? lastProvider, lastId;
        while (true) {
          final page = await tx.getAll(
            '''SELECT provider, viewer_id, display_name FROM viewers
            ${lastProvider == null ? '' : 'WHERE (provider, viewer_id) > (?, ?)'}
            ORDER BY provider, viewer_id LIMIT 500''',
            lastProvider == null ? [] : [lastProvider, lastId],
          );
          if (page.isEmpty) break;
          for (final row in page) {
            final values = await tx.getAll(
              '''SELECT variable_name, value_json FROM viewer_values
              WHERE provider = ? AND viewer_id = ?''',
              [row['provider'], row['viewer_id']],
            );
            sink.writeln(
              jsonEncode({
                'viewer': ViewerDataRow(
                  provider: row['provider'] as String,
                  viewer: ViewerIdentity(
                    id: row['viewer_id'] as String,
                    displayName: row['display_name'] as String,
                  ),
                  values: {
                    for (final value in values)
                      value['variable_name'] as String: jsonDecode(
                        value['value_json'] as String,
                      ),
                  },
                ).toJson(),
              }),
            );
            count++;
          }
          await sink.flush();
          lastProvider = page.last['provider'] as String;
          lastId = page.last['viewer_id'] as String;
        }
        sink.writeln(jsonEncode({'complete': true, 'viewers': count}));
        await sink.flush();
      });
    } finally {
      await sink.close();
    }
  });

  Future<int> importFrom(File source, {bool overwrite = false}) => _run(
    (db) => db.writeTransaction((tx) async {
      var line = 0, count = 0, imported = 0;
      var completed = false;
      final seen = <String>{};
      await for (final text
          in source
              .openRead()
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        line++;
        final Object? decoded;
        try {
          decoded = jsonDecode(text);
        } catch (_) {
          throw const FormatException(
            'Malformed viewer archive. No rows were imported.',
          );
        }
        if (decoded is! Map<String, dynamic> || completed) {
          throw const FormatException('Invalid viewer archive structure.');
        }
        if (line == 1) {
          if (decoded['format'] != 'showrunner.viewer-data' ||
              decoded['version'] != 1 ||
              decoded['definitions'] is! List) {
            throw const FormatException('Unsupported viewer archive.');
          }
          final incoming = [
            for (final value in decoded['definitions'] as List)
              ViewerVariableDefinition.fromJson(value as JsonMap),
          ];
          final current = {for (final d in await _definitions(tx)) d.name: d};
          final names = <String>{};
          for (final definition in incoming) {
            if (!names.add(definition.name)) {
              throw const FormatException(
                'Duplicate viewer archive definition.',
              );
            }
            final existing = current[definition.name];
            if (existing != null &&
                jsonEncode(existing.toJson()) !=
                    jsonEncode(definition.toJson()) &&
                !overwrite) {
              throw const FormatException(
                'Viewer archive definitions conflict with existing definitions.',
              );
            }
            current[definition.name] = definition;
          }
          await _saveDefinitions(tx, current.values.toList());
        } else if (decoded['complete'] == true) {
          if (decoded['viewers'] != count) {
            throw const FormatException('Incomplete viewer archive.');
          }
          completed = true;
        } else {
          final row = _decodeViewerRow(decoded['viewer']);
          if (!seen.add(jsonEncode([row.provider, row.viewer.id]))) {
            throw const FormatException('Duplicate viewer in archive.');
          }
          if (await _importRow(tx, row, overwrite)) imported++;
          count++;
        }
      }
      if (!completed) {
        throw const FormatException(
          'Incomplete viewer archive. No rows were imported.',
        );
      }
      return imported;
    }),
  );
}
