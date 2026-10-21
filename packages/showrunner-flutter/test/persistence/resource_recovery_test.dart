import '../support/transaction_file_fixtures.dart';
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

  for (var step = 1; step <= 4; step++) {
    for (final after in [false, true]) {
      test(
        'resource config/state/credentials recover write step $step after=$after',
        () async {
          await File(
            '${resources.path}/studio.yaml',
          ).writeAsString('host: old-host\n');
          await Directory('${resources.path}/.state').create();
          await File(
            '${resources.path}/.state/studio.json',
          ).writeAsString('{"generation":0}');
          await secrets.saveResource('OBSConnection', 'studio', {
            'password': 'old-password',
          });
          final failing = ResourceRepository(
            resources,
            resourceType: 'OBSConnection',
            secretSettings: secrets,
            fileOperations: FaultInjectingFiles(writeAt: step, after: after),
          );
          await expectLater(
            failing.save(
              const ResourceData(
                id: 'studio',
                config: {'host': 'new-host', 'password': 'new-password'},
                state: {'generation': 1},
              ),
            ),
            throwsA(isA<FileSystemException>()),
          );
          final pending = File('${resources.path}/.transactions/studio.json');
          if (await pending.exists()) {
            final raw = await pending.readAsString();
            expect(raw, isNot(contains('new-password')));
            final journal = jsonDecode(raw) as Map;
            for (final entry in journal['writes'] as List) {
              if (entry['data'] != null) {
                expect(
                  utf8.decode(
                    base64Decode(entry['data'] as String),
                    allowMalformed: true,
                  ),
                  isNot(contains('new-password')),
                );
              }
            }
          }
          final recovered = (await ResourceRepository(
            resources,
            resourceType: 'OBSConnection',
            secretSettings: secrets,
          ).load('studio'))!;
          final generation = step == 1 && !after ? 0 : 1;
          expect(
            recovered.config['host'],
            generation == 0 ? 'old-host' : 'new-host',
          );
          expect(
            recovered.config['password'],
            generation == 0 ? 'old-password' : 'new-password',
          );
          expect(recovered.state, {'generation': generation});
        },
      );
    }
  }
  test(
    'catalog recovers a pending creation before its public file exists',
    () async {
      final failing = ResourceRepository(
        resources,
        resourceType: 'OBSConnection',
        secretSettings: secrets,
        fileOperations: FaultInjectingFiles(writeAt: 2, after: true),
      );
      await expectLater(
        failing.save(
          const ResourceData(
            id: 'studio',
            config: {'host': 'host', 'password': 'private-value'},
          ),
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(await File('${resources.path}/studio.json').exists(), false);
      final catalog = await ResourceRepository(
        resources,
        resourceType: 'OBSConnection',
        secretSettings: secrets,
      ).listWithErrors();
      expect(catalog, hasLength(1));
      expect(catalog.single.isValid, true);
      expect(catalog.single.resource!.config['password'], 'private-value');
    },
  );
  test(
    'accepted resource input is isolated from later caller mutations',
    () async {
      final config = <String, dynamic>{
        'host': 'accepted',
        'password': 'accepted-secret',
        'nested': {'value': 1},
      };
      final repository = ResourceRepository(
        resources,
        resourceType: 'OBSConnection',
        secretSettings: secrets,
      );
      final saving = repository.save(
        ResourceData(id: 'studio', config: config),
      );
      config['host'] = 'changed';
      config['password'] = 'changed-secret';
      (config['nested'] as Map)['value'] = 2;
      await saving;
      final loaded = (await repository.load('studio'))!;
      expect(loaded.config, {
        'host': 'accepted',
        'password': 'accepted-secret',
        'nested': {'value': 1},
      });
    },
  );
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
