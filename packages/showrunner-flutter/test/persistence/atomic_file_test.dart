import 'dart:io';
import 'dart:ffi';
import 'package:ffi/ffi.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/persistence/filesystem/atomic_file.dart';

void main() {
  test(
    'Windows replacement waits for a sharing lock without removing existing data',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'showrunner-atomic-sharing-',
      );
      addTearDown(() => root.delete(recursive: true));
      final file = File('${root.path}/state.json');
      await writeAtomicText(file, 'original');
      final handle = _readWithoutDeleteSharing(file.path);
      final close = DynamicLibrary.open('kernel32.dll')
          .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
            'CloseHandle',
          );
      var closed = false;
      addTearDown(() {
        if (!closed) close(handle);
      });
      final saving = writeAtomicText(file, 'replacement');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(await file.readAsString(), 'original');
      expect(close(handle), isNonZero);
      closed = true;
      await saving;
      expect(await file.readAsString(), 'replacement');
      expect(await root.list().where((f) => f.path.endsWith('.tmp')).length, 0);
    },
    skip: !Platform.isWindows,
  );

  test(
    'Windows permanent sharing failure preserves the original and cleans temporary files',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'showrunner-atomic-sharing-failure-',
      );
      addTearDown(() => root.delete(recursive: true));
      final file = File('${root.path}/state.json');
      await writeAtomicText(file, 'original');
      final handle = _readWithoutDeleteSharing(file.path);
      final close = DynamicLibrary.open('kernel32.dll')
          .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
            'CloseHandle',
          );
      try {
        await expectLater(
          writeAtomicText(file, 'replacement'),
          throwsA(isA<FileSystemException>()),
        );
        expect(await file.readAsString(), 'original');
        expect(
          await root.list().where((f) => f.path.endsWith('.tmp')).length,
          0,
        );
      } finally {
        close(handle);
      }
    },
    skip: !Platform.isWindows,
  );
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

int _readWithoutDeleteSharing(String path) {
  final open = DynamicLibrary.open('kernel32.dll')
      .lookupFunction<
        IntPtr Function(
          Pointer<Utf16>,
          Uint32,
          Uint32,
          Pointer<Void>,
          Uint32,
          Uint32,
          IntPtr,
        ),
        int Function(Pointer<Utf16>, int, int, Pointer<Void>, int, int, int)
      >('CreateFileW');
  final nativePath = path.toNativeUtf16();
  try {
    final handle = open(nativePath, 0x80000000, 1, nullptr, 3, 0x80, 0);
    expect(handle, isNot(-1));
    return handle;
  } finally {
    calloc.free(nativePath);
  }
}
