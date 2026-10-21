import 'dart:io';
import 'dart:convert';
import 'package:showrunner_flutter/persistence/filesystem/file_transaction.dart';
import 'package:showrunner_flutter/persistence/filesystem/safe_path.dart';

Future<void> main(List<String> arguments) async {
  final root = Directory(arguments[0]);
  final mode = arguments[1];
  if (mode == 'probe') {
    final file = await containedFile(root, ['.locks', 'fixture.lock']);
    final handle = await file.open(mode: FileMode.append);
    try {
      try {
        await handle.lock(FileLock.exclusive);
      } on FileSystemException {
        stdout.writeln('blocked');
        return;
      }
      stdout.writeln('acquired');
      await handle.unlock();
    } finally {
      await handle.close();
    }
    return;
  }
  final owner = FileTransaction(
    directory: root,
    id: 'fixture',
    targets: {
      for (final name in ['a', 'b'])
        name: () => containedFile(root, ['$name.json']),
    },
    operations: mode == 'crash'
        ? CrashFiles()
        : const TransactionFileOperations(),
  );
  await owner.locked(() async {
    if (mode == 'hold') {
      stdout.writeln('locked');
      await stdin.first;
      return;
    }
    await owner.commit([
      for (final name in ['a', 'b'])
        FileMutation.write(name, utf8.encode('new-$name')),
    ]);
  });
}

final class CrashFiles extends TransactionFileOperations {
  int writes = 0;
  @override
  Future<void> write(File file, List<int> bytes) async {
    await super.write(file, bytes);
    if (++writes == 2) exit(73);
  }
}
