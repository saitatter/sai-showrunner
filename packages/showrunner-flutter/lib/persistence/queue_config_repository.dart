import 'document_revision.dart';
import 'filesystem/typed_document_file.dart';
import 'document_codec.dart';
import 'dart:io';

import 'filesystem/safe_path.dart';
import '../schema/queue.dart';

final class QueueConfigRepository {
  const QueueConfigRepository(this.directory);

  final Directory directory;

  Future<List<({String fileName, QueueConfig? config, Object? error})>>
  list() async {
    if (!await directory.exists()) return const [];
    final files = await directory
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.yaml'))
        .cast<File>()
        .toList();
    files.sort((a, b) => a.path.compareTo(b.path));
    final result = <({String fileName, QueueConfig? config, Object? error})>[];
    for (final file in files) {
      try {
        result.add((
          fileName: file.uri.pathSegments.last,
          config: await load(file),
          error: null,
        ));
      } catch (error) {
        result.add((
          fileName: file.uri.pathSegments.last,
          config: null,
          error: error,
        ));
      }
    }
    return result;
  }

  Future<QueueConfig> load(File file) async {
    if (!pathIsWithin(directory.absolute.path, file.absolute.path)) {
      throw ArgumentError('Queue file leaves the repository.');
    }
    file = await containedFile(directory, [file.uri.pathSegments.last]);
    final config = await _store(file).load();
    if (config == null) throw const FormatException('Queue config is missing.');
    return config;
  }

  TypedDocumentFile<QueueConfig> _store(File file) => TypedDocumentFile(
    file: file,
    kind: 'queue',
    decode: QueueConfig.fromJson,
    encode: (value) => value.toJson(),
    format: encodeYaml,
  );

  Future<void> save(
    String fileName,
    QueueConfig config, {
    DocumentRevision? expectedRevision,
    bool requireAbsent = false,
  }) async {
    validateFileIdentifier(fileName);
    final file = await containedFile(directory, [fileName]);
    await _store(file).save(
      config,
      expectedRevision: expectedRevision,
      requireAbsent: requireAbsent,
    );
  }

  Future<void> delete(
    String fileName, {
    DocumentRevision? expectedRevision,
  }) async {
    validateFileIdentifier(fileName);
    final file = await containedFile(directory, [fileName]);
    await _store(file).delete(expectedRevision: expectedRevision);
  }
}
