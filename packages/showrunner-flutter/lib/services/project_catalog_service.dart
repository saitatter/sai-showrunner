import 'dart:io';
import 'package:path/path.dart' as p;
import '../plugins/registry/builtin_resource_specs.dart';
import '../persistence/project_storage.dart';
import '../persistence/persistence_issue.dart';
import '../persistence/filesystem/persistence_directory.dart';

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
    this.issues = const [],
  });

  final List<PersistenceIssue> issues;
  final List<AutomationCatalogEntry> automations;
  final List<ProfileCatalogEntry> profiles;
  final Map<String, List<ProjectResourceCatalogEntry>> resources;
}

final class ProjectResourceCatalogEntry {
  const ProjectResourceCatalogEntry({
    required this.resourceType,
    required this.resource,
    this.error,
  });

  final String resourceType;
  final ResourceData resource;
  final Object? error;

  String get title =>
      error == null ? resource.name : '${resource.name} (unreadable)';
}

final class ShowRunnerProjectCatalogService {
  const ShowRunnerProjectCatalogService(
    this.userDirectory, {
    this.secretSettings,
  });
  final Directory userDirectory;
  final SecretSettingsStore? secretSettings;
  String get _scope => Platform.isWindows
      ? p.normalize(userDirectory.absolute.path).toLowerCase()
      : p.normalize(userDirectory.absolute.path);
  @override
  bool operator ==(Object other) =>
      other is ShowRunnerProjectCatalogService &&
      _scope == other._scope &&
      identical(secretSettings, other.secretSettings);
  @override
  int get hashCode => Object.hash(_scope, secretSettings);

  ProjectStorage get _storage => ProjectStorage(
    userDirectory,
    secrets:
        secretSettings ??
        SecretSettingsStore(
          directory: Directory('${userDirectory.path}/secrets'),
          location: PersistenceDirectory(userDirectory, ['secrets']),
        ),
  );

  /// The panel owns this subscription and its cache invalidation timer.
  Stream<FileSystemEvent> watchChanges() {
    if (!userDirectory.existsSync()) return const Stream.empty();
    final scopes = [
      'automations',
      'profiles',
      for (final spec in builtInResourceSpecs) spec.storageDirectory,
    ];
    bool relevant(String path) {
      final relative = p
          .relative(path, from: userDirectory.path)
          .replaceAll('\\', '/');
      final segments = relative.split('/');
      if (segments.any(
        (part) => const {'.locks', '.transactions', '.state'}.contains(part),
      )) {
        return false;
      }
      if (!relative.endsWith('.yaml') && !relative.endsWith('.json')) {
        return false;
      }
      return scopes.any((scope) => relative.startsWith('$scope/'));
    }

    return userDirectory
        .watch(recursive: true)
        .where(
          (event) =>
              relevant(event.path) ||
              event is FileSystemMoveEvent &&
                  event.destination != null &&
                  relevant(event.destination!),
        );
  }

  Future<ShowRunnerProjectCatalog> load() async {
    final storage = _storage;
    final issues = <PersistenceIssue>[];
    Future<List<T>> query<T>(
      String owner,
      String path,
      Future<List<T>> Function() read,
    ) async {
      try {
        return await read();
      } catch (error) {
        issues.add(
          PersistenceIssue.fromError(error, owner: owner, document: path),
        );
        return [];
      }
    }

    final specs = builtInResourceSpecs.toList(growable: false);
    final results = await Future.wait<Object>([
      query('automations', 'automations', storage.listAutomations),
      query('profiles', 'profiles', storage.listProfiles),
      for (final spec in specs)
        query(
          spec.resourceTypeId.value,
          spec.storageDirectory,
          storage.resource(spec.resourceTypeId).listWithErrors,
        ),
    ]);
    final resources = <String, List<ProjectResourceCatalogEntry>>{};
    for (var index = 0; index < specs.length; index++) {
      final type = specs[index].resourceTypeId.value;
      final entries = results[index + 2] as List<ResourceCatalogEntry>;
      resources[type] = [
        for (final entry in entries)
          ProjectResourceCatalogEntry(
            resourceType: type,
            resource:
                entry.resource ??
                ResourceData(
                  id: entry.fileName.replaceFirst(
                    RegExp(r'\.(yaml|json)$'),
                    '',
                  ),
                  config: {'name': entry.fileName},
                ),
            error: entry.error,
          ),
      ]..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    }
    issues.sort((a, b) => a.toString().compareTo(b.toString()));
    return ShowRunnerProjectCatalog(
      automations: results[0] as List<AutomationCatalogEntry>,
      profiles: results[1] as List<ProfileCatalogEntry>,
      resources: resources,
      issues: List.unmodifiable(issues),
    );
  }
}
