import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/plugins/showrunner/manifest.dart';
import 'package:showrunner_flutter/runtime/action_queue.dart';
import 'package:showrunner_flutter/runtime/automation_queue_manager.dart';
import 'package:showrunner_flutter/schema/automation.dart';

void main() {
  test('queues an automation and emits a filtered start event', () async {
    final queue = DartActionQueue()..setPaused(true);
    final manager = DartAutomationQueueManager(
      defaultQueue: DartActionQueue(),
      execute: (automation, context, item) async => null,
    )..register('alerts', queue);
    addTearDown(manager.dispose);

    final automation = AutomationData(extra: const {'name': 'Alert worker'});
    final registry = DartPluginRegistry()
      ..register(
        createShowRunnerPlugin(
          queueManager: manager,
          loadAutomation: (id) async =>
              id == 'alert-worker' ? automation : null,
        ),
      );
    addTearDown(registry.close);

    final trigger = registry.findTrigger('ShowRunner', 'queueItemStarted')!;
    final started = trigger.listenForConfig!.call({'queue': 'alerts'}).first;
    final result = await registry.invokeAction('ShowRunner', 'addToQueue', {
      'queue': 'alerts',
      'automation': 'alert-worker',
      'payload': {'message': 'Hello'},
    });

    expect(result, {
      'queued': true,
      'queueId': 'alerts',
      'automationId': 'alert-worker',
      'itemId': 'queue-0',
    });
    expect(queue.pending, hasLength(1));
    expect(queue.pending.single.contextState['payload'], {'message': 'Hello'});
    expect(queue.pending.single.source['sourceType'], 'automation');
    expect(queue.pending.single.source['sourceId'], 'alert-worker');

    expect(
      await registry.invokeAction('ShowRunner', 'pause', {
        'queue': 'alerts',
        'paused': false,
      }),
      {'paused': false},
    );
    await manager.drain('alerts');

    expect(await started, {
      'queueId': 'alerts',
      'queueName': 'alerts',
      'itemId': 'queue-0',
      'sourceType': 'automation',
      'sourceId': 'alert-worker',
      'payload': {'message': 'Hello'},
      'queuedAt': isA<String>(),
      'startedAt': isA<String>(),
    });
    expect(queue.history.single.status, 'completed');
  });

  test(
    'queue controls preserve pending items and report completion point',
    () async {
      final queue = DartActionQueue()..setPaused(true);
      final manager = DartAutomationQueueManager(
        defaultQueue: DartActionQueue(),
        execute: (automation, context, item) async => null,
      )..register('alerts', queue);
      addTearDown(manager.dispose);
      final registry = DartPluginRegistry()
        ..register(createShowRunnerPlugin(queueManager: manager));
      addTearDown(registry.close);

      expect(
        await registry.invokeAction('ShowRunner', 'completeQueueItem', {}),
        {'completed': true},
      );
      queue.enqueue({'name': 'pending'}, const {});
      expect(
        await registry.invokeAction('ShowRunner', 'clearQueue', {
          'queue': 'alerts',
        }),
        {'cleared': true},
      );
      expect(queue.pending, isEmpty);
    },
  );
}
