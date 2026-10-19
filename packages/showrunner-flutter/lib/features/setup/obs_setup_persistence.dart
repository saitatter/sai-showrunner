import 'dart:io';

import '../../plugins/obs/transport.dart';
import '../../persistence/resource_repository.dart';
import '../../persistence/secret_settings_store.dart';
import '../../schema/resource.dart';

final class ObsSetupPersistence {
  const ObsSetupPersistence();

  Future<ResourceData?> loadSelected({
    required Directory directory,
    required Map<String, dynamic> settings,
  }) async {
    final selectedId = settings['obsDefault']?.toString();
    if (selectedId == null || selectedId.isEmpty) return null;
    return _repository(directory).load(selectedId);
  }

  Future<String> save({
    required Directory directory,
    required String? resourceId,
    required String host,
    required int port,
    required String password,
  }) async {
    final repository = _repository(directory);
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

  ResourceRepository _repository(Directory directory) => ResourceRepository(
    directory,
    resourceType: 'OBSConnection',
    secretSettings: SecretSettingsStore(
      directory: Directory('${directory.parent.parent.path}/secrets'),
    ),
  );
}

bool isLocalHost(String host) {
  final normalized = host.trim().toLowerCase();
  return normalized == 'localhost' ||
      normalized == '127.0.0.1' ||
      normalized == '::1';
}

typedef ObsSetupProbe =
    Future<void> Function(String host, int port, String? password);

/// Performs the same authenticated OBS WebSocket handshake used by runtime
/// actions, but keeps setup UI independent from network implementation.
final class ObsSetupConnectionTester {
  const ObsSetupConnectionTester({this.probe});

  final ObsSetupProbe? probe;

  Future<void> verify({
    required String host,
    required int port,
    String? password,
  }) => (probe ?? _probe)(host, port, password);

  Future<void> _probe(String host, int port, String? password) async {
    final transport = ObsWebSocketTransport(
      host: host,
      port: port,
      password: password?.isEmpty == true ? null : password,
    );
    try {
      await transport.call('GetVersion', const <String, dynamic>{});
    } finally {
      await transport.close();
    }
  }
}
