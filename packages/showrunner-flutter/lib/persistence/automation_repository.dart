import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

import 'filesystem/atomic_file.dart';
import '../schema/automation.dart';

final class AutomationCatalogEntry {
  const AutomationCatalogEntry({
    required this.fileName,
    this.automation,
    this.error,
  });

  final String fileName;
  final AutomationData? automation;
  final Object? error;

  bool get isValid => automation != null && error == null;
}

final class AutomationRepository {
  const AutomationRepository(this.file);

  final File file;

  Future<AutomationData?> load() => loadStrict();

  /// Loads only the canonical V2 graph representation.
  Future<AutomationData?> loadStrict() async {
    if (!await file.exists()) return null;
    final contents = await file.readAsString();
    dynamic decoded;
    try {
      decoded = jsonDecode(contents);
    } on FormatException {
      decoded = _yamlToDart(loadYaml(contents));
    }
    if (decoded is! Map) {
      throw const FormatException(
        'Automation file must contain a JSON object.',
      );
    }
    final source = Map<String, dynamic>.from(decoded);
    return AutomationData.fromJson(source);
  }

  static Future<List<AutomationCatalogEntry>> loadDirectory(
    Directory directory,
  ) async {
    if (!await directory.exists()) return const <AutomationCatalogEntry>[];
    final entries = <AutomationCatalogEntry>[];
    await for (final entity in directory.list()) {
      if (entity is! File || !entity.path.endsWith('.yaml')) continue;
      final fileName = entity.uri.pathSegments.last;
      try {
        entries.add(
          AutomationCatalogEntry(
            fileName: fileName,
            automation: await AutomationRepository(entity).load(),
          ),
        );
      } catch (error) {
        entries.add(AutomationCatalogEntry(fileName: fileName, error: error));
      }
    }
    entries.sort((left, right) => left.fileName.compareTo(right.fileName));
    return entries;
  }

  Future<void> save(AutomationData automation) async {
    await writeAtomicText(
      file,
      const JsonEncoder.withIndent('  ').convert(automation.toJson()),
    );
  }

  Future<void> delete() async {
    if (await file.exists()) await file.delete();
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
