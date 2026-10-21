import 'dart:io';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/persistence/resource_repository.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/plugins/variables/manifest.dart';
import 'package:showrunner_flutter/plugins/variables/runtime.dart';
import 'package:showrunner_flutter/runtime/expression.dart';
import 'package:showrunner_flutter/graph/runtime/graph_execution_engine.dart';
import '../../support/graph_fixtures.dart';
import 'package:showrunner_flutter/schema/resource.dart';
import 'package:showrunner_flutter/persistence/filesystem/file_transaction.dart';

void main() {
  test(
    'close drains blocked variable edits before their registry dependency closes',
    () async {
      final root = await Directory.systemTemp.createTemp('variable-close-');
      final repository = ResourceRepository(root);
      await repository.save(
        const ResourceData(
          id: 'count',
          config: {'type': 'number', 'persistent': true, 'defaultValue': 1},
          state: {'value': 1},
        ),
      );
      final registry = DartPluginRegistry();
      registry.register(createVariablesPlugin());
      final runtime = DartVariableRuntime(
        directory: root,
        onChanged: (id, value) =>
            registry.updateDynamicState('variables', id, value),
      );
      await runtime.load();
      final entered = Completer<void>(), release = Completer<void>();
      final blocker = FileTransaction(directory: root, id: 'count', targets: {})
          .locked(() async {
            entered.complete();
            await release.future;
          });
      await entered.future;
      final edit = runtime.setValue('count', 7);
      var closed = false;
      final closing = runtime.close().then((_) {
        closed = true;
      });
      try {
        await Future<void>.delayed(Duration.zero);
        expect(closed, false);
        await expectLater(runtime.reload(), throwsStateError);
      } finally {
        release.complete();
        await blocker;
        await edit;
        await closing;
        await runtime.close();
      }
      expect(registry.stateValues('variables')['count'], 7);
      expect((await repository.load('count'))?.state['value'], 7);
      await registry.close();
      await root.delete(recursive: true);
    },
  );
  test(
    'concurrent offsets share canonical ID ownership and return each result',
    () async {
      final root = await Directory.systemTemp.createTemp('variable-offsets-');
      addTearDown(() => root.delete(recursive: true));
      final repository = ResourceRepository(root);
      await repository.save(
        const ResourceData(
          id: 'count',
          config: {
            'name': 'Count',
            'type': 'number',
            'persistent': true,
            'defaultValue': 0,
          },
        ),
      );
      final runtime = DartVariableRuntime(directory: root);
      final results = await Future.wait([
        for (var i = 0; i < 30; i++)
          runtime.offsetValue(i.isEven ? 'count' : 'Count', 1),
      ]);
      expect(results, List.generate(30, (i) => i + 1));
      expect((await repository.load('count'))!.state['value'], 30);
      await runtime.close();
    },
  );

  test(
    'runtime patches preserve editor config and unrelated state without resurrecting deletes',
    () async {
      final root = await Directory.systemTemp.createTemp('variable-patch-');
      addTearDown(() => root.delete(recursive: true));
      final repository = ResourceRepository(root);
      await repository.save(
        const ResourceData(
          id: 'count',
          config: {'type': 'number', 'persistent': true, 'defaultValue': 3},
        ),
      );
      final runtime = DartVariableRuntime(directory: root);
      expect(await runtime.resetValue('count'), 3);
      await repository.save(
        const ResourceData(
          id: 'count',
          config: {
            'type': 'number',
            'name': 'Edited',
            'persistent': true,
            'defaultValue': 10,
            'futureField': {'keep': true},
          },
          state: {'value': 3, 'other': 42},
        ),
      );
      await runtime.setValue('count', 7);
      final saved = (await repository.load('count'))!;
      expect(saved.config['name'], 'Edited');
      expect(saved.config['defaultValue'], 10);
      expect(saved.config['futureField'], {'keep': true});
      expect(saved.state, {'value': 7, 'other': 42});
      await repository.save(
        ResourceData(
          id: 'count',
          config: {...saved.config, 'persistent': false},
          state: saved.state,
        ),
      );
      await runtime.setValue('count', 8);
      expect((await repository.load('count'))!.state['value'], 7);
      await repository.delete('count');
      await runtime.setValue('count', 9);
      expect(await repository.load('count'), isNull);
      await runtime.close();
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
    final result = await CompiledExecutionEngine().executeWithRegistry(
      automation: automationFixture(
        nodes: [
          GraphNode(
            id: 'get',
            type: actionNodeType('variables', 'getVariable'),
            data: {
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
