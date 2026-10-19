import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/persistence/profile_repository.dart';
import '../../support/graph_fixtures.dart';
import 'package:showrunner_flutter/schema/profile.dart';
import 'package:showrunner_flutter/features/profile/profile_workspace.dart';

void main() {
  test('queues a profile open request until the workspace attaches', () async {
    final controller = ProfileWorkspaceController();
    var openedFileName = '';

    await controller.openProfile('queued.yaml');
    controller.attach(
      () async => true,
      openProfile: (fileName) async => openedFileName = fileName,
    );
    await Future<void>.delayed(Duration.zero);

    expect(openedFileName, 'queued.yaml');
    controller.detach();
  });

  test(
    'persists the profile trigger contract and activation condition',
    () async {
      final directory = await Directory.systemTemp.createTemp('profile-ui-');
      addTearDown(() => directory.delete(recursive: true));
      final profileFile = File('${directory.path}/profiles/main.yaml');
      final profile = ShowRunnerProfile(
        name: 'Main',
        activationMode: 'toggle',
        triggers: [
          {
            'id': 'trigger-1',

            'automation': eventFixture(
              id: 'chat',
              plugin: 'twitch',
              config: {'user': 'alice'},
            ).toJson(),
          },
        ],
        activationCondition: {
          'type': 'group',
          'operator': 'or',
          'operands': const [],
        },
        activationAutomation: AutomationDocument.empty(),
        deactivationAutomation: AutomationDocument.empty(),
      );
      await ProfileRepository(profileFile).save(profile);
      final saved = await ProfileRepository(profileFile).load();
      expect(saved?.activationCondition['operator'], 'or');
      final document = AutomationDocument.fromJson(
        Map<String, Object?>.from(saved!.triggers.single['automation'] as Map),
      );
      final event =
          document.graph.spaces[mainAutomationSpace]!.nodes.values.single;
      expect(event.type, triggerNodeType('twitch', 'chat'));
      expect(event.data['config'], {'user': 'alice'});
    },
  );

  test('rejects old profile automation documents without conversion', () async {
    final directory = await Directory.systemTemp.createTemp('profile-v2-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/profiles/graph.yaml');
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({
        'name': 'Graph profile',
        'activationMode': 'always',
        'triggers': [
          {
            'id': 'automation-1',
            'automation': {
              'schemaVersion': 2,
              'graph': {'nodes': [], 'edges': [], 'entryNodeId': ''},
              'subgraphs': [],
              'dataWires': [],
              'variableNodes': [],
              'triggerNodes': [
                {'id': 'trigger-1'},
              ],
            },
          },
        ],
        'activationCondition': {},
        'activationAutomation': {
          'schemaVersion': 2,
          'graph': {'nodes': [], 'edges': [], 'entryNodeId': ''},
          'subgraphs': [],
          'dataWires': [],
          'variableNodes': [],
          'triggerNodes': [],
        },
        'deactivationAutomation': {
          'schemaVersion': 2,
          'graph': {'nodes': [], 'edges': [], 'entryNodeId': ''},
          'subgraphs': [],
          'dataWires': [],
          'variableNodes': [],
          'triggerNodes': [],
        },
      }),
    );

    await expectLater(ProfileRepository(file).load(), throwsFormatException);
    expect(await Directory('${directory.path}/backup').exists(), isFalse);
  });
}
