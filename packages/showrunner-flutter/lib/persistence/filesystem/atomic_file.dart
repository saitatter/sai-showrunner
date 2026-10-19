import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'safe_path.dart';

final _fileOperations = <String, Future<void>>{};
int _temporarySequence = 0;

/// Serializes complete read/modify/write transactions, including failures.
Future<T> withFileLock<T>(String path, Future<T> Function() operation) async {
  final resolved = await canonicalPath(path);
  final key = Platform.isWindows ? resolved.toLowerCase() : resolved;
  final previous = _fileOperations[key];
  final release = Completer<void>();
  _fileOperations[key] = release.future;
  if (previous != null) await previous;
  try {
    return await operation();
  } finally {
    release.complete();
    if (identical(_fileOperations[key], release.future)) {
      _fileOperations.remove(key);
    }
  }
}

Future<void> writeAtomicText(File file, String contents) =>
    writeAtomicBytes(file, utf8.encode(contents));

Future<void> writeAtomicBytes(File file, List<int> bytes) =>
    withFileLock(file.path, () async {
      await file.parent.create(recursive: true);
      final temporary = File('${file.path}.$pid.${_temporarySequence++}.tmp');
      try {
        await temporary.writeAsBytes(bytes, flush: true);
        await temporary.rename(file.path);
      } finally {
        if (await temporary.exists()) await temporary.delete();
      }
    });
