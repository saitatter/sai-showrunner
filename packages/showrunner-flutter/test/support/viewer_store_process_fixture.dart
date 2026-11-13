import 'dart:io';

import 'package:sqlite_async/sqlite_async.dart';
import 'package:showrunner_flutter/persistence/filesystem/safe_path.dart';
import 'package:showrunner_flutter/persistence/sqlite_viewer_data_repository.dart';
import 'package:showrunner_flutter/schema/viewer_data.dart';

Future<void> main(List<String> args) async {
  final root = Directory(args[0]);
  if (!pathIsWithin(
    Directory('../../.tmp').absolute.path,
    root.absolute.path,
  )) {
    throw StateError('Fixture must use workspace .tmp storage.');
  }
  final repository = SqliteViewerDataRepository(root);
  const viewer = ViewerIdentity(id: '42', displayName: 'Viewer');
  await repository.initialize();
  switch (args[1]) {
    case 'increment':
      for (var i = 0; i < 25; i++) {
        await repository.offsetViewerValue('twitch', viewer, 'points', 1);
      }
      await repository.close();
    case 'crash-committed':
      await repository.offsetViewerValue('twitch', viewer, 'points', 1);
      exit(73);
    case 'crash-uncommitted':
      final database = SqliteDatabase(path: '${root.path}/viewers.sqlite');
      await database.writeTransaction((tx) async {
        await tx.execute(
          "UPDATE viewer_values SET value_json = '999', sort_number = 999 WHERE variable_name = 'points'",
        );
        exit(73);
      });
    default:
      throw ArgumentError('Unknown fixture mode.');
  }
}
