import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sai_nodes/sai_nodes.dart';
import 'package:showrunner_flutter/persistence/profile_repository.dart';
import 'package:showrunner_flutter/schema/automation.dart';
import 'package:showrunner_flutter/schema/profile.dart';
import 'package:showrunner_flutter/editor/showrunner_graph_editor.dart';
import 'package:showrunner_flutter/features/graph/graph_workspace.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';

void main() {
  test(
    'persists the legacy trigger contract and activation condition',
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
            'plugin': 'twitch',
            'trigger': 'chat',
            'config': {'user': 'alice'},
          },
        ],
        activationCondition: {
          'type': 'group',
          'operator': 'or',
          'operands': const [],
        },
        activationAutomation: AutomationData(),
        deactivationAutomation: AutomationData(),
      );
      await ProfileRepository(profileFile).save(profile);
      final saved = await ProfileRepository(profileFile).load();
      expect(saved?.activationCondition['operator'], 'or');
      expect(saved!.triggers.single['plugin'], 'twitch');
      expect(saved.triggers.single['trigger'], 'chat');
      expect(saved.triggers.single['config'], {'user': 'alice'});
    },
  );

  testWidgets(
    'opens a pre-v1 profile and renders its migrated inline automations',
    (tester) async {
      final profile = ShowRunnerProfile.fromJson({
        'name': 'Legacy Profile',
        'activationMode': 'always',
        'triggers': <dynamic>[],
        'activationCondition': {'type': 'value', 'value': true},
        'activationAutomation': {
          'sequence': {
            'actions': [
              {
                'id': 'activation',
                'plugin': 'sample',
                'action': 'emit',
                'config': {'value': 'started'},
              },
            ],
          },
        },
        'deactivationAutomation': {
          'sequence': {
            'actions': [
              {
                'id': 'deactivation',
                'plugin': 'sample',
                'action': 'emit',
                'config': {'value': 'stopped'},
              },
            ],
          },
        },
      });
      final activationEditor = ShowRunnerGraphEditor()
        ..loadAutomation(profile.activationAutomation);
      final deactivationEditor = ShowRunnerGraphEditor()
        ..loadAutomation(profile.deactivationAutomation);
      addTearDown(activationEditor.dispose);
      addTearDown(deactivationEditor.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShowRunnerInlineGraphEditor(
              editor: activationEditor,
              registryFuture: Future.value(DartPluginRegistry()),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
      expect(find.byType(NodeEditorToolbar), findsOneWidget);
      expect(activationEditor.controller.nodes, hasLength(1));
      expect(deactivationEditor.controller.nodes, hasLength(1));
    },
  );
}
