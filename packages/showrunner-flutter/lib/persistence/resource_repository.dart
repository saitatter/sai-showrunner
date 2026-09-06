import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

import 'filesystem/atomic_file.dart';
import 'migrations/legacy_import_service.dart';
import '../schema/resource.dart';
import 'secret_settings_store.dart';

typedef _JsonMap = Map<String, dynamic>;

class ResourceRepository {
  const ResourceRepository(
    this.directory, {
    this.resourceType,
    this.secretSettings,
  });

  final Directory directory;
  final String? resourceType;
  final SecretSettingsStore? secretSettings;

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
    final secretFields = secretResourceFieldIdsFor(resourceType ?? '');
    final publicConfig = <String, dynamic>{
      for (final entry in resource.config.entries)
        if (!secretFields.contains(entry.key)) entry.key: entry.value,
    };
    if (secretFields.isNotEmpty && secretSettings != null) {
      final existing = await _loadSecretResource(resource.id);
      final secrets = <String, dynamic>{
        for (final key in secretFields)
          if (resource.config.containsKey(key)) key: resource.config[key],
      };
      if (secrets.isNotEmpty) {
        await secretSettings!.saveResource(resourceType!, resource.id, {
          ...existing,
          ...secrets,
        });
      }
    }
    final publicResource = ResourceData(
      id: resource.id,
      config: publicConfig,
      state: resource.state,
    );
    final jsonFile = File('${directory.path}/${resource.id}.json');
    final yamlFile = File('${directory.path}/${resource.id}.yaml');
    if (!await jsonFile.exists() && await yamlFile.exists()) {
      await writeAtomicText(yamlFile, _encodeYaml(publicConfig));
      return;
    }
    const encoder = JsonEncoder.withIndent('  ');
    await writeAtomicText(jsonFile, encoder.convert(publicResource.toJson()));
  }

  Future<void> delete(String id) async {
    if (resourceType != null && secretSettings != null) {
      await secretSettings!.deleteResource(resourceType!, id);
    }
    for (final file in [
      File('${directory.path}/$id.json'),
      File('${directory.path}/$id.yaml'),
    ]) {
      if (await file.exists()) await file.delete();
    }
  }

  Future<ResourceData> _read(File file) async {
    final content = await file.readAsString();
    ResourceData resource;
    if (file.path.endsWith('.json')) {
      final decoded = jsonDecode(content);
      if (decoded is! Map) {
        throw const FormatException('Resource JSON must contain an object.');
      }
      resource = await _normalizeResource(
        file,
        ResourceData.fromJson(Map<String, dynamic>.from(decoded)),
      );
    } else {
      final parsed = loadYaml(content);
      if (parsed is! YamlMap) {
        throw const FormatException('Resource YAML must contain a map.');
      }
      final id = file.uri.pathSegments.last.replaceFirst(
        RegExp(r'\.yaml$'),
        '',
      );
      resource = await _normalizeResource(
        file,
        ResourceData(id: id, config: _yamlMap(parsed)),
      );
    }
    return _withSecretResourceConfig(resource);
  }

  Future<ResourceData> _withSecretResourceConfig(ResourceData resource) async {
    if (resourceType == null || secretSettings == null) return resource;
    final secretFields = secretResourceFieldIdsFor(resourceType!);
    if (secretFields.isEmpty) return resource;
    _JsonMap secrets;
    try {
      secrets = await _loadSecretResource(resource.id);
    } on Object {
      secrets = <String, dynamic>{};
    }
    if (secrets.isEmpty) return resource;
    return ResourceData(
      id: resource.id,
      config: {...resource.config, ...secrets},
      state: resource.state,
    );
  }

  Future<_JsonMap> _loadSecretResource(String resourceId) async {
    final type = resourceType;
    if (type == null || secretSettings == null) {
      return <String, dynamic>{};
    }
    var secrets = await secretSettings!.loadResource(type, resourceId);
    if (secrets.isEmpty) {
      try {
        secrets = await secretSettings!.loadLegacyAccount(type, resourceId);
      } on Object {
        // A missing/incompatible legacy account must not hide public config.
      }
    }
    return secrets;
  }

  Future<ResourceData> _normalizeResource(
    File file,
    ResourceData resource,
  ) async {
    final config = resource.config;
    if (!config.containsKey('segments') ||
        !config.containsKey('activationAutomation')) {
      return resource;
    }
    final normalizedConfig = const LegacyImportService().normalizeStreamPlanMap(
      config,
    );
    if (jsonEncode(normalizedConfig) == jsonEncode(config)) {
      return resource;
    }

    // Inline stream-plan automations were persisted by the Electron runtime
    // in the same resource file. Keep the original recoverable before
    // replacing it with the canonical V2 representation.
    await backupOriginalFile(file);
    await writeAtomicText(
      file,
      file.path.endsWith('.yaml')
          ? _encodeYaml(normalizedConfig)
          : const JsonEncoder.withIndent('  ').convert(
              ResourceData(
                id: resource.id,
                config: normalizedConfig,
                state: resource.state,
              ).toJson(),
            ),
    );
    return ResourceData(
      id: resource.id,
      config: normalizedConfig,
      state: resource.state,
    );
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
