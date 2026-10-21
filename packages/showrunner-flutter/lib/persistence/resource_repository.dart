import 'document_codec.dart';
import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

import 'filesystem/atomic_file.dart';
import 'filesystem/safe_path.dart';
import '../services/structured_logger.dart';
import '../schema/resource.dart';
import 'secret_settings_store.dart';

typedef _JsonMap = Map<String, dynamic>;

final class ResourceCatalogEntry {
  const ResourceCatalogEntry({
    required this.fileName,
    this.resource,
    this.error,
  });
  final String fileName;
  final ResourceData? resource;
  final Object? error;
  bool get isValid => resource != null && error == null;
}

class ResourceRepository {
  const ResourceRepository(
    this.directory, {
    this.resourceType,
    this.secretSettings,
  });

  final Directory directory;
  final String? resourceType;
  final SecretSettingsStore? secretSettings;

  Future<List<ResourceData>> list() async => (await listWithErrors())
      .where((entry) => entry.isValid)
      .map((entry) => entry.resource!)
      .toList();

  Future<List<ResourceCatalogEntry>> listWithErrors() async {
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

    final resources = <ResourceCatalogEntry>[];
    for (final file in files) {
      try {
        resources.add(
          ResourceCatalogEntry(
            fileName: file.uri.pathSegments.last,
            resource: await _read(file),
          ),
        );
      } catch (error, stackTrace) {
        resources.add(
          ResourceCatalogEntry(
            fileName: file.uri.pathSegments.last,
            error: error,
          ),
        );
        ShowRunnerLogger.instance.error(
          'persistence',
          'Could not read resource ${file.path}',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
    resources.sort((left, right) => left.fileName.compareTo(right.fileName));
    return resources;
  }

  Future<ResourceData?> load(String id) async {
    validateFileIdentifier(id);
    final jsonFile = await containedFile(directory, ['$id.json']);
    if (await jsonFile.exists()) return _read(jsonFile);
    final yamlFile = await containedFile(directory, ['$id.yaml']);
    if (await yamlFile.exists()) return _read(yamlFile);
    return null;
  }

  Future<void> save(ResourceData resource) {
    validateFileIdentifier(resource.id);
    return withFileLock(
      '${directory.path}/${resource.id}.transaction',
      () => _save(resource),
    );
  }

  Future<void> _save(ResourceData resource) async {
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    // Revalidate existing bytes before any credential/state write. A corrupt
    // or unsupported file must never be overwritten by a stale editor save.
    await load(resource.id);
    final secretFields = secretResourceFieldIdsFor(resourceType ?? '');
    if (secretSettings == null &&
        secretFields.any(resource.config.containsKey)) {
      throw StateError(
        'Encrypted storage is required for declared resource secrets.',
      );
    }
    final publicConfig = <String, dynamic>{
      for (final entry in resource.config.entries)
        if (secretSettings == null || !secretFields.contains(entry.key))
          entry.key: entry.value,
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
    final jsonFile = await containedFile(directory, ['${resource.id}.json']);
    final yamlFile = await containedFile(directory, ['${resource.id}.yaml']);
    if (!await jsonFile.exists() && await yamlFile.exists()) {
      final stateFile = await containedFile(directory, [
        '.state',
        '${resource.id}.json',
      ]);
      if (resource.state.isNotEmpty) {
        await writeAtomicText(stateFile, jsonEncode(resource.state));
      } else if (await stateFile.exists()) {
        await stateFile.delete();
      }
      await writeAtomicText(yamlFile, encodeYaml(publicConfig));
      return;
    }
    const encoder = JsonEncoder.withIndent('  ');
    await writeAtomicText(jsonFile, encoder.convert(publicResource.toJson()));
  }

  Future<void> delete(String id) {
    validateFileIdentifier(id);
    return withFileLock('${directory.path}/$id.transaction', () => _delete(id));
  }

  Future<void> _delete(String id) async {
    if (resourceType != null && secretSettings != null) {
      await secretSettings!.deleteResource(resourceType!, id);
    }
    for (final file in [
      await containedFile(directory, ['$id.json']),
      await containedFile(directory, ['$id.yaml']),
      await containedFile(directory, ['.state', '$id.json']),
    ]) {
      if (await file.exists()) await file.delete();
    }
  }

  Future<ResourceData> _read(File file) async {
    file = await containedFile(directory, [file.uri.pathSegments.last]);
    final content = await file.readAsString();
    ResourceData resource;
    if (file.path.endsWith('.json')) {
      final decoded = jsonDecode(content);
      if (decoded is! Map) {
        throw const FormatException('Resource JSON must contain an object.');
      }
      resource = ResourceData.fromJson(Map<String, dynamic>.from(decoded));
      final fileId = file.uri.pathSegments.last.replaceFirst(
        RegExp(r'\.json$'),
        '',
      );
      if (resource.id != fileId) {
        throw const FormatException(
          'Resource identity does not match its filename.',
        );
      }
    } else {
      final parsed = loadYaml(content);
      if (parsed is! YamlMap) {
        throw const FormatException('Resource YAML must contain a map.');
      }
      final id = file.uri.pathSegments.last.replaceFirst(
        RegExp(r'\.yaml$'),
        '',
      );
      final stateFile = await containedFile(directory, ['.state', '$id.json']);
      final state = await stateFile.exists()
          ? jsonDecode(await stateFile.readAsString())
          : <String, dynamic>{};
      if (state is! Map) {
        throw const FormatException('Resource state must be an object.');
      }
      resource = ResourceData(
        id: id,
        config: _yamlMap(parsed),
        state: Map<String, dynamic>.from(state),
      );
    }
    return _withSecretResourceConfig(resource);
  }

  Future<ResourceData> _withSecretResourceConfig(ResourceData resource) async {
    if (resourceType == null || secretSettings == null) return resource;
    final secretFields = secretResourceFieldIdsFor(resourceType!);
    if (secretFields.isEmpty) return resource;
    final secrets = await _loadSecretResource(resource.id);
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
    return secretSettings!.loadResource(type, resourceId);
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
