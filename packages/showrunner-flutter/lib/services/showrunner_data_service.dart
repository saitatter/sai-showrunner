import '../persistence/project_storage.dart';
import '../persistence/filesystem/persistence_directory.dart';
import 'dart:convert';
import '../schema/identifiers.dart';
import '../persistence/plugin_settings_store.dart';
import 'dart:io';

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
        location: PersistenceDirectory(userDirectory, ['secrets']),
      );

  Directory get settingsDirectory =>
      Directory('${userDirectory.path}/settings');
  Directory get stateDirectory => Directory('${userDirectory.path}/state');

  Future<ShowRunnerHealth> health() async {
    final settingsRoot = await PersistenceDirectory(userDirectory, [
      'settings',
    ]).resolve();
    final stateRoot = await PersistenceDirectory(userDirectory, [
      'state',
    ]).resolve();
    final settingsExists = await settingsRoot.exists();
    final settingsFiles = settingsExists
        ? await settingsRoot
              .list()
              .where(
                (entity) => entity is File && entity.path.endsWith('.yaml'),
              )
              .length
        : 0;
    return ShowRunnerHealth(
      userDirectoryExists: await userDirectory.exists(),
      settingsDirectoryExists: settingsExists,
      stateDirectoryExists: await stateRoot.exists(),
      settingsFileCount: settingsFiles,
    );
  }

  PluginSettingsStore get pluginSettingsStore => FilePluginSettingsStore(
    directory: settingsDirectory,
    secrets: secretSettingsStore,
    location: PersistenceDirectory(userDirectory, ['settings']),
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

  ProjectStorage get storage =>
      ProjectStorage(userDirectory, secrets: secretSettingsStore);

  Future<List<String>> listUserFiles(String relativeDirectory) =>
      storage.listFiles(relativeDirectory);
}
