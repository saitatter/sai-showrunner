import 'dart:io';

import '../persistence/automation_repository.dart';
import '../persistence/profile_repository.dart';

/// The persisted resources that have first-class entries in the reference
/// ProjectView. The UI consumes this snapshot and never reads the filesystem
/// directly.
final class ShowRunnerProjectCatalog {
  const ShowRunnerProjectCatalog({
    required this.automations,
    required this.profiles,
  });

  final List<AutomationCatalogEntry> automations;
  final List<ProfileCatalogEntry> profiles;
}

final class ShowRunnerProjectCatalogService {
  const ShowRunnerProjectCatalogService(this.userDirectory);

  final Directory userDirectory;

  Future<ShowRunnerProjectCatalog> load() async {
    final results = await Future.wait<Object>([
      AutomationRepository.loadDirectory(
        Directory('${userDirectory.path}/automations'),
      ),
      ProfileRepository.loadDirectory(
        Directory('${userDirectory.path}/profiles'),
      ),
    ]);
    return ShowRunnerProjectCatalog(
      automations: results[0] as List<AutomationCatalogEntry>,
      profiles: results[1] as List<ProfileCatalogEntry>,
    );
  }
}
