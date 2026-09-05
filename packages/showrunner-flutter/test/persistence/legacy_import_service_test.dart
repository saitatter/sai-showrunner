import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/persistence/migrations/legacy_import_service.dart';

void main() {
  const service = LegacyImportService();

  test('converts legacy action sequences and root trigger metadata', () {
    final result = service.importAutomation({
      'name': 'Legacy chat reply',
      'plugin': 'twitch',
      'trigger': 'chat',
      'config': {'command': '!hello'},
      'sequence': {
        'actions': [
          {
            'id': 'reply',
            'plugin': 'twitch',
            'action': 'chat',
            'config': {'message': 'Hello'},
          },
        ],
      },
      'floatingSequences': const [],
    });

    expect(result.report.migrated, isTrue);
    expect(result.automation.schemaVersion, 2);
    expect(result.automation.graph.entryNodeId, 'reply');
    expect(result.automation.graph.nodes.single.data['plugin'], 'twitch');
    expect(result.automation.triggerNodes, [
      {
        'id': 'trigger',
        'plugin': 'twitch',
        'trigger': 'chat',
        'config': {'command': '!hello'},
        'stop': false,
        'x': 42,
        'y': 88,
      },
    ]);
    final persisted = result.automation.toJson();
    expect(persisted.containsKey('sequence'), isFalse);
    expect(persisted.containsKey('floatingSequences'), isFalse);
    expect(persisted.containsKey('plugin'), isFalse);
    expect(persisted.containsKey('trigger'), isFalse);
  });

  test('flattens legacy stack and nested flow actions in order', () {
    final result = service.importAutomation({
      'sequence': {
        'actions': [
          {
            'stack': [
              {'plugin': 'a', 'action': 'one'},
              {'plugin': 'a', 'action': 'two'},
            ],
            'offsets': [
              {
                'actions': [
                  {'plugin': 'a', 'action': 'three'},
                ],
              },
            ],
          },
        ],
      },
    });

    expect(result.automation.graph.nodes.map((node) => node.data['action']), [
      'one',
      'two',
    ]);
    expect(result.report.warnings, isEmpty);
  });

  test('normalizes profile and stream-plan inline automations', () {
    final profile = service.normalizeProfileMap({
      'name': 'Legacy profile',
      'activationMode': 'toggle',
      'triggers': [
        {
          'plugin': 'twitch',
          'trigger': 'chat',
          'config': {},
          'sequence': {
            'actions': [
              {'plugin': 'twitch', 'action': 'chat'},
            ],
          },
        },
      ],
      'activationAutomation': {
        'sequence': {'actions': []},
      },
      'deactivationAutomation': {
        'sequence': {'actions': []},
      },
    });
    final plan = service.normalizeStreamPlanMap({
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
    });

    expect(profile['activationAutomation']['schemaVersion'], 2);
    expect(profile['triggers'][0]['id'], 'trigger-0');
    expect(profile['triggers'][0]['automation']['schemaVersion'], 2);
    expect(plan['activationAutomation']['schemaVersion'], 2);
    expect(plan['segments'][0]['activationAutomation']['schemaVersion'], 2);
    expect(jsonDecode(jsonEncode(plan)), isA<Map>());
  });

  test(
    'creates an isolated timestamped backup before replacing a file',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'showrunner-migration-',
      );
      addTearDown(() => root.delete(recursive: true));
      final file = File('${root.path}/automations/legacy.yaml');
      await file.parent.create(recursive: true);
      const original = '{"sequence":{"actions":[]}}';
      await file.writeAsString(original);

      final result = await service.migrateAutomationFile(file);

      expect(result.report.backupPath, isNotNull);
      expect(await File(result.report.backupPath!).readAsString(), original);
      expect((await file.readAsString()).contains('sequence'), isFalse);
    },
  );
}
