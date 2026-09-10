import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:showrunner_flutter/app/bootstrap/showrunner_services.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/plugins/showrunner/manifest.dart';
import 'package:showrunner_flutter/runtime/action_queue.dart';
import 'package:showrunner_flutter/runtime/automation_queue_manager.dart';
import 'package:showrunner_flutter/runtime/cancellation.dart';
import 'package:showrunner_flutter/runtime/expression.dart';
import 'package:showrunner_flutter/runtime/graph_execution_engine.dart';
import 'package:showrunner_flutter/runtime/profile_runtime.dart';
import 'package:showrunner_flutter/schema/automation.dart';
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

    final automation = AutomationData(
      graph: AutomationGraph(
        entryNodeId: 'call',
        nodes: [
          const GraphNode(
            id: 'call',
            type: 'subgraphCall',
            x: 0,
            y: 0,
            data: {
              'subgraphId': 'format',
              'inputs': {
                'value': {'type': 'literal', 'value': 7},
              },
            },
          ),
          const GraphNode(
            id: 'return',
            type: 'return',
            x: 100,
            y: 0,
            data: {
              'outputs': {
                'result': {'type': 'port', 'nodeId': 'call', 'port': 'result'},
              },
            },
          ),
        ],
        edges: const [GraphEdge(id: 'call-return', from: 'call', to: 'return')],
      ),
      subgraphs: [
        SubgraphDefinition(
          id: 'format',
          name: 'Format',
          parameters: const [
            {'name': 'value'},
          ],
          outputs: const [
            {
              'name': 'result',
              'expression': {
                'type': 'port',
                'nodeId': 'convert',
                'port': 'value',
              },
            },
          ],
          entryNodeId: 'convert',
          nodes: [
            const GraphNode(
              id: 'convert',
              type: 'action',
              x: 0,
              y: 0,
              data: {
                'plugin': 'ShowRunner',
                'action': 'convertNumberToString',
                'config': {'value': '{{value}}'},
              },
            ),
          ],
          edges: const [],
        ),
      ],
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

    final automation = AutomationData(
      extra: const {'name': 'Queued integration'},
      graph: AutomationGraph(
        entryNodeId: 'record',
        nodes: const [
          GraphNode(
            id: 'record',
            type: 'action',
            x: 0,
            y: 0,
            data: {
              'plugin': 'integration',
              'action': 'record',
              'config': {'value': 'queued'},
            },
          ),
        ],
      ),
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
    addTearDown(registry.close);
    final runtime = DartProfileRuntime(registry: registry);
    addTearDown(runtime.dispose);
    final triggered = AutomationData(
      graph: AutomationGraph(
        entryNodeId: 'record',
        nodes: const [
          GraphNode(
            id: 'record',
            type: 'action',
            x: 0,
            y: 0,
            data: {'plugin': 'integration', 'action': 'record', 'config': {}},
          ),
        ],
      ),
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

    expect(result?.completed, isTrue);
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
    final failed = AutomationData(
      graph: AutomationGraph(
        entryNodeId: 'fail',
        nodes: const [
          GraphNode(
            id: 'fail',
            type: 'action',
            x: 0,
            y: 0,
            data: {'plugin': 'integration', 'action': 'fail'},
          ),
        ],
      ),
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
    final cancellationGraph = AutomationData(
      graph: AutomationGraph(
        entryNodeId: 'cancel',
        nodes: const [
          GraphNode(
            id: 'cancel',
            type: 'action',
            x: 0,
            y: 0,
            data: {'plugin': 'integration', 'action': 'cancel'},
          ),
        ],
      ),
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
