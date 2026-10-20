import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/plugins/stream_plans/manifest.dart';
import 'package:showrunner_flutter/runtime/cancellation.dart';
import 'package:showrunner_flutter/runtime/expression.dart';
import 'package:showrunner_flutter/schema/stream_plan.dart';
import '../../support/graph_fixtures.dart';

void main() {
  test(
    'component rollback retains both activation and cleanup failures',
    () async {
      final registry = DartPluginRegistry();
      addTearDown(registry.close);
      final runtime = DartStreamPlanRuntime();
      addTearDown(runtime.close);
      final activation = StateError('activation failed');
      final cleanup = StateError('cleanup failed');
      runtime.registerComponentType(
        DartStreamPlanComponent(
          id: 'failed',
          onActivate: (_, _) => throw activation,
          onDeactivate: (_, _) => throw cleanup,
        ),
      );
      await expectLater(
        runtime.activatePlan(
          'p',
          _plan(
            segments: [
              _segment('one', components: {'failed': {}}),
            ],
          ),
          registry: registry,
        ),
        throwsA(
          isA<StreamPlanCleanupFailure>()
              .having(
                (failure) => failure.cause,
                'original error',
                same(activation),
              )
              .having((failure) => failure.cleanupErrors, 'cleanup errors', [
                cleanup,
              ]),
        ),
      );
      expect(runtime.isActive, isFalse);
    },
  );
  late DartPluginRegistry registry;
  late DartStreamPlanRuntime runtime;
  late Future<Object?> Function(RuntimeMap, EvaluationContext) action;
  setUp(() {
    action = (_, _) async => null;
    registry = DartPluginRegistry()
      ..register(
        DartPluginManifest(
          id: const PluginId('test'),
          name: 'Test',
          actions: [
            ActionSpec<RuntimeMap, Object?>(
              pluginId: const PluginId('test'),
              actionId: const ActionId('record'),
              invoke: (config, context) => action(config, context),
            ),
          ],
        ),
      );
    runtime = DartStreamPlanRuntime();
  });
  tearDown(() async {
    await runtime.close();
    await registry.close();
  });

  test(
    'close cancels active graph and rejects transitions already waiting',
    () async {
      final entered = Completer<void>();
      var starts = 0;
      action = (_, context) async {
        starts++;
        entered.complete();
        await context.cancellationToken!.whenCancelled;
        return null;
      };
      final plan = _plan(
        activation: _automation('start'),
        segments: [_segment('one'), _segment('two')],
      );
      final activating = expectLater(
        runtime.activatePlan('p', plan, registry: registry),
        throwsA(isA<DartCancelledException>()),
      );
      await entered.future;
      final waiting = expectLater(
        runtime.transitionToNextSegment('p', plan, registry: registry),
        throwsStateError,
      );
      await runtime.close(registry: registry);
      await Future.wait([activating, waiting]);
      expect(starts, 1);
      expect(runtime.isActive, isFalse);
      expect(runtime.activeSegmentId, isNull);
      expect(() => runtime.activate('late'), throwsStateError);
    },
  );

  test(
    'failed segment activation releases reached components in reverse order',
    () async {
      final calls = <String>[];
      final error = StateError('activation failed');
      action = (_, _) async => throw error;
      for (final id in ['a', 'b']) {
        runtime.registerComponentType(
          DartStreamPlanComponent(
            id: id,
            onActivate: (_, _) => calls.add('$id:on'),
            onDeactivate: (_, _) => calls.add('$id:off'),
          ),
        );
      }
      final plan = _plan(
        segments: [
          _segment('one'),
          _segment(
            'two',
            activation: _automation('fail'),
            components: {'a': {}, 'b': {}},
          ),
        ],
      );
      await runtime.activatePlan('p', plan, registry: registry);
      await expectLater(
        runtime.activatePlanSegment('p', plan, 'two', registry: registry),
        throwsA(same(error)),
      );
      expect(calls, ['a:on', 'b:on', 'b:off', 'a:off']);
      expect(runtime.activePlanId, 'p');
      expect(runtime.activeSegmentId, isNull);
      expect(runtime.lastTransitionError, same(error));
      await runtime.close(registry: registry);
      expect(calls, ['a:on', 'b:on', 'b:off', 'a:off']);
    },
  );

  test(
    'failed plan activation clears provisional active state without retry',
    () async {
      var starts = 0;
      final error = StateError('failed plan');
      action = (_, _) async {
        starts++;
        throw error;
      };
      await expectLater(
        runtime.activatePlan(
          'p',
          _plan(activation: _automation('fail')),
          registry: registry,
        ),
        throwsA(same(error)),
      );
      expect(runtime.activePlan, isNull);
      expect(runtime.isActive, isFalse);
      expect(runtime.lastTransitionError, same(error));
      expect(starts, 1);
    },
  );

  test(
    'exit attempts remaining components and plan hook after cleanup failure',
    () async {
      final calls = <String>[];
      final error = StateError('component cleanup failed');
      action = (config, _) async {
        calls.add('${config['phase']}');
        return null;
      };
      runtime.registerComponentType(
        DartStreamPlanComponent(
          id: 'a',
          onDeactivate: (_, _) {
            calls.add('a:off');
            throw error;
          },
        ),
      );
      runtime.registerComponentType(
        DartStreamPlanComponent(
          id: 'b',
          onDeactivate: (_, _) => calls.add('b:off'),
        ),
      );
      final plan = _plan(
        deactivation: _automation('plan:off'),
        segments: [
          _segment('one', components: {'a': {}, 'b': {}}),
        ],
      );
      await runtime.activatePlan('p', plan, registry: registry);
      await expectLater(
        runtime.deactivatePlan(registry: registry),
        throwsA(same(error)),
      );
      expect(calls, ['a:off', 'b:off', 'plan:off']);
      expect(runtime.isActive, isFalse);
      expect(runtime.activeSegmentId, isNull);
      await runtime.close(registry: registry);
      expect(calls, ['a:off', 'b:off', 'plan:off']);
    },
  );
}

Map<String, dynamic> _automation(String phase) => automationFixture(
  nodes: [
    actionFixture('a', config: {'phase': phase}),
  ],
  entryNodeId: 'a',
).toJson();
StreamPlanData _plan({
  Map<String, dynamic>? activation,
  Map<String, dynamic>? deactivation,
  List<StreamPlanSegmentData> segments = const [],
}) => StreamPlanData(
  name: 'Lifecycle',
  activationAutomation: activation ?? emptyInlineAutomation(),
  deactivationAutomation: deactivation ?? emptyInlineAutomation(),
  segments: segments,
);
StreamPlanSegmentData _segment(
  String id, {
  Map<String, dynamic>? activation,
  Map<String, dynamic> components = const {},
}) => StreamPlanSegmentData(
  id: id,
  name: id,
  components: components,
  activationAutomation: activation ?? emptyInlineAutomation(),
  deactivationAutomation: emptyInlineAutomation(),
);
