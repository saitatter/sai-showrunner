import 'package:showrunner_flutter/persistence/automation_repository.dart';
import 'dart:io';
import 'dart:convert';
import '../../support/graph_fixtures.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/features/plugins/plugin_usage.dart';

void main() {
  test('indexes root triggers, graph actions, and subgraph actions', () async {
    final directory = await Directory.systemTemp.createTemp(
      'showrunner-usage-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final nested = actionFixture(
      'nested',
      plugin: 'twitch',
      action: 'timeout',
      config: {'seconds': 10},
    );
    final signature = AutomationSubgraph(
      id: 'branch',
      name: 'Alerts',
      entryNodeId: nested.id,
    );
    final document = automationFixture(
      name: 'Sample show',
      nodes: [
        GraphNode(
          id: 'trigger-1',
          type: triggerNodeType('twitch', 'follow'),
          data: {
            'config': {'user': 'alice'},
          },
        ),
        actionFixture(
          'action-1',
          plugin: 'twitch',
          action: 'chat',
          config: {'message': 'hello'},
        ),
        actionFixture('other', plugin: 'obs', action: 'scene'),
      ],
      entryNodeId: 'trigger-1',
      subgraphs: {signature.id: signature},
      spaces: {
        signature.spaceId: GraphSpace(
          id: signature.spaceId,
          nodes: {nested.id: nested},
        ),
      },
    );
    await File(
      '${directory.path}/sample.yaml',
    ).writeAsString(jsonEncode(document.toJson()));

    final usage = await loadPluginUsage(
      loadEntries: () => AutomationRepository.loadDirectory(directory),
      pluginId: 'twitch',
    );

    expect(usage.map((entry) => entry.kind), [
      'Action node',
      'Subgraph action · Alerts',
      'Trigger',
    ]);
    expect(usage.map((entry) => entry.name), ['chat', 'timeout', 'follow']);
    expect(usage.first.automationName, 'Sample show');
    expect(usage.last.config['user'], 'alice');
  });
}
