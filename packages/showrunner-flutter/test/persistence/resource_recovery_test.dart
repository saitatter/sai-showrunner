import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/persistence/resource_repository.dart';
import 'package:showrunner_flutter/persistence/secret_settings_store.dart';
import 'package:showrunner_flutter/schema/resource.dart';

void main() {
  late Directory root;
  late Directory resources;
  late SecretSettingsStore secrets;
  setUp(() async {
    root = await Directory.systemTemp.createTemp(
      'showrunner-resource-recovery-',
    );
    resources = await Directory(
      '${root.path}/obs/connections',
    ).create(recursive: true);
    Future<List<int>> cipher(List<int> bytes) async =>
        bytes.map((byte) => byte ^ 0x5a).toList();
    secrets = SecretSettingsStore(
      directory: Directory('${root.path}/secrets'),
      encrypt: cipher,
      decrypt: cipher,
    );
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });

  test(
    'a failed state write cannot expose new credentials with old configuration',
    () async {
      final config = File('${resources.path}/studio.yaml');
      await config.writeAsString('name: Studio\nhost: old-host\n');
      await secrets.saveResource('OBSConnection', 'studio', {
        'password': 'old-password',
      });
      // The state directory cannot be created: the failure occurs after the old
      // implementation has already published replacement encrypted credentials.
      final blocker = File('${resources.path}/.state');
      await blocker.writeAsString('blocked state directory');
      final repository = ResourceRepository(
        resources,
        resourceType: 'OBSConnection',
        secretSettings: secrets,
      );
      await expectLater(
        repository.save(
          const ResourceData(
            id: 'studio',
            config: {
              'name': 'Studio',
              'host': 'new-host',
              'password': 'new-password',
            },
            state: {'generation': 1},
          ),
        ),
        throwsA(isA<FileSystemException>()),
      );
      await blocker.delete();
      final loaded = (await repository.load('studio'))!;
      expect(
        [
          [loaded.config['host'], loaded.config['password']],
        ],
        anyOf(
          equals([
            ['old-host', 'old-password'],
          ]),
          equals([
            ['new-host', 'new-password'],
          ]),
        ),
      );
      if (loaded.config['host'] == 'new-host') {
        expect(loaded.state, {'generation': 1});
      }
    },
  );
  test(
    'unavailable encrypted secrets are a visible failure, not empty credentials',
    () async {
      final repository = ResourceRepository(
        resources,
        resourceType: 'OBSConnection',
        secretSettings: secrets,
      );
      await repository.save(
        const ResourceData(
          id: 'studio',
          config: {'host': 'host', 'password': 'private-value'},
        ),
      );
      final broken = SecretSettingsStore(
        directory: secrets.directory,
        decrypt: (_) async => throw StateError('synthetic decryption failure'),
      );
      await expectLater(
        ResourceRepository(
          resources,
          resourceType: 'OBSConnection',
          secretSettings: broken,
        ).load('studio'),
        throwsA(isA<StateError>()),
      );
    },
  );
  test(
    'declared secrets require encrypted storage before any public write',
    () async {
      final repository = ResourceRepository(
        resources,
        resourceType: 'OBSConnection',
      );
      await expectLater(
        repository.save(
          const ResourceData(
            id: 'studio',
            config: {'password': 'private-value'},
          ),
        ),
        throwsA(isA<StateError>()),
      );
      expect(await File('${resources.path}/studio.json').exists(), false);
    },
  );
  test(
    'unsupported resource envelopes remain unchanged on load and save',
    () async {
      final file = File('${resources.path}/studio.json');
      final unsupported = jsonEncode({
        'schemaVersion': 999,
        'id': 'studio',
        'config': {'name': 'Future'},
      });
      await file.writeAsString(unsupported);
      final repository = ResourceRepository(resources);
      await expectLater(repository.load('studio'), throwsFormatException);
      await expectLater(
        repository.save(
          const ResourceData(id: 'studio', config: {'name': 'Replacement'}),
        ),
        throwsFormatException,
      );
      expect(await file.readAsString(), unsupported);
    },
  );
  test('a resource filename cannot redirect its secret identity', () async {
    final file = File('${resources.path}/studio.json');
    final source = jsonEncode({
      'id': 'other-account',
      'config': {'name': 'Confused'},
    });
    await file.writeAsString(source);
    await expectLater(
      ResourceRepository(
        resources,
        resourceType: 'OBSConnection',
        secretSettings: secrets,
      ).load('studio'),
      throwsFormatException,
    );
    expect(await file.readAsString(), source);
  });
}
