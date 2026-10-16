import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/plugins/showrunner/manifest.dart';
import 'package:showrunner_flutter/runtime/expression.dart';
import 'package:showrunner_flutter/runtime/profile_runtime.dart';
import 'package:showrunner_flutter/runtime/action_queue.dart';
import 'package:showrunner_flutter/runtime/automation_queue_manager.dart';
import 'package:showrunner_flutter/graph/runtime/graph_execution_engine.dart';
import 'package:showrunner_flutter/schema/profile.dart';
import '../support/graph_fixtures.dart';

void main() {
  test('empty activation conditions mean always on', () {
    expect(
      evaluateBooleanCondition({
        'type': 'group',
        'operator': 'and',
        'operands': const [],
      }, EvaluationContext()),
      isTrue,
    );
    expect(evaluateBooleanCondition(const {}, EvaluationContext()), isTrue);
  });

  test('evaluates profile boolean groups and state values', () {
    final condition = <String, dynamic>{
      'type': 'group',
      'operator': 'and',
      'operands': [
        {
          'type': 'value',
          'operator': 'greaterThan',
          'lhs': {'type': 'state', 'plugin': 'twitch', 'state': 'viewers'},
          'rhs': {'type': 'value', 'value': 10},
        },
        {
          'type': 'value',
          'operator': 'equal',
          'lhs': {'type': 'value', 'value': 'live'},
          'rhs': {'type': 'value', 'value': 'live'},
        },
      ],
    };

    expect(
      evaluateBooleanCondition(
        condition,
        EvaluationContext(
          contextState: {
            'twitch': {'viewers': 12},
          },
        ),
      ),
      isTrue,
    );
  });

  late DartPluginRegistry registry;
  late DartProfileRuntime runtime;
  late StreamController<RuntimeMap> events;
  late List<Object?> calls;
  setUp(() {
    calls = [];
    events = StreamController<RuntimeMap>.broadcast();
    registry = DartPluginRegistry()
      ..register(
        DartPluginManifest(
          id: PluginId('test'),
          name: 'Test',
          states: [
            const StateSpec(
              id: StateId('enabled'),
              displayName: 'Enabled',
              initialValue: false,
            ),
          ],
          actions: [
            ActionSpec<RuntimeMap, Object?>(
              pluginId: PluginId('test'),
              actionId: ActionId('record'),
              invoke: (config, context) async {
                calls.add(config['value'] ?? context.contextState['message']);
                return config;
              },
            ),
          ],
          triggers: [
            TriggerSpec<RuntimeMap, RuntimeMap>(
              pluginId: PluginId('test'),
              triggerId: TriggerId('chat'),
              displayName: 'Chat',
              listen: () => events.stream,
            ),
          ],
        ),
      )
      ..register(createShowRunnerPlugin());
    runtime = DartProfileRuntime(registry: registry);
  });
  tearDown(() async {
    await runtime.dispose();
    await events.close();
    await registry.close();
  });

  test(
    'runs activation and deactivation automations on condition transitions',
    () async {
      final profile = profileFixture(
        activation: automationFixture(
          nodes: [
            actionFixture('on', config: {'value': 'on'}),
          ],
          entryNodeId: 'on',
        ),
        deactivation: automationFixture(
          nodes: [
            actionFixture('off', config: {'value': 'off'}),
          ],
          entryNodeId: 'off',
        ),
        condition: {
          'type': 'value',
          'operator': 'equal',
          'lhs': {'type': 'state', 'plugin': 'test', 'state': 'enabled'},
          'rhs': {'type': 'value', 'value': true},
        },
      );
      registry.updateState('test', 'enabled', true);
      await runtime.reconcile('p', profile);
      expect(runtime.isActive('p'), true);
      registry.updateState('test', 'enabled', false);
      await runtime.reconcile('p', profile);
      expect(runtime.isActive('p'), false);
      expect(calls, ['on', 'off']);
    },
  );
  test(
    'routes active trigger events to their actual trigger node and payload',
    () async {
      final profile = profileFixture(
        events: [
          eventFixture(
            id: 'event',
            nodes: [actionFixture('record')],
            next: 'record',
          ),
        ],
      );
      expect(
        await runtime.handleTrigger('p', profile, 'test', 'chat', {
          'message': 'ignored',
        }),
        isNull,
      );
      await runtime.activate('p', profile);
      await runtime.handleTrigger('p', profile, 'test', 'chat', {
        'message': 'hello',
      });
      expect(calls, ['hello']);
    },
  );
  test(
    'queues a profile trigger with its entry override and unchanged canonical envelope',
    () async {
      final queue = DartActionQueue()..setPaused(true);
      final manager = DartAutomationQueueManager(
        defaultQueue: DartActionQueue(),
        execute: (document, context, item) =>
            CompiledExecutionEngine().executeWithRegistry(
              automation: document,
              context: context,
              registry: registry,
              entryNodeId: item.source['entryNodeId'] as String?,
            ),
      )..register('alerts', queue);
      addTearDown(manager.dispose);
      runtime = DartProfileRuntime(registry: registry, queueManager: manager);
      final document = eventFixture(
        id: 'event',
        nodes: [actionFixture('record')],
        next: 'record',
        queue: 'alerts',
      );
      final profile = profileFixture(events: [document]);
      await runtime.activate('p', profile);
      await runtime.handleTrigger('p', profile, 'test', 'chat', {
        'message': 'queued',
      });
      expect(queue.pending, hasLength(1));
      expect(queue.pending.single.source['automation'], document.toJson());
      expect(queue.pending.single.source['entryNodeId'], 'event');
      expect(calls, isEmpty);
      queue.setPaused(false);
      await manager.drain('alerts');
      expect(calls, ['queued']);
    },
  );
  test(
    'multiple trigger nodes enter their own branch in one document',
    () async {
      final document = automationFixture(
        entryNodeId: 'left',
        nodes: [
          GraphNode(id: 'left', type: triggerNodeType('test', 'chat')),
          GraphNode(id: 'right', type: triggerNodeType('test', 'chat')),
          actionFixture('a', config: {'value': 'left'}),
          actionFixture('b', config: {'value': 'right'}),
        ],
        connections: [
          controlFixture('left-a', 'left', 'a'),
          controlFixture('right-b', 'right', 'b'),
        ],
      );
      final profile = profileFixture(events: [document]);
      await runtime.activate('p', profile);
      final session = runtime.watch('p', profile);
      addTearDown(session.dispose);
      events.add({});
      await flushEvents();
      expect(calls, ['left', 'right']);
    },
  );
  test(
    'watch subscribes to repeated event targets and disposes subscriptions',
    () async {
      final profile = profileFixture(
        events: [
          eventFixture(
            id: 'first',
            nodes: [
              actionFixture('a', config: {'value': 'first'}),
            ],
            next: 'a',
          ),
          eventFixture(
            id: 'second',
            nodes: [
              actionFixture('b', config: {'value': 'second'}),
            ],
            next: 'b',
          ),
        ],
      );
      await runtime.activate('p', profile);
      final session = runtime.watch('p', profile);
      events.add({});
      await flushEvents();
      expect(calls, ['first', 'second']);
      await session.dispose();
      events.add({});
      await flushEvents();
      expect(calls, ['first', 'second']);
    },
  );
  test('stop propagation belongs to the source node', () async {
    final profile = profileFixture(
      events: [
        eventFixture(
          id: 'first',
          nodes: [
            actionFixture('a', config: {'value': 'first'}),
          ],
          next: 'a',
          stop: true,
        ),
        eventFixture(
          id: 'second',
          nodes: [
            actionFixture('b', config: {'value': 'second'}),
          ],
          next: 'b',
        ),
      ],
    );
    await runtime.activate('p', profile);
    final session = runtime.watch('p', profile);
    addTearDown(session.dispose);
    events.add({});
    await flushEvents();
    expect(calls, ['first']);
  });
  test(
    'autoRun and condition triggers react to registry state changes',
    () async {
      final profile = profileFixture(
        events: [
          eventFixture(
            id: 'auto',
            plugin: 'ShowRunner',
            trigger: 'autoRun',
            nodes: [
              actionFixture('a', config: {'value': 'auto'}),
            ],
            next: 'a',
          ),
          eventFixture(
            id: 'condition',
            plugin: 'ShowRunner',
            trigger: 'condition',
            config: {
              'condition': {
                'type': 'value',
                'operator': 'equal',
                'lhs': {'type': 'state', 'plugin': 'test', 'state': 'enabled'},
                'rhs': {'type': 'value', 'value': true},
              },
              'runImmediately': false,
            },
            nodes: [
              actionFixture('b', config: {'value': 'condition'}),
            ],
            next: 'b',
          ),
        ],
      );
      await runtime.activate('p', profile);
      final session = runtime.watch('p', profile);
      addTearDown(session.dispose);
      await flushEvents();
      expect(calls, ['auto']);
      registry.updateState('test', 'enabled', true);
      await flushEvents();
      expect(calls, ['auto', 'auto', 'condition']);
    },
  );
}

ShowRunnerProfile profileFixture({
  AutomationDocument? activation,
  AutomationDocument? deactivation,
  List<AutomationDocument> events = const [],
  RuntimeMap condition = const {},
}) => ShowRunnerProfile(
  name: 'Test',
  activationMode: condition.isEmpty ? 'always' : 'conditional',
  triggers: [
    for (final (index, document) in events.indexed)
      {'id': 'event-$index', 'automation': document.toJson()},
  ],
  activationCondition: condition,
  activationAutomation: activation ?? AutomationDocument.empty(),
  deactivationAutomation: deactivation ?? AutomationDocument.empty(),
);
Future<void> flushEvents() async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
