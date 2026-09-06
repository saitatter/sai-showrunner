import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

import 'filesystem/atomic_file.dart';
import '../schema/profile.dart';

final class ProfileCatalogEntry {
  const ProfileCatalogEntry({required this.fileName, this.profile, this.error});

  final String fileName;
  final ShowRunnerProfile? profile;
  final Object? error;

  bool get isValid => profile != null && error == null;
}

final class ProfileRepository {
  const ProfileRepository(this.file);

  final File file;

  static Future<List<ProfileCatalogEntry>> loadDirectory(
    Directory directory,
  ) async {
    if (!await directory.exists()) return const <ProfileCatalogEntry>[];
    final entries = <ProfileCatalogEntry>[];
    await for (final entity in directory.list()) {
      if (entity is! File || !entity.path.endsWith('.yaml')) continue;
      final fileName = entity.uri.pathSegments.last;
      try {
        entries.add(
          ProfileCatalogEntry(
            fileName: fileName,
            profile: await ProfileRepository(entity).load(),
          ),
        );
      } catch (error) {
        entries.add(ProfileCatalogEntry(fileName: fileName, error: error));
      }
    }
    entries.sort((left, right) {
      final leftName = left.profile?.name ?? left.fileName;
      final rightName = right.profile?.name ?? right.fileName;
      return leftName.toLowerCase().compareTo(rightName.toLowerCase());
    });
    return entries;
  }

  Future<ShowRunnerProfile?> load() async {
    if (!await file.exists()) return null;
    final contents = await file.readAsString();
    dynamic decoded;
    try {
      decoded = jsonDecode(contents);
    } on FormatException {
      decoded = _yamlToDart(loadYaml(contents));
    }
    if (decoded is! Map) {
      throw const FormatException('Profile file must contain a JSON object.');
    }
    final source = Map<String, dynamic>.from(decoded);
    return ShowRunnerProfile.fromJson(source);
  }

  Future<void> save(ShowRunnerProfile profile) async {
    await writeAtomicText(
      file,
      const JsonEncoder.withIndent('  ').convert(profile.toJson()),
    );
  }
}

dynamic _yamlToDart(dynamic value) {
  if (value is YamlMap) {
    return <String, dynamic>{
      for (final entry in value.entries)
        entry.key.toString(): _yamlToDart(entry.value),
    };
  }
  if (value is YamlList) return value.map(_yamlToDart).toList();
  return value;
}
