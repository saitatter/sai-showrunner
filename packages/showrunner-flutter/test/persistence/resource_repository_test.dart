import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/persistence/resource_repository.dart';
import 'package:showrunner_flutter/persistence/secret_settings_store.dart';
import 'package:showrunner_flutter/schema/resource.dart';

void main() {
  test('rejects malformed JSON at the resource schema boundary', () async {
    final directory = await Directory.systemTemp.createTemp(
      'showrunner-resource-schema-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final repository = ResourceRepository(directory);
    final file = File('${directory.path}/broken.json');

    await file.writeAsString(jsonEncode({'id': 'broken', 'config': []}));

    await expectLater(
      repository.load('broken'),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('config'),
        ),
      ),
    );
  });

  test(
    'rejects non-object JSON resources instead of casting blindly',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'showrunner-resource-schema-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final repository = ResourceRepository(directory);
      final file = File('${directory.path}/broken.json');

      await file.writeAsString(jsonEncode(['not', 'a', 'resource']));

      await expectLater(
        repository.load('broken'),
        throwsA(isA<FormatException>()),
      );
    },
  );

  test('accepts resources without optional state', () {
    final resource = ResourceData.fromJson({
      'id': 'resource-1',
      'config': {'name': 'Resource'},
    });

    expect(resource.id, 'resource-1');
    expect(resource.name, 'Resource');
    expect(resource.state, isEmpty);
  });

  test('keeps resource secrets outside the public resource file', () async {
    final root = await Directory.systemTemp.createTemp(
      'showrunner-resource-secrets-',
    );
    addTearDown(() => root.delete(recursive: true));
    Future<List<int>> cipher(List<int> bytes) async =>
        bytes.map((byte) => byte ^ 0x5a).toList();
    final secrets = SecretSettingsStore(
      directory: Directory('${root.path}/secrets'),
      encrypt: cipher,
      decrypt: cipher,
    );
    final repository = ResourceRepository(
      Directory('${root.path}/obs/connections'),
      resourceType: 'OBSConnection',
      secretSettings: secrets,
    );

    await repository.save(
      const ResourceData(
        id: 'studio',
        config: {
          'name': 'Studio OBS',
          'host': '127.0.0.1',
          'port': 4455,
          'password': 'private-password',
        },
      ),
    );

    final publicFile = File('${root.path}/obs/connections/studio.json');
    expect(
      await publicFile.readAsString(),
      isNot(contains('private-password')),
    );
    expect(
      (await repository.load('studio'))!.config['password'],
      'private-password',
    );

    await repository.delete('studio');
    expect(
      await File(
        '${root.path}/secrets/resources/OBSConnection/studio.yaml',
      ).exists(),
      isFalse,
    );
  });
}
