import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

import '../schema/profile.dart';

final class ProfileRepository {
  const ProfileRepository(this.file);

  final File file;

  Future<ShowRunnerProfile?> load() async {
    if (!await file.exists()) return null;
    final contents = await file.readAsString();
    final parsed = _yamlToDart(loadYaml(contents));
    if (parsed is! Map) {
      throw const FormatException('Profile must contain an object.');
    }
    return ShowRunnerProfile.fromJson(Map<String, dynamic>.from(parsed));
  }

  Future<void> save(ShowRunnerProfile profile) async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      const JsonEncoder.withIndent('  ').convert(profile.toJson()),
    );
    await temporary.rename(file.path);
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
