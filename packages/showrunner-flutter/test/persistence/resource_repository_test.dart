import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/persistence/resource_repository.dart';
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

  test('keeps optional resource state backward compatible when omitted', () {
    final resource = ResourceData.fromJson({
      'id': 'resource-1',
      'config': {'name': 'Resource'},
    });

    expect(resource.id, 'resource-1');
    expect(resource.name, 'Resource');
    expect(resource.state, isEmpty);
  });

  test(
    'normalizes legacy inline stream-plan automations at the boundary',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'showrunner-stream-plan-schema-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final storage = Directory('${directory.path}/stream-plans');
      await storage.create(recursive: true);
      final repository = ResourceRepository(storage);
      final file = File('${storage.path}/plan.json');
      final legacy = {
        'id': 'plan',
        'config': {
          'name': 'Legacy plan',
          'activationAutomation': {
            'sequence': {'actions': []},
          },
          'deactivationAutomation': {
            'sequence': {'actions': []},
          },
          'segments': [
            {
              'id': 'intro',
              'name': 'Intro',
              'components': {},
              'activationAutomation': {
                'sequence': {'actions': []},
              },
              'deactivationAutomation': {
                'sequence': {'actions': []},
              },
            },
          ],
        },
      };
      await file.writeAsString(jsonEncode(legacy));

      final loaded = await repository.load('plan');
      final config = loaded!.config;

      expect(config['activationAutomation']['schemaVersion'], 2);
      expect(config['activationAutomation'].containsKey('sequence'), isFalse);
      expect(config['segments'][0]['activationAutomation']['schemaVersion'], 2);
      final persisted = await file.readAsString();
      expect(persisted, isNot(contains('sequence')));
      final backups = Directory('${directory.path}/backup');
      expect(await backups.exists(), isTrue);
      final backupFiles = await backups
          .list(recursive: true)
          .where((entity) => entity is File)
          .cast<File>()
          .toList();
      expect(backupFiles, hasLength(1));
      expect(await backupFiles.single.readAsString(), jsonEncode(legacy));

      final reopened = await repository.load('plan');
      expect(reopened!.config['activationAutomation']['schemaVersion'], 2);
      expect(
        (await backups
            .list(recursive: true)
            .where((entity) => entity is File)
            .cast<File>()
            .toList()),
        hasLength(1),
      );
    },
  );
}
