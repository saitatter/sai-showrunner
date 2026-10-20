import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/plugins/stream_plans/manifest.dart';
import 'package:showrunner_flutter/plugins/stream_plans/contracts.dart';
import 'package:showrunner_flutter/runtime/action_queue.dart';
import 'package:showrunner_flutter/runtime/automation_queue_manager.dart';
import 'package:showrunner_flutter/schema/json.dart';
import '../../support/graph_fixtures.dart';
import 'package:showrunner_flutter/schema/stream_plan.dart';

void main() {
  test(
    'editing active components activates additions and cleans up removals',
    () async {
      final registry = DartPluginRegistry();
      addTearDown(registry.close);
      final runtime = DartStreamPlanRuntime();
      addTearDown(runtime.dispose);
      final calls = <String>[];
      for (final id in ['a', 'b']) {
        runtime.registerComponentType(
          DartStreamPlanComponent(
            id: id,
            onActivate: (segment, config) => calls.add('$id:on'),
            onDeactivate: (segment, config) => calls.add('$id:off'),
            activeConfigChanged: (segment, config) => calls.add('$id:update'),
          ),
        );
      }
      StreamPlanData plan(String component) => StreamPlanData(
        name: 'Editable',
        activationAutomation: emptyInlineAutomation(),
        deactivationAutomation: emptyInlineAutomation(),
        segments: [
          _segment(
            'one',
            components: {
              component: {'enabled': true},
            },
          ),
        ],
      );
      await runtime.activatePlan('plan', plan('a'), registry: registry);
      await runtime.updateActivePlan('plan', plan('a'));
      await runtime.updateActivePlan('plan', plan('b'));
      await runtime.deactivatePlan(registry: registry);
      expect(calls, ['a:on', 'a:update', 'a:off', 'b:on', 'b:off']);
    },
  );
  test('rapid navigation executes each transition once in order', () async {
    final registry = DartPluginRegistry();
    addTearDown(registry.close);
    final runtime = DartStreamPlanRuntime();
    addTearDown(runtime.dispose);
    final activated = <String>[];
    runtime.registerComponentType(
      DartStreamPlanComponent(
        id: 'slow',
        onActivate: (id, config) async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          activated.add(id);
        },
      ),
    );
    final plan = StreamPlanData(
      name: 'Rapid navigation',
      activationAutomation: emptyInlineAutomation(),
      deactivationAutomation: emptyInlineAutomation(),
      segments: [
        for (final id in ['one', 'two', 'three', 'four'])
          _segment(id, components: {'slow': {}}),
      ],
    );
    await runtime.activatePlan('probe', plan, registry: registry);
    final results = await Future.wait(
      List.generate(
        3,
        (_) =>
            runtime.transitionToNextSegment('probe', plan, registry: registry),
      ),
    );
    expect(results, ['two', 'three', 'four']);
    expect(activated, ['one', 'two', 'three', 'four']);
    expect(runtime.activeSegmentId, 'four');
    await runtime.deactivatePlan(registry: registry);
  });
  test('round-trips Stream Plan config with default values', () {
    final plan = StreamPlanData.fromConfig({
      'name': 'Friday show',
      'segments': [
        {
          'id': 'intro',
          'name': 'Intro',
          'components': {
            'twitch-stream-info': {
              'title': 'Welcome',
              'category': 'Just Chatting',
            },
          },
        },
      ],
    });

    expect(plan.name, 'Friday show');
    expect(plan.segments, hasLength(1));
    expect(plan.segments.single.activationAutomation['schemaVersion'], 1);
    expect(plan.segments.single.components['twitch-stream-info'], isNotNull);

    final restored = StreamPlanData.fromConfig(plan.toConfig());
    expect(restored.segments.single.id, 'intro');
    expect(restored.segments.single.name, 'Intro');
    expect(restored.segments.single.components['twitch-stream-info'], {
      'title': 'Welcome',
      'category': 'Just Chatting',
    });
  });

  test('moves the active plan between ordered segments', () {
    final plan = StreamPlanData(
      name: 'Show',
      activationAutomation: emptyInlineAutomation(),
      deactivationAutomation: emptyInlineAutomation(),
      segments: [_segment('one'), _segment('two'), _segment('three')],
    );
    final runtime = DartStreamPlanRuntime()
      ..activate('plan-1', segmentId: 'two');

    expect(runtime.next(plan), 'three');
    expect(runtime.previous(plan), 'two');
    expect(runtime.previous(plan), 'one');
    expect(runtime.previous(plan), isNull);
  });

  test('registers Stream Plan navigation actions', () async {
    final runtime = DartStreamPlanRuntime();
    final registry = DartPluginRegistry()
      ..register(createStreamPlansPlugin(runtime: runtime));

    expect(registry.findAction('stream-plans', 'nextSegment'), isNotNull);
    expect(registry.findAction('stream-plans', 'prevSegment'), isNotNull);
    expect(
      registry.findAction('stream-plans', 'nextSegment')?.decodeConfig({}),
      isA<StreamPlanNavigationConfig>(),
    );
    runtime.activate('plan-1', segmentId: 'one');
    const segments = [
      {'id': 'one', 'name': 'One'},
      {'id': 'two', 'name': 'Two'},
    ];
    final result = await registry.invokeAction('stream-plans', 'nextSegment', {
      'segments': segments,
    });
    expect((result as Map)['action'], 'nextSegment');
    expect(result['segmentId'], 'two');
    runtime.deactivate();
  });

  test('executes plan and segment transitions in configured order', () async {
    final events = <String>[];
    final registry = DartPluginRegistry()
      ..register(
        DartPluginManifest(
          id: PluginId('test'),
          name: 'Test',
          actions: [
            ActionSpec<Map<String, dynamic>, Object?>(
              pluginId: PluginId('test'),
              actionId: ActionId('record'),
              invoke: (config, context) async {
                events.add(config['value'].toString());
                return null;
              },
            ),
          ],
        ),
      );
    addTearDown(registry.close);
    final runtime = DartStreamPlanRuntime();
    runtime.registerComponentType(
      DartStreamPlanComponent(
        id: 'component',
        onActivate: (segmentId, config) {
          events.add('component:$segmentId:activate');
        },
        onDeactivate: (segmentId, config) {
          events.add('component:$segmentId:deactivate');
        },
      ),
    );
    final plan = StreamPlanData(
      name: 'Show',
      activationAutomation: _automation('plan:activate'),
      deactivationAutomation: _automation('plan:deactivate'),
      segments: [
        _segment(
          'one',
          activation: 'one:activate',
          deactivation: 'one:deactivate',
          components: const {
            'component': {'enabled': true},
          },
        ),
        _segment(
          'two',
          activation: 'two:activate',
          deactivation: 'two:deactivate',
        ),
      ],
    );

    await runtime.activatePlan('plan-1', plan, registry: registry);
    await runtime.activatePlanSegment(
      'plan-1',
      plan,
      'two',
      registry: registry,
    );
    await runtime.deactivatePlan(registry: registry);

    expect(events, [
      'plan:activate',
      'component:one:activate',
      'one:activate',
      'component:one:deactivate',
      'one:deactivate',
      'two:activate',
      'two:deactivate',
      'plan:deactivate',
    ]);
    expect(runtime.activePlanId, isNull);
    expect(runtime.activeSegmentId, isNull);
  });

  test('navigation actions run the active segment transition', () async {
    final runtime = DartStreamPlanRuntime();
    final registry = DartPluginRegistry();
    registry.register(
      createStreamPlansPlugin(runtime: runtime, registry: registry),
    );
    addTearDown(registry.close);
    final plan = StreamPlanData(
      name: 'Show',
      activationAutomation: emptyInlineAutomation(),
      deactivationAutomation: emptyInlineAutomation(),
      segments: [_segment('one'), _segment('two')],
    );

    await runtime.activatePlan('plan-1', plan, registry: registry);
    final result = await registry.invokeAction('stream-plans', 'nextSegment', {
      'planId': 'plan-1',
      'segments': plan.segments.map((segment) => segment.toJson()).toList(),
    });

    expect((result as Map)['segmentId'], 'two');
    expect(runtime.activeSegmentId, 'two');
    await runtime.deactivatePlan(registry: registry);
  });

  test(
    'navigation actions use the active plan for empty action configs',
    () async {
      final runtime = DartStreamPlanRuntime();
      final registry = DartPluginRegistry();
      registry.register(
        createStreamPlansPlugin(runtime: runtime, registry: registry),
      );
      addTearDown(registry.close);
      final plan = StreamPlanData(
        name: 'Show',
        activationAutomation: emptyInlineAutomation(),
        deactivationAutomation: emptyInlineAutomation(),
        segments: [_segment('one'), _segment('two')],
      );

      await runtime.activatePlan('plan-1', plan, registry: registry);
      final result = await registry.invokeAction(
        'stream-plans',
        'nextSegment',
        const <String, dynamic>{},
      );

      expect((result as Map)['segmentId'], 'two');
      expect(runtime.activeSegmentId, 'two');
      await runtime.deactivatePlan(registry: registry);
    },
  );

  test('queues inline stream-plan automations with source metadata', () async {
    final queue = DartActionQueue()..setPaused(true);
    final queueManager = DartAutomationQueueManager(
      defaultQueue: queue,
      execute: (automation, context, item) async => null,
    );
    addTearDown(queueManager.dispose);
    final runtime = DartStreamPlanRuntime(queueManager: queueManager);
    final registry = DartPluginRegistry()
      ..register(
        DartPluginManifest(
          id: const PluginId('test'),
          name: 'Test',
          actions: [
            ActionSpec<Map<String, dynamic>, Object?>(
              pluginId: const PluginId('test'),
              actionId: const ActionId('record'),
              invoke: (_, _) async => null,
            ),
          ],
        ),
      );
    addTearDown(registry.close);
    final plan = StreamPlanData(
      name: 'Show',
      activationAutomation: AutomationDocument.fromJson(
        _automation('plan:activate'),
      ).withSettings({'entryNodeId': 'record', 'queue': 'default'}).toJson(),
      deactivationAutomation: emptyInlineAutomation(),
      segments: const [],
    );

    await runtime.activatePlan('plan-1', plan, registry: registry);

    expect(queue.pending, hasLength(1));
    expect(queue.pending.single.source['sourceType'], 'stream-plan');
    expect(queue.pending.single.source['sourceId'], 'plan-1');
    expect(queue.pending.single.source['sourceSubId'], 'activation');
    expect(queue.pending.single.contextState['streamPlan.planId'], 'plan-1');
  });
}

StreamPlanSegmentData _segment(
  String id, {
  String? activation,
  String? deactivation,
  JsonMap components = const {},
}) => StreamPlanSegmentData(
  id: id,
  name: id,
  components: components,
  activationAutomation: activation == null
      ? emptyInlineAutomation()
      : _automation(activation),
  deactivationAutomation: deactivation == null
      ? emptyInlineAutomation()
      : _automation(deactivation),
);

JsonMap _automation(String value) => automationFixture(
  nodes: [
    actionFixture('record', config: {'value': value}),
  ],
  entryNodeId: 'record',
).toJson();
