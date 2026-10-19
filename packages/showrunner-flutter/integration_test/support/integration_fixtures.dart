import 'dart:io';
import 'package:showrunner_flutter/persistence/automation_repository.dart';
import 'package:showrunner_flutter/schema/profile.dart';
import '../../test/support/graph_fixtures.dart';
export '../../test/support/graph_fixtures.dart';

AutomationDocument namedAutomation(
  String name, {
  bool withAction = false,
  String actionValue = '42',
}) => automationFixture(
  name: name,
  nodes: [
    if (withAction)
      actionFixture(
        'convert',
        plugin: 'ShowRunner',
        action: 'convertNumberToString',
        config: {'value': actionValue},
        data: {
          'resultMapping': {'value': 'converted'},
        },
      ),
  ],
  entryNodeId: withAction ? 'convert' : '',
);
AutomationDocument actionAutomation({String value = '42'}) => namedAutomation(
  'Integration automation',
  withAction: true,
  actionValue: value,
);
Future<void> saveAutomation(
  Directory root,
  String fileName,
  AutomationDocument automation,
) => AutomationRepository(
  File('${root.path}/automations/$fileName'),
).save(automation);
ShowRunnerProfile profileWithTrigger({
  required AutomationDocument triggerAutomation,
  String name = 'Integration profile',
}) {
  final space = triggerAutomation.graph.spaces[mainAutomationSpace]!;
  const source = 'integration-event';
  final document = AutomationDocument.fromGraph(
    triggerAutomation.graph.copyWith(
      spaces: {
        ...triggerAutomation.graph.spaces,
        mainAutomationSpace: space.copyWith(
          nodes: {
            ...space.nodes,
            source: GraphNode(
              id: source,
              type: triggerNodeType('ShowRunner', 'autoRun'),
            ),
          },
          connections: {
            ...space.connections,
            if (triggerAutomation.entryNodeId.isNotEmpty)
              'event-next': controlFixture(
                'event-next',
                source,
                triggerAutomation.entryNodeId,
              ),
          },
        ),
      },
    ),
  ).withSettings({...triggerAutomation.settings, 'entryNodeId': source});
  return ShowRunnerProfile(
    name: name,
    activationMode: 'always',
    triggers: [
      {'id': 'integration-trigger', 'automation': document.toJson()},
    ],
    activationCondition: const {},
    activationAutomation: AutomationDocument.empty(),
    deactivationAutomation: AutomationDocument.empty(),
  );
}
