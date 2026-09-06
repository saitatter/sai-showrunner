import 'dart:io';

import '../persistence/automation_repository.dart';
import '../persistence/profile_repository.dart';
import '../persistence/resource_repository.dart';
import '../persistence/secret_settings_store.dart';
import '../schema/resource.dart';

/// The persisted resources that have first-class entries in the reference
/// ProjectView. The UI consumes this snapshot and never reads the filesystem
/// directly.
final class ShowRunnerProjectCatalog {
  const ShowRunnerProjectCatalog({
    required this.automations,
    required this.profiles,
    required this.resources,
  });

  final List<AutomationCatalogEntry> automations;
  final List<ProfileCatalogEntry> profiles;
  final Map<String, List<ProjectResourceCatalogEntry>> resources;
}

final class ProjectResourceCatalogEntry {
  const ProjectResourceCatalogEntry({
    required this.resourceType,
    required this.resource,
  });

  final String resourceType;
  final ResourceData resource;

  String get title => resource.name;
}

final class ShowRunnerProjectCatalogService {
  const ShowRunnerProjectCatalogService(this.userDirectory);

  final Directory userDirectory;

  Future<ShowRunnerProjectCatalog> load() async {
    final resourceDirectories = _projectResourceDirectories.entries.toList(
      growable: false,
    );
    final secretSettings = SecretSettingsStore(
      directory: Directory('${userDirectory.path}/secrets'),
    );
    final results = await Future.wait<Object>([
      AutomationRepository.loadDirectory(
        Directory('${userDirectory.path}/automations'),
      ),
      ProfileRepository.loadDirectory(
        Directory('${userDirectory.path}/profiles'),
      ),
      for (final entry in resourceDirectories)
        ResourceRepository(
          Directory('${userDirectory.path}/${entry.value}'),
          resourceType: entry.key,
          secretSettings: secretSettings,
        ).list(),
    ]);
    final resources = <String, List<ProjectResourceCatalogEntry>>{};
    for (var index = 0; index < resourceDirectories.length; index++) {
      final resourceType = resourceDirectories[index].key;
      final entries =
          (results[index + 2] as List<ResourceData>)
              .map(
                (resource) => ProjectResourceCatalogEntry(
                  resourceType: resourceType,
                  resource: resource,
                ),
              )
              .toList()
            ..sort(
              (left, right) =>
                  left.title.toLowerCase().compareTo(right.title.toLowerCase()),
            );
      resources[resourceType] = entries;
    }
    return ShowRunnerProjectCatalog(
      automations: results[0] as List<AutomationCatalogEntry>,
      profiles: results[1] as List<ProfileCatalogEntry>,
      resources: resources,
    );
  }
}

const _projectResourceDirectories = <String, String>{
  'StreamPlan': 'stream-plans',
  'Overlay': 'overlays',
  'Dashboard': 'dashboards',
  'TTSVoice': 'sound/tts',
  'SoundOutput': 'sound/outputs',
  'AudioSplitterOutput': 'sound/splitters',
  'OBSConnection': 'obs/connections',
  'CustomTwitchViewerGroup': 'twitch/groups',
  'ChannelPointReward': 'twitch/channelpoints',
  'SpellHook': 'spellcast/spells',
  'TwitchAccount': 'accounts/twitch',
  'BlueSkyAccount': 'accounts/bluesky',
  'WyzeAccount': 'accounts/wyze',
};
