import '../schema/resource_codec.dart';
import 'viewer_data_repository.dart';
import 'dart:io';
import '../plugins/registry/builtin_resource_specs.dart';
import '../plugins/registry/plugin_contract.dart';
import 'automation_repository.dart';
import 'profile_repository.dart';
import 'queue_config_repository.dart';
import 'resource_repository.dart';
import 'secret_settings_store.dart';
import 'filesystem/persistence_directory.dart';
import 'filesystem/safe_path.dart';

/// Typed repository composition; paths remain rooted in this app's storage.
final class ProjectStorage {
  const ProjectStorage(this.directory, {required this.secrets});
  final Directory directory;
  final SecretSettingsStore secrets;

  PersistenceDirectory location(String relative) =>
      PersistenceDirectory(directory, relative.split('/'));
  PersistenceDirectory get automations => location('automations');
  PersistenceDirectory get profiles => location('profiles');
  PersistenceDirectory get queues => location('queues');

  ResourceRepository resource(
    ResourceTypeId type, {
    DartResourceContract? contract,
  }) {
    final definition = contract ?? builtInResourceSpec(type.value);
    if (definition.resourceTypeId != type) {
      throw ArgumentError('Resource contract identity mismatch.');
    }
    final owned = location(definition.storageDirectory);
    return ResourceRepository(
      owned.directory,
      location: owned,
      resourceType: type.value,
      codec: ResourceDataCodec(definition.configurationCodec),
      secretSettings: secrets,
    );
  }

  AutomationRepository automation(String fileName) {
    validateFileIdentifier(fileName);
    return AutomationRepository(
      File('${automations.directory.path}/$fileName'),
      location: automations,
    );
  }

  ProfileRepository profile(String fileName) {
    validateFileIdentifier(fileName);
    return ProfileRepository(
      File('${profiles.directory.path}/$fileName'),
      location: profiles,
    );
  }

  FileViewerDataRepository get viewerData {
    final owned = location('viewer-data');
    return FileViewerDataRepository(owned.directory, location: owned);
  }

  QueueConfigRepository get queueConfigs =>
      QueueConfigRepository(queues.directory, location: queues);
  Future<List<AutomationCatalogEntry>> listAutomations() =>
      AutomationRepository.loadDirectory(
        automations.directory,
        location: automations,
      );
  Future<List<ProfileCatalogEntry>> listProfiles() =>
      ProfileRepository.loadDirectory(profiles.directory, location: profiles);

  Future<List<String>> listFiles(String relative) async {
    final owned = await location(relative).resolve();
    if (!await owned.exists()) return [];
    final names = <String>[];
    await for (final entry in owned.list(followLinks: false)) {
      if (entry is! File) continue;
      // Check every returned path against the application root.
      await location(relative).file([entry.uri.pathSegments.last]);
      names.add(entry.uri.pathSegments.last);
    }
    return names..sort();
  }
}
