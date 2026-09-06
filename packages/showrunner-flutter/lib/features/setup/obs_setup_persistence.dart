import 'dart:io';

import '../../persistence/resource_repository.dart';
import '../../schema/resource.dart';

final class ObsSetupPersistence {
  const ObsSetupPersistence();

  Future<ResourceData?> loadSelected({
    required Directory directory,
    required Map<String, dynamic> settings,
  }) async {
    final selectedId = settings['obsDefault']?.toString();
    if (selectedId == null || selectedId.isEmpty) return null;
    return ResourceRepository(directory).load(selectedId);
  }

  Future<String> save({
    required Directory directory,
    required String? resourceId,
    required String host,
    required int port,
    required String password,
  }) async {
    final repository = ResourceRepository(directory);
    final id = resourceId == null || resourceId.isEmpty
        ? 'obs-main-${DateTime.now().microsecondsSinceEpoch}'
        : resourceId;
    final existing = await repository.load(id);
    await repository.save(
      ResourceData(
        id: id,
        config: {
          ...?existing?.config,
          'name': existing?.config['name'] ?? 'Main OBS',
          'host': host,
          'port': port,
          'password': password,
          'local': isLocalHost(host),
        },
        state: existing?.state ?? const {},
      ),
    );
    return id;
  }
}

bool isLocalHost(String host) {
  final normalized = host.trim().toLowerCase();
  return normalized == 'localhost' ||
      normalized == '127.0.0.1' ||
      normalized == '::1';
}
