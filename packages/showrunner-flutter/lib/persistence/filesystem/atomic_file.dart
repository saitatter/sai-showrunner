import 'dart:io';

/// Writes a text document through a sibling temporary file and publishes it
/// with a single rename. A failed write never leaves a stale partial file.
Future<void> writeAtomicText(File file, String contents) async {
  await file.parent.create(recursive: true);
  final temporary = File('${file.path}.tmp');
  try {
    await temporary.writeAsString(contents, flush: true);
    await temporary.rename(file.path);
  } catch (_) {
    if (await temporary.exists()) await temporary.delete();
    rethrow;
  }
}

/// Byte equivalent of [writeAtomicText] for encrypted or otherwise binary
/// artifacts.
Future<void> writeAtomicBytes(File file, List<int> bytes) async {
  await file.parent.create(recursive: true);
  final temporary = File('${file.path}.tmp');
  try {
    await temporary.writeAsBytes(bytes, flush: true);
    await temporary.rename(file.path);
  } catch (_) {
    if (await temporary.exists()) await temporary.delete();
    rethrow;
  }
}
