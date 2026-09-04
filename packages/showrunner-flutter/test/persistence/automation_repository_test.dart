import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/persistence/automation_repository.dart';
import 'package:showrunner_flutter/schema/automation.dart';

void main() {
  test('saves, loads, and deletes an automation file', () async {
    final directory = await Directory.systemTemp.createTemp(
      'showrunner-automation-repository-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final repository = AutomationRepository(
      File('${directory.path}/automations/new.yaml'),
    );
    const automation = AutomationData(
      extra: {'name': 'New Automation'},
      graph: AutomationGraph(entryNodeId: 'trigger-1'),
    );

    await repository.save(automation);
    final loaded = await repository.load();

    expect(loaded?.extra['name'], 'New Automation');
    expect(loaded?.graph.entryNodeId, 'trigger-1');

    await repository.delete();
    expect(await repository.file.exists(), isFalse);
  });

  test('persists legacy automation migration on first load', () async {
    final directory = await Directory.systemTemp.createTemp(
      'showrunner-legacy-repository-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/automations/legacy.yaml');
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({
        'name': 'Legacy automation',
        'sequence': {
          'actions': [
            {
              'id': 'legacy-action',
              'plugin': 'sample',
              'action': 'emit',
              'config': {'value': 'hello'},
            },
          ],
        },
        'floatingSequences': [
          {
            'id': 'legacy-floating',
            'actions': [
              {'plugin': 'sample', 'action': 'emit'},
            ],
          },
        ],
        'variableNodes': [
          {'id': 'text', 'type': 'string', 'value': 'hello'},
        ],
      }),
    );

    final loaded = await AutomationRepository(file).load();
    final persisted = jsonDecode(await file.readAsString()) as Map;

    expect(loaded?.graph.nodes.single.id, 'legacy-action');
    expect(loaded?.subgraphs.single.id, 'legacy-floating');
    expect(loaded?.variableNodes.single['id'], 'text');
    expect(persisted.containsKey('sequence'), isFalse);
    expect(persisted.containsKey('floatingSequences'), isFalse);
    expect(persisted['schemaVersion'], 2);
    expect((persisted['graph'] as Map)['nodes'], isNotEmpty);
  });
}
