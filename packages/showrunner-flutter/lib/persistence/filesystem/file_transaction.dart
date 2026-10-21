import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'atomic_file.dart';
import 'safe_path.dart';

/// File operations are injectable for real-filesystem interruption tests. They
/// never receive decoded secret values: secret payloads must already be sealed.
class TransactionFileOperations {
  const TransactionFileOperations();
  Future<void> write(File file, List<int> bytes) =>
      writeAtomicBytes(file, bytes);
  Future<void> remove(File file) async {
    if (await file.exists()) await file.delete();
  }
}

final class FileMutation {
  FileMutation.write(this.target, List<int> bytes)
    : bytes = List.unmodifiable(bytes);
  const FileMutation.remove(this.target) : bytes = null;
  final String target;
  final List<int>? bytes;
}

final class PersistenceConflictException extends StateError {
  PersistenceConflictException(this.document)
    : super(
        'Stored data changed for $document. Reload before saving; pending recovery was preserved.',
      );
  final String document;
}

/// A durable redo journal with a closed target vocabulary. Public file shapes
/// stay unchanged; readers using this owner lock finish a pending generation
/// before observing any member. Raw filesystem readers are not transactional.
final class FileTransaction {
  FileTransaction({
    required this.directory,
    required this.id,
    required Map<String, Future<File> Function()> targets,
    this.operations = const TransactionFileOperations(),
  }) : targets = Map.unmodifiable(targets) {
    validateFileIdentifier(id);
  }
  final Directory directory;
  final String id;
  final Map<String, Future<File> Function()> targets;
  final TransactionFileOperations operations;

  Future<File> get _journal =>
      containedFile(directory, ['.transactions', '$id.json']);

  Future<T> locked<T>(Future<T> Function() operation) async {
    final lockFile = await containedFile(directory, ['.locks', '$id.lock']);
    return withFileLock(lockFile.path, () async {
      await lockFile.parent.create(recursive: true);
      final checked = await containedFile(directory, ['.locks', '$id.lock']);
      final handle = await checked.open(mode: FileMode.append);
      try {
        await handle.lock(FileLock.blockingExclusive);
        try {
          return await operation();
        } finally {
          await handle.unlock();
        }
      } finally {
        await handle.close();
      }
    });
  }

  Future<String?> _digest(File file) async {
    final type = await FileSystemEntity.type(file.path);
    if (type == FileSystemEntityType.notFound) return null;
    if (type != FileSystemEntityType.file) {
      throw FileSystemException('Expected a regular document file.', file.path);
    }
    return sha256.convert(await file.readAsBytes()).toString();
  }

  Future<void> commit(List<FileMutation> mutations) async {
    await recover();
    final seen = <String>{};
    final writes = <Map<String, Object?>>[];
    for (final mutation in mutations) {
      final resolve = targets[mutation.target];
      if (resolve == null || !seen.add(mutation.target)) {
        throw ArgumentError('Transaction targets must be known and unique.');
      }
      writes.add({
        'target': mutation.target,
        'before': await _digest(await resolve()),
        'after': mutation.bytes == null
            ? null
            : sha256.convert(mutation.bytes!).toString(),
        'data': mutation.bytes == null ? null : base64Encode(mutation.bytes!),
      });
    }
    if (writes.isEmpty) return;
    await operations.write(
      await _journal,
      utf8.encode(jsonEncode({'version': 1, 'writes': writes})),
    );
    await recover();
  }

  Future<void> recover() async {
    final journal = await _journal;
    if (!await journal.exists()) return;
    // Decode and validate the entire journal before applying any target.
    final Object? decoded;
    try {
      decoded = jsonDecode(await journal.readAsString());
    } on FormatException {
      throw const FormatException('Invalid persistence recovery journal JSON.');
    }
    if (decoded is! Map ||
        decoded['version'] != 1 ||
        decoded.keys.any((key) => key != 'version' && key != 'writes') ||
        decoded['writes'] is! List) {
      throw const FormatException('Unsupported persistence recovery journal.');
    }
    final raw = decoded['writes'] as List;
    if (raw.isEmpty || raw.length > targets.length) {
      throw const FormatException('Invalid persistence recovery target count.');
    }
    final writes =
        <({String target, String? before, String? after, List<int>? bytes})>[];
    final seen = <String>{};
    bool digest(Object? value) =>
        value == null ||
        value is String && RegExp(r'^[a-f0-9]{64}$').hasMatch(value);
    for (final item in raw) {
      if (item is! Map ||
          item['target'] is! String ||
          !targets.containsKey(item['target']) ||
          !seen.add(item['target'] as String) ||
          !const {
            'target',
            'before',
            'after',
            'data',
          }.every(item.containsKey) ||
          item.keys.any(
            (key) => !const {'target', 'before', 'after', 'data'}.contains(key),
          ) ||
          !digest(item['before']) ||
          !digest(item['after']) ||
          (item['data'] != null && item['data'] is! String)) {
        throw const FormatException('Invalid persistence recovery entry.');
      }
      List<int>? bytes;
      try {
        bytes = item['data'] == null
            ? null
            : base64Decode(item['data'] as String);
      } on FormatException {
        throw const FormatException('Invalid persistence recovery payload.');
      }
      final after = bytes == null ? null : sha256.convert(bytes).toString();
      if (after != item['after']) {
        throw const FormatException('Persistence recovery checksum mismatch.');
      }
      writes.add((
        target: item['target'] as String,
        before: item['before'] as String?,
        after: after,
        bytes: bytes,
      ));
    }
    for (final write in writes) {
      final current = await _digest(await targets[write.target]!());
      if (current != write.before && current != write.after) {
        throw PersistenceConflictException(id);
      }
    }
    for (final write in writes) {
      final file = await targets[write.target]!();
      final current = await _digest(file);
      if (current == write.after) continue;
      if (current != write.before) throw PersistenceConflictException(id);
      if (write.bytes == null) {
        await operations.remove(file);
      } else {
        await operations.write(file, write.bytes!);
      }
    }
    for (final write in writes) {
      if (await _digest(await targets[write.target]!()) != write.after) {
        throw PersistenceConflictException(id);
      }
    }
    await operations.remove(await _journal);
  }
}
