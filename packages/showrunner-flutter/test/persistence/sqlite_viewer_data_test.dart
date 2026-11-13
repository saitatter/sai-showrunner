import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:showrunner_flutter/persistence/sqlite_viewer_data_repository.dart';
import 'package:showrunner_flutter/schema/viewer_data.dart';

const _points = ViewerVariableDefinition(
  name: 'points',
  type: 'Number',
  defaultValue: 5,
);
const _viewer = ViewerIdentity(id: '42', displayName: 'Viewer');

void main() {
  late Directory root;
  final owners = <SqliteViewerDataRepository>[];
  SqliteViewerDataRepository owner([Directory? directory]) {
    final repository = SqliteViewerDataRepository(directory ?? root);
    owners.add(repository);
    return repository;
  }

  setUp(() async {
    final scratch = await Directory(
      '../../.tmp/viewer-store-tests',
    ).create(recursive: true);
    root = await scratch.createTemp('sqlite-');
  });
  tearDown(() async {
    for (final repository in owners.reversed) {
      await repository.close();
    }
    owners.clear();
    await root.delete(recursive: true);
  });

  test(
    'integer precision, numeric overflow and malformed values never reset accepted data',
    () async {
      final repository = owner();
      await repository.saveDefinitions([_points]);
      const large = 9007199254740993;
      expect(
        (await repository.setViewerValue(
          'twitch',
          _viewer,
          'points',
          large,
        )).values['points'],
        large,
      );
      expect(
        (await repository.offsetViewerValue(
          'twitch',
          _viewer,
          'points',
          1,
        )).values['points'],
        large + 1,
      );
      await repository.setViewerValue(
        'twitch',
        _viewer,
        'points',
        9223372036854775807,
      );
      await expectLater(
        repository.offsetViewerValue('twitch', _viewer, 'points', 1),
        throwsArgumentError,
      );
      expect(
        (await repository.loadViewer('twitch', _viewer)).values['points'],
        9223372036854775807,
      );
      final raw = sqlite3.open('${root.path}/viewers.sqlite');
      raw.execute(
        '''UPDATE viewer_values SET value_json = ?, value_type = 'string',
      sort_rank = 3, sort_number = 0, sort_text = 'private-marker' WHERE variable_name = 'points' ''',
        [jsonEncode('private-marker')],
      );
      for (final read in [
        () => repository.loadViewer('twitch', _viewer),
        () => repository.offsetViewerValue('twitch', _viewer, 'points', 1),
      ]) {
        try {
          await read();
          fail('Malformed value accepted');
        } on FormatException catch (error) {
          expect(error.toString(), isNot(contains('private-marker')));
        }
      }
      expect(
        raw.select('SELECT value_json FROM viewer_values').single['value_json'],
        jsonEncode('private-marker'),
      );
      raw.execute(
        'UPDATE viewer_variable_definitions SET definition_json = ?',
        [
          jsonEncode({'name': 'points', 'type': 'private-marker'}),
        ],
      );
      await expectLater(
        repository.saveDefinitions([_points]),
        throwsFormatException,
      );
      expect(
        raw
            .select('SELECT definition_json FROM viewer_variable_definitions')
            .single['definition_json'],
        contains('private-marker'),
      );
      raw.close();
    },
  );

  test(
    'imports the current file store once and preserves originals and unknown values',
    () async {
      final definitions = File('${root.path}/variables.yaml');
      await definitions.writeAsString(
        '- name: points\n  type: Number\n  defaultValue: 5\n',
      );
      final original = await _legacyRow(root, 'twitch', '42', {
        'points': 12,
        'future': {'opaque': true},
      });
      final originalBytes = await original.readAsBytes();
      await _legacyRow(root, 'youtube', '42', {'points': 21});
      final repository = owner();
      expect((await repository.loadViewer('twitch', _viewer)).values, {
        'points': 12,
      });
      expect((await repository.loadViewer('youtube', _viewer)).values, {
        'points': 21,
      });
      expect(await original.readAsBytes(), originalBytes);
      await repository.saveDefinitions([
        _points,
        const ViewerVariableDefinition(name: 'future', type: 'Object'),
      ]);
      expect(
        (await repository.loadViewer('twitch', _viewer)).values['future'],
        {'opaque': true},
      );
      await repository.close();
      await original.writeAsString('{ broken old file');
      expect(
        (await owner().loadViewer('twitch', _viewer)).values['points'],
        12,
      );
    },
  );

  test(
    'a missing migrated database never silently restores stale source JSON',
    () async {
      final original = await _legacyRow(root, 'twitch', '42', {'points': 7});
      final repository = owner();
      await repository.saveDefinitions([_points]);
      await repository.setViewerValue('twitch', _viewer, 'points', 99);
      await repository.close();
      expect(await File('${root.path}/viewers.sqlite-owner').exists(), true);
      await File('${root.path}/viewers.sqlite').delete();
      final restarted = owner();
      await expectLater(restarted.initialize(), throwsFormatException);
      await restarted.close();
      expect(await File('${root.path}/viewers.sqlite').exists(), false);
      expect(jsonDecode(await original.readAsString())['values'], {
        'points': 7,
      });
    },
  );

  test(
    'a failed import rolls back every row and can be retried after restart',
    () async {
      final first = await _legacyRow(root, 'twitch', 'a', {'unknown': 7});
      final second = await _legacyRow(root, 'twitch', 'b', {'unknown': 8});
      await second.writeAsString('{ private-marker');
      final repository = owner();
      try {
        await repository.initialize();
        fail('Corrupt migration accepted');
      } on FormatException catch (error) {
        expect(error.toString(), isNot(contains('private-marker')));
      }
      await repository.close();
      final inspect = sqlite3.open('${root.path}/viewers.sqlite');
      expect(
        inspect.select('SELECT count(*) AS n FROM viewers').single['n'],
        0,
      );
      expect(
        inspect
            .select('SELECT imported FROM viewer_store_metadata')
            .single['imported'],
        0,
      );
      inspect.close();
      expect(await first.exists(), true);
      await _legacyRow(root, 'twitch', 'b', {'unknown': 8});
      expect(await owner().queryViewers('twitch'), hasLength(2));
    },
  );

  test(
    'future schemas and corrupt databases remain byte-for-byte intact',
    () async {
      final database = File('${root.path}/viewers.sqlite');
      final raw = sqlite3.open(database.path);
      raw.execute('PRAGMA application_id = 1398167364');
      raw.execute('PRAGMA user_version = 99');
      raw.execute('CREATE TABLE future_data(value TEXT)');
      raw.execute("INSERT INTO future_data VALUES('private-marker')");
      raw.close();
      final bytes = await database.readAsBytes();
      final repository = owner();
      await expectLater(repository.initialize(), throwsFormatException);
      await repository.close();
      expect(await database.readAsBytes(), bytes);
      await database.writeAsString('not sqlite private-marker');
      final corrupt = owner();
      await expectLater(corrupt.initialize(), throwsFormatException);
      await corrupt.close();
      expect(await database.readAsString(), 'not sqlite private-marker');
    },
  );

  test(
    'explicit defaults, missing fields and explicit null retain their semantics',
    () async {
      final repository = owner();
      await repository.saveDefinitions([_points]);
      await repository.syncViewerIdentity('twitch', _viewer);
      await repository.saveDefinitions([
        const ViewerVariableDefinition(
          name: 'points',
          type: 'Number',
          defaultValue: 9,
        ),
        const ViewerVariableDefinition(
          name: 'bonus',
          type: 'Number',
          defaultValue: 7,
        ),
      ]);
      expect((await repository.loadViewer('twitch', _viewer)).values, {
        'points': 5,
        'bonus': 7,
      });
      await repository.setViewerValue('twitch', _viewer, 'points', null);
      await repository.saveDefinitions([
        const ViewerVariableDefinition(
          name: 'points',
          type: 'Number',
          defaultValue: 11,
        ),
        const ViewerVariableDefinition(
          name: 'bonus',
          type: 'Number',
          defaultValue: 13,
        ),
      ]);
      expect((await repository.loadViewer('twitch', _viewer)).values, {
        'points': null,
        'bonus': 7,
      });
      final missing = await repository.loadViewer(
        'twitch',
        const ViewerIdentity(id: 'new', displayName: 'New'),
      );
      expect(missing.persisted, false);
      expect(missing.values, {'points': 11, 'bonus': 13});
      expect(
        (await repository.offsetViewerValue(
          'twitch',
          _viewer,
          'points',
          1,
        )).values['points'],
        1,
      );
    },
  );

  test(
    'typed sorting has stable ties, provider isolation and SQL pagination',
    () async {
      final repository = owner();
      await repository.saveDefinitions([
        const ViewerVariableDefinition(
          name: 'value',
          type: 'Json',
          required: false,
        ),
      ]);
      final values = [
        null,
        2,
        10,
        false,
        true,
        'A',
        'a',
        {'x': 1},
      ];
      for (var i = values.length - 1; i >= 0; i--) {
        await repository.setViewerValue(
          'twitch',
          ViewerIdentity(id: '$i', displayName: 'Same'),
          'value',
          values[i],
        );
      }
      await repository.setViewerValue('youtube', _viewer, 'value', 999);
      expect(
        (await repository.queryViewers(
          'twitch',
          sortBy: 'value',
        )).map((r) => r.viewer.id),
        List.generate(values.length, (i) => '$i'),
      );
      expect(
        (await repository.queryViewers(
          'twitch',
          sortBy: 'value',
          descending: true,
          start: 1,
          end: 4,
        )).map((r) => r.viewer.id),
        ['6', '5', '4'],
      );
      expect(
        await repository.queryViewers('twitch', start: 10, end: 2),
        isEmpty,
      );
      expect(
        (await repository.queryViewers(
          'twitch',
          sortBy: 'unknown',
        )).first.viewer.id,
        '0',
      );
      final raw = sqlite3.open('${root.path}/viewers.sqlite');
      final plan = raw.select(
        '''EXPLAIN QUERY PLAN SELECT viewer_id FROM viewer_values
      WHERE provider = 'twitch' AND variable_name = 'value'
      ORDER BY sort_rank DESC, sort_number DESC, sort_text DESC, id_sort DESC, viewer_id DESC LIMIT 25''',
      ).toString();
      expect(plan, contains('viewer_values_sort'));
      expect(plan, isNot(contains('TEMP B-TREE')));
      raw.close();
    },
  );

  test(
    'independent owners increment atomically and closing a handle is isolated',
    () async {
      final first = owner(), second = owner();
      await first.saveDefinitions([_points]);
      final writes = List.generate(
        50,
        (i) => (i.isEven ? first : second).offsetViewerValue(
          'twitch',
          _viewer,
          'points',
          1,
        ),
      );
      final closing = first.close();
      await Future.wait(writes);
      await closing;
      expect((await second.loadViewer('twitch', _viewer)).values['points'], 55);
      await expectLater(first.loadViewer('twitch', _viewer), throwsStateError);
      expect(
        (await second.offsetViewerValue(
          'twitch',
          _viewer,
          'points',
          1,
        )).values['points'],
        56,
      );
    },
  );

  test(
    'archives and live WAL backups round trip without overwriting existing outputs',
    () async {
      final repository = owner();
      await repository.saveDefinitions([_points]);
      await repository.setViewerValue('twitch', _viewer, 'points', 42);
      final archive = File('${root.path}/export.ndjson'),
          backup = File('${root.path}/backup.sqlite');
      await repository.exportTo(archive);
      await repository.backupTo(backup);
      final snapshot = sqlite3.open(backup.path);
      expect(
        snapshot.select('PRAGMA integrity_check').single.values.single,
        'ok',
      );
      expect(
        snapshot
            .select('SELECT value_json FROM viewer_values')
            .single['value_json'],
        '42',
      );
      snapshot.close();
      await expectLater(
        repository.backupTo(backup),
        throwsA(isA<FileSystemException>()),
      );
      final target = owner(Directory('${root.path}/restored'));
      expect(await target.importFrom(archive), 1);
      expect((await target.loadViewer('twitch', _viewer)).values['points'], 42);
      expect(await target.importFrom(archive), 0);
      final truncated = File('${root.path}/truncated.ndjson');
      final lines = await archive.readAsLines();
      await truncated.writeAsString(
        '${lines.take(lines.length - 1).join('\n')}\n',
      );
      final empty = owner(Directory('${root.path}/incomplete'));
      await expectLater(empty.importFrom(truncated), throwsFormatException);
      expect(await empty.queryViewers('twitch'), isEmpty);
    },
  );

  test(
    'separate processes serialize writes and recover committed/uncommitted WAL after abrupt exit',
    () async {
      final repository = owner();
      await repository.saveDefinitions([_points]);
      await repository.syncViewerIdentity('twitch', _viewer);
      final output = '${root.absolute.path}/worker';
      final build = await Process.run('dart', [
        'build',
        'cli',
        '--target=test/support/viewer_store_process_fixture.dart',
        '--output=$output',
      ], runInShell: Platform.isWindows);
      expect(build.exitCode, 0, reason: '${build.stdout}\n${build.stderr}');
      final executable =
          '$output/bundle/bin/viewer_store_process_fixture${Platform.isWindows ? '.exe' : ''}';
      Future<ProcessResult> run(String mode) =>
          Process.run(executable, [root.absolute.path, mode]);
      final results = await Future.wait([
        run('increment'),
        run('increment'),
        run('increment'),
      ]);
      for (final result in results) {
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
      }
      expect(
        (await repository.loadViewer('twitch', _viewer)).values['points'],
        80,
      );
      expect((await run('crash-uncommitted')).exitCode, 73);
      expect(
        (await repository.loadViewer('twitch', _viewer)).values['points'],
        80,
      );
      expect((await run('crash-committed')).exitCode, 73);
      expect(
        (await repository.loadViewer('twitch', _viewer)).values['points'],
        81,
      );
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );
}

Future<File> _legacyRow(
  Directory root,
  String provider,
  String id,
  Map<String, dynamic> values,
) async {
  final folder = await Directory(
    '${root.path}/$provider',
  ).create(recursive: true);
  final name = base64Url.encode(utf8.encode(id)).replaceAll('=', '');
  return File('${folder.path}/$name.json').writeAsString(
    jsonEncode({
      'provider': provider,
      'id': id,
      'displayName': 'Viewer',
      'values': values,
    }),
  );
}
