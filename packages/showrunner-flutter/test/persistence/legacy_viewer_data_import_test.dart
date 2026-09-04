import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:showrunner_flutter/persistence/legacy_viewer_data_import.dart';
import 'package:showrunner_flutter/persistence/viewer_data_repository.dart';
import 'package:showrunner_flutter/schema/viewer_data.dart';

void main() {
  test('imports legacy SQLite viewer rows and decodes stored values', () async {
    final directory = await Directory.systemTemp.createTemp(
      'showrunner-legacy-viewer-data-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final databaseFile = File('${directory.path}/db.sqlite3');
    final database = sqlite3.open(databaseFile.path);
    database.execute(
      'CREATE TABLE ViewerData '
      '(twitch TEXT UNIQUE, twitch_name TEXT, points REAL, vip INTEGER, metadata TEXT)',
    );
    database.execute(
      'INSERT INTO ViewerData '
      '(twitch, twitch_name, points, vip, metadata) VALUES (?, ?, ?, ?, ?)',
      ['viewer-1', 'Alice', 12.5, 1, '{"badges":["vip"]}'],
    );
    database.execute(
      'INSERT INTO ViewerData (twitch, twitch_name) VALUES (?, ?)',
      [null, 'Invalid'],
    );
    database.close();

    final target = FileViewerDataRepository(
      Directory('${directory.path}/viewer-data'),
    );
    await target.saveDefinitions([
      const ViewerVariableDefinition(name: 'points', type: 'number'),
      const ViewerVariableDefinition(name: 'vip', type: 'boolean'),
      const ViewerVariableDefinition(
        name: 'metadata',
        type: 'object',
        defaultValue: {},
      ),
    ]);

    final report = await const LegacyViewerDataImporter().importFile(
      databaseFile: databaseFile,
      target: target,
    );
    expect(report.imported, 1);
    expect(report.skipped, 0);
    expect(report.invalid, 1);
    expect(report.processed, 2);

    final row = await target.loadViewer(
      'twitch',
      const ViewerIdentity(id: 'viewer-1', displayName: 'Alice'),
    );
    expect(row.viewer.displayName, 'Alice');
    expect(row.values['points'], 12.5);
    expect(row.values['vip'], isTrue);
    expect(row.values['metadata'], {
      'badges': ['vip'],
    });

    final secondReport = await const LegacyViewerDataImporter().importFile(
      databaseFile: databaseFile,
      target: target,
    );
    expect(secondReport.imported, 0);
    expect(secondReport.skipped, 1);
    expect(secondReport.invalid, 1);
  });

  test(
    'supports non-primitive viewer values without overwriting rows',
    () async {
      final repository = InMemoryViewerDataRepository(
        definitions: [
          const ViewerVariableDefinition(
            name: 'profile',
            type: 'object',
            defaultValue: {},
          ),
          const ViewerVariableDefinition(name: 'tags', type: 'list'),
        ],
      );
      final first = await repository.importViewerRow(
        const ViewerDataRow(
          provider: 'twitch',
          viewer: ViewerIdentity(id: 'viewer-2', displayName: 'Bob'),
          values: {
            'profile': {'level': 4},
            'tags': ['regular'],
          },
        ),
      );
      final second = await repository.importViewerRow(
        const ViewerDataRow(
          provider: 'twitch',
          viewer: ViewerIdentity(id: 'viewer-2', displayName: 'Other name'),
          values: {
            'profile': {'level': 9},
          },
        ),
      );

      expect(first, isTrue);
      expect(second, isFalse);
      final row = await repository.loadViewer(
        'twitch',
        const ViewerIdentity(id: 'viewer-2', displayName: 'Bob'),
      );
      expect(row.viewer.displayName, 'Bob');
      expect(row.values['profile'], {'level': 4});
      expect(row.values['tags'], ['regular']);
    },
  );
}
