import 'package:showrunner_flutter/runtime/graph_invocation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:showrunner_flutter/app/bootstrap/showrunner_services.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/plugins/showrunner/manifest.dart';
import 'package:showrunner_flutter/runtime/action_queue.dart';
import 'package:showrunner_flutter/runtime/automation_queue_manager.dart';
import 'package:showrunner_flutter/runtime/cancellation.dart';
import 'package:showrunner_flutter/runtime/expression.dart';
import 'package:showrunner_flutter/graph/runtime/graph_execution_engine.dart';
import 'package:showrunner_flutter/runtime/profile_runtime.dart';

import 'package:showrunner_flutter/services/showrunner_data_service.dart';

import '../support/integration_fixtures.dart';
import '../support/showrunner_test_app.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test(
    'executes a real graph through the production Flutter composition',
    () async {
      final directory = await createShowRunnerFixtureDirectory();
      addTearDown(() => directory.delete(recursive: true));
      final services = ShowRunnerServices.create(
        dataService: ShowRunnerDataService(directory),
        onVariableChanged: (_, _) {},
      );
      addTearDown(services.shutdown);

      final registry = await services.pluginRegistryFuture;
      final result = await services.graphExecutionEngine.executeWithRegistry(
        automation: actionAutomation(value: '42'),
        context: EvaluationContext(),
        registry: registry,
      );

      expect(result.completed, isTrue);
      expect(result.nodeResults['convert'], {'value': '42'});
      expect(result.contextState['converted'], '42');
      expect(services.graphExecutionEngine, isA<CompiledExecutionEngine>());
    },
  );

  test('executes nested subgraphs and preserves output values', () async {
    final registry = DartPluginRegistry()..register(createShowRunnerPlugin());
    addTearDown(registry.close);

    final signature = AutomationSubgraph(
      id: 'format',
      name: 'Format',
      entryNodeId: 'convert',
      parameters: [
        AutomationParameter(id: 'p', name: 'value', type: 'core.number'),
      ],
      outputs: [
        AutomationParameter(id: 'r', name: 'result', type: 'core.string'),
      ],
    );
    final automation = automationFixture(
      entryNodeId: 'call',
      nodes: [
        GraphNode(
          id: 'call',
          type: 'showrunner.subgraphCall',
          data: {
            'subgraphId': 'format',
            'arguments': {'p': 7},
          },
        ),
        GraphNode(
          id: 'return',
          type: 'showrunner.return',
          data: {
            'outputs': {
              'result': {'type': 'port', 'nodeId': 'call', 'port': 'result'},
            },
          },
        ),
      ],
      connections: [controlFixture('call-return', 'call', 'return')],
      subgraphs: {'format': signature},
      spaces: {
        signature.spaceId: GraphSpace(
          id: signature.spaceId,
          nodes: {
            'parameter': GraphNode(
              id: 'parameter',
              type: 'showrunner.parameter',
              data: {'parameterId': 'p'},
            ),
            'convert': actionFixture(
              'convert',
              plugin: 'ShowRunner',
              action: 'convertNumberToString',
              config: {'value': 0},
            ),
            'sub-return': GraphNode(
              id: 'sub-return',
              type: 'showrunner.return',
            ),
          },
          connections: {
            'next': controlFixture('next', 'convert', 'sub-return'),
            'input': valueFixture(
              'input',
              'parameter',
              'value.out',
              'convert',
              'config:value',
            ),
            'output': valueFixture(
              'output',
              'convert',
              'result:value',
              'sub-return',
              'output:r',
            ),
          },
        ),
      },
    );

    final result = await CompiledExecutionEngine().executeWithRegistry(
      automation: automation,
      context: EvaluationContext(),
      registry: registry,
    );
    expect(result.completed, isTrue);
    expect(result.outputValues, {'result': '7'});
  });

  test('runs queued automation and records its completed history', () async {
    final calls = <String>[];
    final registry = DartPluginRegistry()
      ..register(
        DartPluginManifest(
          id: PluginId('integration'),
          name: 'Integration',
          actions: [
            ActionSpec<Map<String, dynamic>, Object?>(
              pluginId: PluginId('integration'),
              actionId: ActionId('record'),
              invoke: (config, context) async {
                calls.add(config['value'].toString());
                return {'recorded': true};
              },
            ),
          ],
        ),
      );
    addTearDown(registry.close);
    final queueManager = DartAutomationQueueManager(
      defaultQueue: DartActionQueue(),
      execute: (automation, context, _) =>
          CompiledExecutionEngine().executeWithRegistry(
            automation: automation,
            context: context,
            registry: registry,
          ),
    );
    addTearDown(queueManager.dispose);

    final automation = automationFixture(
      name: 'Queued integration',
      nodes: [
        actionFixture(
          'record',
          plugin: 'integration',
          config: {'value': 'queued'},
        ),
      ],
      entryNodeId: 'record',
    );
    final item = await queueManager.enqueue(automation, EvaluationContext());
    await queueManager.drain('default');
    for (var attempt = 0; attempt < 20 && item.status == 'running'; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }

    expect(item.status, 'completed');
    expect(queueManager.defaultQueue.history.single.id, item.id);
    expect(calls, ['queued']);
  });

  test('dispatches an active profile trigger into its graph', () async {
    final calls = <String>[];
    final registry = DartPluginRegistry()
      ..register(
        DartPluginManifest(
          id: PluginId('integration'),
          name: 'Integration',
          actions: [
            ActionSpec<Map<String, dynamic>, Object?>(
              pluginId: PluginId('integration'),
              actionId: ActionId('record'),
              invoke: (config, context) async {
                calls.add(context.contextState['event']['message'].toString());
                return null;
              },
            ),
          ],
        ),
      );
    registry.register(createShowRunnerPlugin());
    addTearDown(registry.close);
    final runtime = DartProfileRuntime(registry: registry);
    addTearDown(runtime.dispose);
    final triggered = automationFixture(
      nodes: [actionFixture('record', plugin: 'integration')],
      entryNodeId: 'record',
    );
    final profile = profileWithTrigger(triggerAutomation: triggered);
    await runtime.activate('integration-profile', profile);
    final result = await runtime.handleTrigger(
      'integration-profile',
      profile,
      'ShowRunner',
      'autoRun',
      {'message': 'profile-event'},
    );

    expect(result, isA<InvocationCompleted>());
    expect((result as InvocationCompleted).execution.completed, isTrue);
    expect(calls, ['profile-event']);
  });

  test('surfaces failed actions and propagates cancellation', () async {
    final registry = DartPluginRegistry()
      ..register(
        DartPluginManifest(
          id: PluginId('integration'),
          name: 'Integration',
          actions: [
            ActionSpec<Map<String, dynamic>, Object?>(
              pluginId: PluginId('integration'),
              actionId: ActionId('fail'),
              invoke: (config, context) =>
                  Future<Object?>.error(StateError('integration failure')),
            ),
            ActionSpec<Map<String, dynamic>, Object?>(
              pluginId: PluginId('integration'),
              actionId: ActionId('cancel'),
              invoke: (config, context) async {
                context.cancellationToken?.cancel();
                return null;
              },
            ),
          ],
        ),
      );
    addTearDown(registry.close);
    final failed = automationFixture(
      nodes: [actionFixture('fail', plugin: 'integration', action: 'fail')],
      entryNodeId: 'fail',
    );
    await expectLater(
      CompiledExecutionEngine().executeWithRegistry(
        automation: failed,
        context: EvaluationContext(),
        registry: registry,
      ),
      throwsA(isA<StateError>()),
    );

    final token = DartCancellationToken(id: 'integration-cancel');
    final cancellationGraph = automationFixture(
      nodes: [actionFixture('cancel', plugin: 'integration', action: 'cancel')],
      entryNodeId: 'cancel',
    );
    await expectLater(
      CompiledExecutionEngine().executeWithRegistry(
        automation: cancellationGraph,
        context: EvaluationContext(cancellationToken: token),
        registry: registry,
      ),
      throwsA(isA<DartCancelledException>()),
    );
    expect(token.isCancelled, isTrue);
    // Keep the async test honest if a future implementation adds delayed
    // cancellation cleanup.
    await Future<void>.value();
  });
}
