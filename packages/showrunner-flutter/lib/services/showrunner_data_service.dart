import 'dart:convert';
import '../schema/identifiers.dart';
import '../persistence/plugin_settings_store.dart';
import '../persistence/document_codec.dart';
import 'dart:io';

import 'package:yaml/yaml.dart';

import '../persistence/filesystem/atomic_file.dart';
import '../persistence/filesystem/safe_path.dart';
import '../persistence/secret_settings_store.dart';
import '../schema/json.dart';

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
  const ShowRunnerDataService(this.userDirectory, {this.secretSettings});

  final Directory userDirectory;
  final SecretSettingsStore? secretSettings;

  SecretSettingsStore get secretSettingsStore =>
      secretSettings ??
      SecretSettingsStore(
        directory: Directory('${userDirectory.path}/secrets'),
      );

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

  PluginSettingsStore get pluginSettingsStore => FilePluginSettingsStore(
    directory: settingsDirectory,
    secrets: secretSettingsStore,
  );

  Future<JsonMap> loadPluginSettings(String pluginId) =>
      pluginSettingsStore.load(PluginId(pluginId));

  Future<bool> pluginSettingsExist(String pluginId) =>
      pluginSettingsStore.exists(PluginId(pluginId));

  Future<void> savePluginSettings(String pluginId, JsonMap settings) =>
      pluginSettingsStore.save(PluginId(pluginId), settings);

  Future<void> updatePluginSetting(
    String pluginId,
    String settingId,
    dynamic value,
  ) => updatePluginSettings(pluginId, {settingId: value});

  Future<void> updatePluginSettings(String pluginId, JsonMap patch) {
    final snapshot = jsonDecode(jsonEncode(patch)) as JsonMap;
    return transformPluginSettings(
      pluginId,
      (settings) => {...settings, ...snapshot},
    );
  }

  Future<void> transformPluginSettings(
    String pluginId,
    JsonMap Function(JsonMap settings) transform,
  ) => pluginSettingsStore.transform(PluginId(pluginId), transform);

  Future<Map<String, JsonMap>> loadResourceConfigs(
    String resourceDirectory,
  ) async {
    final directory = safeRelativeDirectory(userDirectory, resourceDirectory);
    if (!await directory.exists()) return <String, JsonMap>{};
    final resources = <String, JsonMap>{};
    await for (final entity in directory.list()) {
      if (entity is! File || !entity.path.endsWith('.yaml')) continue;
      final id = entity.uri.pathSegments.last.replaceFirst(
        RegExp(r'\.yaml$'),
        '',
      );
      final safeFile = await containedFile(userDirectory, [
        ...resourceDirectory.split('/'),
        entity.uri.pathSegments.last,
      ]);
      final parsed = loadYaml(await safeFile.readAsString());
      if (parsed is YamlMap) resources[id] = _toMap(parsed);
    }
    return resources;
  }

  Future<void> saveResourceConfig(
    String resourceDirectory,
    String resourceId,
    JsonMap config,
  ) async {
    safeRelativeDirectory(userDirectory, resourceDirectory);
    validateFileIdentifier(resourceId);
    final file = await containedFile(userDirectory, [
      ...resourceDirectory.split('/'),
      '$resourceId.yaml',
    ]);
    await writeAtomicText(file, encodeYaml(config));
  }

  Future<List<String>> listUserFiles(String relativeDirectory) async {
    final directory = safeRelativeDirectory(userDirectory, relativeDirectory);
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
