import 'document_codec.dart';
import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

import 'filesystem/file_transaction.dart';
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
    this.fileOperations = const TransactionFileOperations(),
  });

  final Directory directory;
  final String? resourceType;
  final SecretSettingsStore? secretSettings;
  final TransactionFileOperations fileOperations;

  FileTransaction _transaction(String id) => FileTransaction(
    directory: directory,
    id: id,
    operations: fileOperations,
    targets: {
      'json': () => containedFile(directory, ['$id.json']),
      'yaml': () => containedFile(directory, ['$id.yaml']),
      'state': () => containedFile(directory, ['.state', '$id.json']),
      if (resourceType != null && secretSettings != null)
        'secrets': () => secretSettings!.resourceStorageFile(resourceType!, id),
    },
  );

  Future<List<ResourceData>> list() async => (await listWithErrors())
      .where((entry) => entry.isValid)
      .map((entry) => entry.resource!)
      .toList();

  Future<List<ResourceCatalogEntry>> listWithErrors() async {
    if (!await directory.exists()) return const [];
    final names = <String, String>{};
    await for (final entity in directory.list(followLinks: false)) {
      final name = entity.uri.pathSegments.last;
      if (entity is! File && entity is! Link) continue;
      if (!name.endsWith('.json') && !name.endsWith('.yaml')) continue;
      final id = name.replaceFirst(RegExp(r'\.(json|yaml)$'), '');
      if (!names.containsKey(id) || name.endsWith('.json')) names[id] = name;
    }
    final pending = (await containedFile(directory, [
      '.transactions',
      '.scan',
    ])).parent;
    if (await pending.exists()) {
      await for (final entity in pending.list(followLinks: false)) {
        final name = entity.uri.pathSegments.last;
        if (name.endsWith('.json')) {
          final id = name.substring(0, name.length - 5);
          names.putIfAbsent(id, () => '$id.json');
        }
      }
    }
    final resources = <ResourceCatalogEntry>[];
    for (final entry in names.entries) {
      try {
        final resource = await load(entry.key);
        if (resource != null) {
          resources.add(
            ResourceCatalogEntry(fileName: entry.value, resource: resource),
          );
        }
      } catch (error, stackTrace) {
        resources.add(
          ResourceCatalogEntry(fileName: entry.value, error: error),
        );
        ShowRunnerLogger.instance.error(
          'persistence',
          'Could not read resource ${entry.value}',
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
    if (!await directory.exists()) return null;
    final transaction = _transaction(id);
    return transaction.locked(() async {
      await transaction.recover();
      return _loadUnlocked(id);
    });
  }

  Future<ResourceData?> _loadUnlocked(String id) async {
    final jsonFile = await containedFile(directory, ['$id.json']);
    if (await jsonFile.exists()) return _read(jsonFile);
    final yamlFile = await containedFile(directory, ['$id.yaml']);
    if (await yamlFile.exists()) return _read(yamlFile);
    return null;
  }

  Future<void> save(ResourceData resource) {
    validateFileIdentifier(resource.id);
    // Freeze accepted input before the first asynchronous filesystem operation.
    final ResourceData snapshot;
    try {
      snapshot = ResourceData.fromJson(
        jsonDecode(jsonEncode(resource.toJson())) as _JsonMap,
      );
    } catch (_) {
      throw const FormatException('Resource values must be JSON serializable.');
    }
    final transaction = _transaction(resource.id);
    return transaction.locked(() async {
      await transaction.recover();
      await _save(snapshot, transaction);
    });
  }

  Future<void> _save(ResourceData resource, FileTransaction transaction) async {
    // Reject unsupported existing bytes before staging any replacement.
    await _loadUnlocked(resource.id);
    final mutations = <FileMutation>[];
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
        final encrypted = await secretSettings!.sealValues({
          ...existing,
          ...secrets,
        }, owner: '$resourceType/${resource.id}');
        mutations.add(FileMutation.write('secrets', encrypted));
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
      if (resource.state.isNotEmpty) {
        mutations.add(
          FileMutation.write('state', utf8.encode(jsonEncode(resource.state))),
        );
      } else {
        mutations.add(const FileMutation.remove('state'));
      }
      mutations.add(
        FileMutation.write('yaml', utf8.encode(encodeYaml(publicConfig))),
      );
    } else {
      const encoder = JsonEncoder.withIndent('  ');
      mutations.add(
        FileMutation.write(
          'json',
          utf8.encode(encoder.convert(publicResource.toJson())),
        ),
      );
    }
    await transaction.commit(mutations);
  }

  Future<void> delete(String id) {
    validateFileIdentifier(id);
    final transaction = _transaction(id);
    return transaction.locked(() async {
      await transaction.recover();
      await transaction.commit([
        for (final key in transaction.targets.keys) FileMutation.remove(key),
      ]);
    });
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
