import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/runtime/cancellation.dart';
import 'package:showrunner_flutter/runtime/expression.dart';
import 'package:showrunner_flutter/runtime/profile_runtime.dart';
import 'package:showrunner_flutter/schema/profile.dart';
import '../support/graph_fixtures.dart';

void main() {
  late StreamController<RuntimeMap> events;
  late DartPluginRegistry registry;
  late DartProfileRuntime runtime;
  late Future<Object?> Function(RuntimeMap, EvaluationContext) action;
  late ShowRunnerProfile profile;
  setUp(() {
    events = StreamController<RuntimeMap>.broadcast();
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
          triggers: [
            TriggerSpec<RuntimeMap, RuntimeMap>(
              pluginId: const PluginId('test'),
              triggerId: const TriggerId('chat'),
              displayName: 'Chat',
              listen: () => events.stream,
            ),
          ],
        ),
      );
    runtime = DartProfileRuntime(registry: registry);
    profile = _profile(
      eventFixture(
        id: 'chat',
        nodes: [actionFixture('record')],
        next: 'record',
      ),
    );
  });
  tearDown(() async {
    await runtime.dispose();
    await events.close();
    await registry.close();
  });

  test(
    'session disposal cancels and awaits direct triggers before detaching ownership',
    () async {
      final entered = Completer<void>(),
          cancelled = Completer<void>(),
          cleaned = Completer<void>();
      var calls = 0;
      action = (_, context) async {
        calls++;
        entered.complete();
        await context.cancellationToken!.whenCancelled;
        cancelled.complete();
        await cleaned.future;
        return null;
      };
      await runtime.activate('p', profile);
      final session = runtime.watch('p', profile);
      events.add({'message': 'start'});
      await entered.future;
      var disposed = false;
      final closing = session.dispose().then((_) => disposed = true);
      await cancelled.future;
      expect(disposed, isFalse);
      cleaned.complete();
      await closing;
      expect(events.hasListener, isFalse);
      events.add({'message': 'late'});
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1);
      expect(runtime.lastTriggerFailure, isNull);
    },
  );

  test(
    'background trigger failures are retained without unhandled futures',
    () async {
      final failed = Completer<ProfileTriggerFailure>();
      runtime = DartProfileRuntime(
        registry: registry,
        onTriggerFailure: failed.complete,
      );
      final error = StateError('fixture action failure');
      action = (_, _) async => throw error;
      await runtime.activate('p', profile);
      runtime.watch('p', profile);
      events.add({'message': 'start'});
      final failure = await failed.future;
      expect(failure.profileId, 'p');
      expect(failure.error, same(error));
      expect(runtime.lastTriggerFailure, same(failure));
      await runtime.dispose();
      expect(events.hasListener, isFalse);
    },
  );

  test(
    'concurrent managed activation executes once and creates one subscriber',
    () async {
      var activations = 0, triggers = 0;
      final triggered = Completer<void>();
      action = (config, _) async {
        if (config['phase'] == 'activation') {
          activations++;
        } else {
          triggers++;
          if (!triggered.isCompleted) triggered.complete();
        }
        return null;
      };
      profile = _profile(
        eventFixture(
          id: 'chat',
          nodes: [actionFixture('record')],
          next: 'record',
        ),
        activation: automationFixture(
          nodes: [
            actionFixture('activate', config: {'phase': 'activation'}),
          ],
          entryNodeId: 'activate',
        ),
      );
      await Future.wait(
        List.generate(
          8,
          (_) => runtime.setManagedActive('p', profile, active: true),
        ),
      );
      events.add({'message': 'once'});
      await triggered.future;
      await Future<void>.delayed(Duration.zero);
      expect(activations, 1);
      expect(triggers, 1);
      expect(runtime.hasManagedSession('p'), isTrue);
    },
  );

  test(
    'overlapping replacements cannot recreate a superseded session',
    () async {
      final entered = Completer<void>(), cleanup = Completer<void>();
      var calls = 0;
      action = (_, context) async {
        if (++calls == 1) {
          entered.complete();
          await context.cancellationToken!.whenCancelled;
          await cleanup.future;
        }
        return null;
      };
      await runtime.setManagedActive('p', profile, active: true);
      events.add({'message': 'first'});
      await entered.future;
      final first = runtime.replaceManagedSession('p', profile);
      final second = runtime.replaceManagedSession('p', profile);
      cleanup.complete();
      await Future.wait([first, second]);
      events.add({'message': 'second'});
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await runtime.dispose();
      expect(calls, 2);
      expect(events.hasListener, isFalse);
    },
  );

  test(
    'host closure cancels activation and prevents a late active profile',
    () async {
      final entered = Completer<void>();
      action = (_, context) async {
        entered.complete();
        await context.cancellationToken!.whenCancelled;
        return null;
      };
      profile = _profile(
        AutomationDocument.empty(),
        activation: automationFixture(
          nodes: [actionFixture('activate')],
          entryNodeId: 'activate',
        ),
      );
      final activating = expectLater(
        runtime.activate('p', profile),
        throwsA(isA<DartCancelledException>()),
      );
      await entered.future;
      await runtime.dispose();
      await activating;
      expect(runtime.isActive('p'), isFalse);
      expect(() => runtime.watch('p', profile), throwsStateError);
    },
  );
}

ShowRunnerProfile _profile(
  AutomationDocument event, {
  AutomationDocument? activation,
}) => ShowRunnerProfile(
  name: 'Lifecycle',
  activationMode: 'manual',
  activationCondition: const {},
  triggers: [
    {'id': 'event', 'automation': event.toJson()},
  ],
  activationAutomation: activation ?? AutomationDocument.empty(),
  deactivationAutomation: AutomationDocument.empty(),
);
