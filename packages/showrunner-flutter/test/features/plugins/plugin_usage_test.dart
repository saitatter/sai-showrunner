import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/features/plugins/plugin_usage.dart';

void main() {
  test('indexes root triggers, graph actions, and subgraph actions', () async {
    final directory = await Directory.systemTemp.createTemp(
      'showrunner-usage-',
    );
    addTearDown(() => directory.delete(recursive: true));
    await File('${directory.path}/sample.yaml').writeAsString('''
schemaVersion: 2
name: Sample show
triggerNodes:
  - id: trigger-1
    plugin: twitch
    trigger: follow
    config:
      user: alice
graph:
  nodes:
    - id: action-1
      type: action
      plugin: twitch
      action: chat
      config:
        message: hello
    - id: other
      type: action
      plugin: obs
      action: scene
subgraphs:
  - id: branch
    name: Alerts
    nodes:
      - id: nested
        type: action
        plugin: twitch
        action: timeout
        config:
          seconds: 10
''');

    final usage = await loadPluginUsage(
      directory: directory,
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
