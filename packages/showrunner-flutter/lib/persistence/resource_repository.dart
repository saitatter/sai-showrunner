import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

import 'filesystem/atomic_file.dart';
import '../schema/resource.dart';

typedef _JsonMap = Map<String, dynamic>;

class ResourceRepository {
  const ResourceRepository(this.directory);

  final Directory directory;

  Future<List<ResourceData>> list() async {
    if (!await directory.exists()) return const [];
    final files = await directory
        .list()
        .where(
          (entity) =>
              entity is File &&
              (entity.path.endsWith('.json') || entity.path.endsWith('.yaml')),
        )
        .cast<File>()
        .toList();

    final resources = <ResourceData>[];
    for (final file in files) {
      try {
        resources.add(await _read(file));
      } catch (_) {
        // Ignore unparseable or corrupted files gracefully
      }
    }
    resources.sort((left, right) => left.id.compareTo(right.id));
    return resources;
  }

  Future<ResourceData?> load(String id) async {
    final jsonFile = File('${directory.path}/$id.json');
    if (await jsonFile.exists()) return _read(jsonFile);
    final yamlFile = File('${directory.path}/$id.yaml');
    if (await yamlFile.exists()) return _read(yamlFile);
    return null;
  }

  Future<void> save(ResourceData resource) async {
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    final jsonFile = File('${directory.path}/${resource.id}.json');
    final yamlFile = File('${directory.path}/${resource.id}.yaml');
    if (!await jsonFile.exists() && await yamlFile.exists()) {
      await writeAtomicText(yamlFile, _encodeYaml(resource.config));
      return;
    }
    const encoder = JsonEncoder.withIndent('  ');
    await writeAtomicText(jsonFile, encoder.convert(resource.toJson()));
  }

  Future<void> delete(String id) async {
    for (final file in [
      File('${directory.path}/$id.json'),
      File('${directory.path}/$id.yaml'),
    ]) {
      if (await file.exists()) await file.delete();
    }
  }

  Future<ResourceData> _read(File file) async {
    final content = await file.readAsString();
    if (file.path.endsWith('.json')) {
      final decoded = jsonDecode(content);
      if (decoded is! Map) {
        throw const FormatException('Resource JSON must contain an object.');
      }
      return ResourceData.fromJson(Map<String, dynamic>.from(decoded));
    }
    final parsed = loadYaml(content);
    if (parsed is! YamlMap) {
      throw const FormatException('Resource YAML must contain a map.');
    }
    final id = file.uri.pathSegments.last.replaceFirst(RegExp(r'\.yaml$'), '');
    return ResourceData(id: id, config: _yamlMap(parsed));
  }
}

_JsonMap _yamlMap(YamlMap value) => {
  for (final entry in value.entries)
    entry.key.toString(): _yamlValue(entry.value),
};

dynamic _yamlValue(dynamic value) {
  if (value is YamlMap) return _yamlMap(value);
  if (value is YamlList) return value.map(_yamlValue).toList();
  return value;
}

String _encodeYaml(_JsonMap value) {
  final lines = <String>[];
  _appendYamlMap(lines, value, 0);
  return '${lines.join('\n')}\n';
}

void _appendYamlMap(List<String> lines, _JsonMap value, int indentation) {
  final prefix = ' ' * indentation;
  for (final entry in value.entries) {
    final nested = entry.value;
    if (nested is Map) {
      final map = Map<String, dynamic>.from(nested);
      lines.add('$prefix${entry.key}:');
      if (map.isEmpty) {
        lines[lines.length - 1] += ' {}';
      } else {
        _appendYamlMap(lines, map, indentation + 2);
      }
    } else if (nested is List) {
      lines.add('$prefix${entry.key}:');
      if (nested.isEmpty) {
        lines[lines.length - 1] += ' []';
      } else {
        _appendYamlList(lines, nested, indentation + 2);
      }
    } else {
      lines.add('$prefix${entry.key}: ${_yamlScalar(nested)}');
    }
  }
}

void _appendYamlList(List<String> lines, List<dynamic> value, int indentation) {
  final prefix = ' ' * indentation;
  for (final item in value) {
    if (item is Map) {
      final map = Map<String, dynamic>.from(item);
      if (map.isEmpty) {
        lines.add('$prefix- {}');
      } else {
        final first = map.entries.first;
        lines.add('$prefix- ${first.key}: ${_yamlScalar(first.value)}');
        if (map.length > 1) {
          _appendYamlMap(
            lines,
            Map<String, dynamic>.fromEntries(map.entries.skip(1)),
            indentation + 2,
          );
        }
      }
    } else {
      lines.add('$prefix- ${_yamlScalar(item)}');
    }
  }
}

String _yamlScalar(dynamic value) {
  if (value == null) return 'null';
  if (value is bool || value is num) return value.toString();
  final text = value.toString().replaceAll('\\', '\\\\').replaceAll('"', '\\"');
  return '"$text"';
}
