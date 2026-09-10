import 'dart:io';

import 'package:showrunner_flutter/persistence/automation_repository.dart';
import 'package:showrunner_flutter/schema/automation.dart';
import 'package:showrunner_flutter/schema/profile.dart';

AutomationData namedAutomation(
  String name, {
  bool withAction = false,
  String actionValue = '42',
}) {
  final nodes = <GraphNode>[];
  if (withAction) {
    nodes.add(
      GraphNode(
        id: 'convert',
        type: 'action',
        x: 80,
        y: 80,
        data: {
          'plugin': 'ShowRunner',
          'action': 'convertNumberToString',
          'config': {'value': actionValue},
          'resultMapping': {'value': 'converted'},
        },
      ),
    );
  }
  return AutomationData(
    extra: {'name': name},
    graph: AutomationGraph(
      nodes: nodes,
      entryNodeId: withAction ? 'convert' : '',
    ),
  );
}

AutomationData actionAutomation({String value = '42'}) => namedAutomation(
  'Integration automation',
  withAction: true,
  actionValue: value,
);

Future<void> saveAutomation(
  Directory root,
  String fileName,
  AutomationData automation,
) => AutomationRepository(
  File('${root.path}/automations/$fileName'),
).save(automation);

ShowRunnerProfile profileWithTrigger({
  required AutomationData triggerAutomation,
  String name = 'Integration profile',
}) => ShowRunnerProfile(
  name: name,
  activationMode: 'always',
  triggers: [
    {
      'id': 'integration-trigger',
      'plugin': 'ShowRunner',
      'trigger': 'autoRun',
      'config': const <String, dynamic>{},
      'automation': triggerAutomation.toJson(),
    },
  ],
  activationCondition: const <String, dynamic>{},
  activationAutomation: const AutomationData(),
  deactivationAutomation: const AutomationData(),
);
