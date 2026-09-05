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

  test('rejects non-V2 automation files', () async {
    final directory = await Directory.systemTemp.createTemp(
      'showrunner-invalid-automation-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/automations/invalid.yaml');
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({
        'schemaVersion': 1,
        'graph': {'nodes': [], 'edges': [], 'entryNodeId': ''},
      }),
    );

    await expectLater(
      AutomationRepository(file).load(),
      throwsA(isA<FormatException>()),
    );
  });
}
