import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/plugins/stream_plans/manifest.dart';
import 'package:showrunner_flutter/runtime/action_queue.dart';
import 'package:showrunner_flutter/runtime/automation_queue_manager.dart';
import 'package:showrunner_flutter/schema/automation.dart';
import 'package:showrunner_flutter/schema/stream_plan.dart';

void main() {
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
    expect(plan.segments.single.activationAutomation['schemaVersion'], 2);
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
    final registry = DartPluginRegistry()..register(createStreamPlansPlugin());

    expect(registry.findAction('stream-plans', 'nextSegment'), isNotNull);
    expect(registry.findAction('stream-plans', 'prevSegment'), isNotNull);
    streamPlanRuntime.activate('plan-1', segmentId: 'one');
    const segments = [
      {'id': 'one', 'name': 'One'},
      {'id': 'two', 'name': 'Two'},
    ];
    final result = await registry.invokeAction('stream-plans', 'nextSegment', {
      'segments': segments,
    });
    expect((result as Map)['action'], 'nextSegment');
    expect(result['segmentId'], 'two');
    streamPlanRuntime.deactivate();
  });

  test('executes plan and segment transitions in configured order', () async {
    final events = <String>[];
    final registry = DartPluginRegistry()
      ..register(
        DartPluginManifest(
          id: 'test',
          name: 'Test',
          actions: [
            DartActionDefinition(
              pluginId: 'test',
              actionId: 'record',
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
    final registry = DartPluginRegistry();
    addTearDown(registry.close);
    final plan = StreamPlanData(
      name: 'Show',
      activationAutomation: {
        ..._automation('plan:activate'),
        'queue': 'default',
      },
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

JsonMap _automation(String value) => AutomationData(
  graph: AutomationGraph(
    nodes: [
      GraphNode(
        id: 'record',
        type: 'action',
        x: 0,
        y: 0,
        data: {
          'plugin': 'test',
          'action': 'record',
          'config': {'value': value},
        },
      ),
    ],
    entryNodeId: 'record',
  ),
).toJson();
