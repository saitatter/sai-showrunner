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
      final repository = ResourceRepository(directory);
      final file = File('${directory.path}/plan.json');
      await file.writeAsString(
        jsonEncode({
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
        }),
      );

      final loaded = await repository.load('plan');
      final config = loaded!.config;

      expect(config['activationAutomation']['schemaVersion'], 2);
      expect(config['activationAutomation'].containsKey('sequence'), isFalse);
      expect(config['segments'][0]['activationAutomation']['schemaVersion'], 2);
    },
  );
}
