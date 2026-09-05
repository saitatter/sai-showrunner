import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/persistence/filesystem/atomic_file.dart';

void main() {
  test('publishes complete text and replaces the previous document', () async {
    final directory = await Directory.systemTemp.createTemp(
      'showrunner-atomic-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/state.json');

    await writeAtomicText(file, 'first');
    await writeAtomicText(file, 'second');

    expect(await file.readAsString(), 'second');
    expect(await File('${file.path}.tmp').exists(), isFalse);
  });

  test('cleans the temporary file when publishing fails', () async {
    final directory = await Directory.systemTemp.createTemp(
      'showrunner-atomic-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final target = Directory('${directory.path}/state.json');
    await target.create();
    final file = File(target.path);

    await expectLater(
      writeAtomicText(file, 'content'),
      throwsA(isA<FileSystemException>()),
    );
    expect(await File('${file.path}.tmp').exists(), isFalse);
  });
}
