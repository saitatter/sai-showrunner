import 'document_revision.dart';
import 'filesystem/persistence_directory.dart';
import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

import '../schema/identifiers.dart';
import '../schema/json.dart';
import 'document_codec.dart';
import 'filesystem/file_transaction.dart';
import 'filesystem/safe_path.dart';
import 'secret_settings_store.dart';

abstract interface class PluginSettingsStore {
  Future<JsonMap> load(PluginId plugin);
  Future<bool> exists(PluginId plugin);
  Future<void> save(
    PluginId plugin,
    JsonMap values, {
    DocumentRevision? expectedRevision,
  });
  Future<void> transform(
    PluginId plugin,
    JsonMap Function(JsonMap) transform, {
    DocumentRevision? expectedRevision,
  });
}

/// Settings and sealed credentials share one durable generation and owner lock.
final class FilePluginSettingsStore implements PluginSettingsStore {
  const FilePluginSettingsStore({
    required this.directory,
    required this.secrets,
    this.location,
    this.operations = const TransactionFileOperations(),
  });

  final Directory directory;
  final PersistenceDirectory? location;
  final SecretSettingsStore secrets;
  final TransactionFileOperations operations;

  Future<File> _public(PluginId plugin) {
    validateFileIdentifier(plugin.value);
    return location?.file(['${plugin.value}.yaml']) ??
        containedFile(directory, ['${plugin.value}.yaml']);
  }

  FileTransaction _transaction(PluginId plugin) => FileTransaction(
    directory: directory,
    id: plugin.value,
    operations: operations,
    location: location,
    targets: {
      'public': () => _public(plugin),
      'secrets': () => secrets.settingsStorageFile(plugin.value),
    },
  );

  Future<JsonMap> _readPublic(PluginId plugin) async {
    final file = await _public(plugin);
    if (!await file.exists()) return {};
    final Object? parsed;
    try {
      parsed = loadYaml(await file.readAsString());
    } on YamlException {
      // Parser spans may include credentials accidentally pasted into YAML.
      throw const FormatException('Invalid plugin settings YAML.');
    }
    if (parsed is! YamlMap) {
      throw const FormatException('Plugin settings must contain a map.');
    }
    return decodeYamlValue(parsed) as JsonMap;
  }

  @override
  Future<JsonMap> load(PluginId plugin) async {
    final transaction = _transaction(plugin);
    return transaction.locked(() async {
      await transaction.recover();
      return _visible(
        plugin,
        await _readPublic(plugin),
        await secrets.load(plugin.value),
      );
    });
  }

  @override
  Future<bool> exists(PluginId plugin) async {
    final transaction = _transaction(plugin);
    return transaction.locked(() async {
      await transaction.recover();
      return (await _public(plugin)).exists();
    });
  }

  @override
  Future<void> save(
    PluginId plugin,
    JsonMap values, {
    DocumentRevision? expectedRevision,
  }) {
    final snapshot = _snapshot(values);
    final transaction = _transaction(plugin);
    return transaction.locked(() async {
      await transaction.recover();
      final public = await _readPublic(plugin);
      final sealed = await secrets.load(plugin.value);
      _verify(plugin, _visible(plugin, public, sealed), expectedRevision);
      await _save(plugin, snapshot, sealed, transaction);
    });
  }

  @override
  Future<void> transform(
    PluginId plugin,
    JsonMap Function(JsonMap) transform, {
    DocumentRevision? expectedRevision,
  }) {
    final transaction = _transaction(plugin);
    return transaction.locked(() async {
      await transaction.recover();
      final public = await _readPublic(plugin);
      final sealed = await secrets.load(plugin.value);
      _verify(plugin, _visible(plugin, public, sealed), expectedRevision);
      final values = _snapshot(transform(_visible(plugin, public, sealed)));
      await _save(plugin, values, sealed, transaction);
    });
  }

  JsonMap _visible(PluginId plugin, JsonMap public, JsonMap sealed) {
    final declared = secretSettingIdsFor(plugin.value);
    return {
      for (final entry in public.entries)
        if (!sealed.containsKey(entry.key)) entry.key: entry.value,
      for (final entry in sealed.entries)
        if (declared.contains(entry.key)) entry.key: entry.value,
    };
  }

  void _verify(PluginId plugin, JsonMap current, DocumentRevision? expected) {
    if (expected != null && DocumentRevision.of(current) != expected) {
      throw PersistenceConflictException('settings/${plugin.value}');
    }
  }

  Future<void> _save(
    PluginId plugin,
    JsonMap values,
    JsonMap existingSecrets,
    FileTransaction transaction,
  ) async {
    // Unknown encrypted fields retain their original confidentiality boundary.
    final keys = {
      ...secretSettingIdsFor(plugin.value),
      ...existingSecrets.keys,
    };
    final public = <String, dynamic>{
      for (final entry in values.entries)
        if (!keys.contains(entry.key)) entry.key: entry.value,
    };
    final sealed = <String, dynamic>{
      ...existingSecrets,
      for (final entry in values.entries)
        if (secretSettingIdsFor(plugin.value).contains(entry.key))
          entry.key: entry.value,
    };
    final mutations = <FileMutation>[
      if (sealed.isNotEmpty)
        FileMutation.write(
          'secrets',
          await secrets.sealValues(sealed, owner: plugin.value),
        ),
      FileMutation.write('public', utf8.encode(encodeYaml(public))),
    ];
    await transaction.commit(mutations);
  }
}

JsonMap _snapshot(JsonMap values) {
  try {
    return jsonDecode(jsonEncode(values)) as JsonMap;
  } catch (_) {
    throw const FormatException('Plugin settings must be JSON serializable.');
  }
}
