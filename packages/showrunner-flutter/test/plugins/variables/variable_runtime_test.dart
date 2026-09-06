import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/persistence/resource_repository.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/plugins/variables/manifest.dart';
import 'package:showrunner_flutter/plugins/variables/runtime.dart';
import 'package:showrunner_flutter/runtime/expression.dart';
import 'package:showrunner_flutter/runtime/graph_runtime.dart';
import 'package:showrunner_flutter/schema/automation.dart';
import 'package:showrunner_flutter/schema/resource.dart';

void main() {
  test(
    'imports the Electron variables file into backed-up resources',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'showrunner-variables-',
      );
      addTearDown(() => root.delete(recursive: true));
      final directory = Directory('${root.path}/variables');
      await directory.create(recursive: true);
      final legacy = File('${directory.path}/variables.yaml');
      await legacy.writeAsString('''
count:
  type: Number
  serialized: true
  defaultValue: 1
  savedValue: 3
enabled:
  type: Boolean
  serialized: false
  defaultValue: true
  savedValue: false
''');

      final runtime = DartVariableRuntime(directory: directory);
      await runtime.load();

      expect(runtime.valueOf('count'), 3);
      expect(runtime.valueOf('enabled'), true);
      expect(await legacy.exists(), isFalse);
      expect(await ResourceRepository(directory).load('count'), isNotNull);
      expect(await Directory('${root.path}/backup').exists(), isTrue);
    },
  );

  test('variable actions persist values and expose dynamic state', () async {
    final root = await Directory.systemTemp.createTemp('showrunner-variables-');
    addTearDown(() => root.delete(recursive: true));
    final directory = Directory('${root.path}/variables');
    await ResourceRepository(directory).save(
      const ResourceData(
        id: 'count',
        config: {
          'name': 'Count',
          'type': 'number',
          'defaultValue': 1,
          'persistent': true,
        },
        state: {'value': 1},
      ),
    );

    final registry = DartPluginRegistry();
    final runtime = DartVariableRuntime(
      directory: directory,
      onChanged: (id, value) =>
          registry.updateDynamicState('variables', id, value),
    );
    registry.register(createVariablesPlugin(variableRuntime: runtime));
    addTearDown(registry.close);
    await registry.start();

    await registry.invokeAction('variables', 'set', {
      'variable': 'count',
      'value': '4.5',
    });
    final result = await registry.invokeAction('variables', 'getVariable', {
      'variable': 'count',
    });

    expect((result as Map)['value'], 4.5);
    expect(registry.stateValues('variables')['count'], 4.5);
    final restored = DartVariableRuntime(directory: directory);
    await restored.load();
    expect(restored.valueOf('count'), 4.5);
  });

  test('reload keeps session variables in memory', () async {
    final root = await Directory.systemTemp.createTemp('showrunner-variables-');
    addTearDown(() => root.delete(recursive: true));
    final directory = Directory('${root.path}/variables');
    final repository = ResourceRepository(directory);
    await repository.save(
      const ResourceData(
        id: 'sessionCount',
        config: {
          'name': 'Session count',
          'type': 'number',
          'defaultValue': 0,
          'persistent': false,
        },
      ),
    );

    final runtime = DartVariableRuntime(directory: directory);
    await runtime.load();
    expect(await runtime.setValue('sessionCount', 9), 9);

    await runtime.reload();

    expect(runtime.valueOf('sessionCount'), 9);
    expect((await repository.load('sessionCount'))?.state, isEmpty);
  });

  test('registry executions start with current variable state', () async {
    final registry = DartPluginRegistry();
    registry.register(createVariablesPlugin());
    addTearDown(registry.close);
    // The graph-runtime state merge is covered independently from disk-backed
    // loading; this keeps the fixture hermetic and proves plugin state is
    // available to a new graph context.
    registry.updateDynamicState('variables', 'count', 7);
    final result = await const DartGraphRuntime().executeWithRegistry(
      graph: const AutomationGraph(
        nodes: [
          GraphNode(
            id: 'get',
            type: 'action',
            x: 0,
            y: 0,
            data: {
              'plugin': 'variables',
              'action': 'getVariable',
              'config': {'variable': 'count'},
            },
          ),
        ],
        entryNodeId: 'get',
      ),
      context: EvaluationContext(),
      registry: registry,
    );
    expect(result.nodeResults['get']?['value'], 7);
  });
}
