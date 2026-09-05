import 'dart:io';

import 'package:yaml/yaml.dart';

import 'filesystem/atomic_file.dart';
import '../schema/automation.dart';
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
    final parsed = _yamlToDart(loadYaml(await file.readAsString()));
    if (parsed is! Map) {
      throw const FormatException('Queue config must contain an object.');
    }
    return QueueConfig.fromJson(Map<String, dynamic>.from(parsed));
  }

  Future<void> save(String fileName, QueueConfig config) async {
    final file = File('${directory.path}/$fileName');
    await writeAtomicText(file, _yamlEncode(config.toJson()));
  }

  Future<void> delete(String fileName) async {
    final file = File('${directory.path}/$fileName');
    if (await file.exists()) await file.delete();
  }
}

dynamic _yamlToDart(dynamic value) {
  if (value is YamlMap) {
    return <String, dynamic>{
      for (final entry in value.entries)
        entry.key.toString(): _yamlToDart(entry.value),
    };
  }
  if (value is YamlList) return value.map(_yamlToDart).toList();
  return value;
}

String _yamlEncode(JsonMap value) =>
    '${value.entries.map((entry) => '${entry.key}: ${_yamlScalar(entry.value)}').join('\n')}\n';

String _yamlScalar(dynamic value) {
  if (value == null) return 'null';
  if (value is bool || value is num) return value.toString();
  final text = value.toString().replaceAll('\\', '\\\\').replaceAll('"', '\\"');
  return '"$text"';
}
