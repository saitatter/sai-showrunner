import 'dart:convert';
import 'dart:io';

import '../schema/resource.dart';

class ResourceRepository {
  const ResourceRepository(this.directory);

  final Directory directory;

  Future<List<ResourceData>> list() async {
    if (!await directory.exists()) return const [];
    final files = await directory
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.json'))
        .cast<File>()
        .toList();

    final resources = <ResourceData>[];
    for (final file in files) {
      try {
        final content = await file.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        resources.add(ResourceData.fromJson(json));
      } catch (_) {
        // Ignore unparseable or corrupted files gracefully
      }
    }
    return resources;
  }

  Future<ResourceData?> load(String id) async {
    final file = File('${directory.path}/$id.json');
    if (!await file.exists()) return null;
    final content = await file.readAsString();
    final json = jsonDecode(content) as Map<String, dynamic>;
    return ResourceData.fromJson(json);
  }

  Future<void> save(ResourceData resource) async {
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    final file = File('${directory.path}/${resource.id}.json');
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(encoder.convert(resource.toJson()));
  }

  Future<void> delete(String id) async {
    final file = File('${directory.path}/$id.json');
    if (await file.exists()) {
      await file.delete();
    }
  }
}
