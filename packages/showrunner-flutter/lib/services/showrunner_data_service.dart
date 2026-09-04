import 'dart:io';

import 'package:yaml/yaml.dart';

import '../schema/automation.dart';

final class ShowRunnerHealth {
  const ShowRunnerHealth({
    required this.userDirectoryExists,
    required this.settingsDirectoryExists,
    required this.stateDirectoryExists,
    required this.settingsFileCount,
  });

  final bool userDirectoryExists;
  final bool settingsDirectoryExists;
  final bool stateDirectoryExists;
  final int settingsFileCount;

  bool get isReady =>
      userDirectoryExists && settingsDirectoryExists && stateDirectoryExists;
}

final class ShowRunnerDataService {
  const ShowRunnerDataService(this.userDirectory);

  final Directory userDirectory;

  Directory get settingsDirectory =>
      Directory('${userDirectory.path}/settings');
  Directory get stateDirectory => Directory('${userDirectory.path}/state');

  Future<ShowRunnerHealth> health() async {
    final settingsExists = await settingsDirectory.exists();
    final settingsFiles = settingsExists
        ? await settingsDirectory
              .list()
              .where(
                (entity) => entity is File && entity.path.endsWith('.yaml'),
              )
              .length
        : 0;
    return ShowRunnerHealth(
      userDirectoryExists: await userDirectory.exists(),
      settingsDirectoryExists: settingsExists,
      stateDirectoryExists: await stateDirectory.exists(),
      settingsFileCount: settingsFiles,
    );
  }

  Future<JsonMap> loadPluginSettings(String pluginId) async {
    final file = File('${settingsDirectory.path}/$pluginId.yaml');
    if (!await file.exists()) return <String, dynamic>{};
    final parsed = loadYaml(await file.readAsString());
    if (parsed is! YamlMap) return <String, dynamic>{};
    return _toMap(parsed);
  }

  Future<void> savePluginSettings(String pluginId, JsonMap settings) async {
    await settingsDirectory.create(recursive: true);
    final file = File('${settingsDirectory.path}/$pluginId.yaml');
    final temporaryFile = File('${file.path}.tmp');
    await temporaryFile.writeAsString(_yamlEncode(settings));
    await temporaryFile.rename(file.path);
  }

  Future<void> updatePluginSetting(
    String pluginId,
    String settingId,
    dynamic value,
  ) async {
    final settings = await loadPluginSettings(pluginId);
    settings[settingId] = value;
    await savePluginSettings(pluginId, settings);
  }

  Future<Map<String, JsonMap>> loadResourceConfigs(
    String resourceDirectory,
  ) async {
    final directory = Directory('${userDirectory.path}/$resourceDirectory');
    if (!await directory.exists()) return <String, JsonMap>{};
    final resources = <String, JsonMap>{};
    await for (final entity in directory.list()) {
      if (entity is! File || !entity.path.endsWith('.yaml')) continue;
      final id = entity.uri.pathSegments.last.replaceFirst(
        RegExp(r'\.yaml$'),
        '',
      );
      final parsed = loadYaml(await entity.readAsString());
      if (parsed is YamlMap) resources[id] = _toMap(parsed);
    }
    return resources;
  }

  Future<void> saveResourceConfig(
    String resourceDirectory,
    String resourceId,
    JsonMap config,
  ) async {
    final directory = Directory('${userDirectory.path}/$resourceDirectory');
    await directory.create(recursive: true);
    final file = File('${directory.path}/$resourceId.yaml');
    final temporaryFile = File('${file.path}.tmp');
    await temporaryFile.writeAsString(_yamlEncode(config));
    await temporaryFile.rename(file.path);
  }

  Future<List<String>> listUserFiles(String relativeDirectory) async {
    final directory = Directory('${userDirectory.path}/$relativeDirectory');
    if (!await directory.exists()) return <String>[];
    final files = <String>[];
    await for (final entity in directory.list()) {
      if (entity is File) files.add(entity.uri.pathSegments.last);
    }
    files.sort();
    return files;
  }
}

JsonMap _toMap(YamlMap value) => {
  for (final entry in value.entries) entry.key.toString(): _toDart(entry.value),
};

dynamic _toDart(dynamic value) {
  if (value is YamlMap) return _toMap(value);
  if (value is YamlList) return value.map(_toDart).toList();
  return value;
}

String _yamlEncode(JsonMap value) {
  final lines = <String>[];
  _appendYamlMap(lines, value, 0);
  return '${lines.join('\n')}\n';
}

void _appendYamlMap(List<String> lines, JsonMap value, int indentation) {
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
    } else if (item is List) {
      lines.add('$prefix-');
      _appendYamlList(lines, item, indentation + 2);
    } else {
      lines.add('$prefix- ${_yamlScalar(item)}');
    }
  }
}

String _yamlScalar(dynamic value) {
  if (value == null) return 'null';
  if (value is bool || value is num) return value.toString();
  if (value is String) {
    final escaped = value.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
    return '"$escaped"';
  }
  return '"${value.toString()}"';
}
