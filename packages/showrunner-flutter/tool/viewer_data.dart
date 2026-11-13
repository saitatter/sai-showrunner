import 'dart:io';
import 'package:showrunner_flutter/persistence/sqlite_viewer_data_repository.dart';

Future<void> main(List<String> args) async {
  if (args.length < 3 ||
      args.length > 4 ||
      !['backup', 'export', 'import'].contains(args[0]) ||
      (args.length == 4 && (args[0] != 'import' || args[3] != '--overwrite'))) {
    stderr.writeln(
      'Usage: dart run tool/viewer_data.dart <backup|export|import> <viewer-data-directory> <file> [--overwrite]',
    );
    exitCode = 64;
    return;
  }
  final repository = SqliteViewerDataRepository(Directory(args[1]));
  try {
    if (args[0] != 'import' && !await repository.directory.exists()) {
      throw StateError('Source viewer data directory does not exist.');
    }
    final file = File(args[2]);
    switch (args[0]) {
      case 'backup':
        await repository.backupTo(file);
        stdout.writeln('Consistent SQLite backup written.');
      case 'export':
        await repository.exportTo(file);
        stdout.writeln('Viewer archive written.');
      case 'import':
        final rows = await repository.importFrom(
          file,
          overwrite: args.length == 4,
        );
        stdout.writeln('Imported $rows viewer rows.');
    }
  } on Object catch (_) {
    stderr.writeln(
      'Viewer data operation failed. Existing data was preserved; check the input format, paths and permissions.',
    );
    exitCode = 1;
  } finally {
    await repository.close();
  }
}
