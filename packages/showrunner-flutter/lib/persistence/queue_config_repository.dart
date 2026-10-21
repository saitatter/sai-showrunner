import 'document_codec.dart';
import 'dart:io';

import 'package:yaml/yaml.dart';

import 'filesystem/atomic_file.dart';
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
    final parsed = decodeYamlValue(loadYaml(await file.readAsString()));
    if (parsed is! Map) {
      throw const FormatException('Queue config must contain an object.');
    }
    return QueueConfig.fromJson(Map<String, dynamic>.from(parsed));
  }

  Future<void> save(String fileName, QueueConfig config) async {
    validateFileIdentifier(fileName);
    final file = await containedFile(directory, [fileName]);
    await writeAtomicText(file, encodeYaml(config.toJson()));
  }

  Future<void> delete(String fileName) async {
    validateFileIdentifier(fileName);
    final file = await containedFile(directory, [fileName]);
    if (await file.exists()) await file.delete();
  }
}
