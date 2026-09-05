import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/runtime/action_queue.dart';
import 'package:showrunner_flutter/runtime/automation_queue_manager.dart';
import 'package:showrunner_flutter/runtime/expression.dart';
import 'package:showrunner_flutter/schema/automation.dart';

void main() {
  test(
    'keeps independent resource queues and preserves runtime context',
    () async {
      final defaultQueue = DartActionQueue();
      final alertsQueue = DartActionQueue(
        defaultTimeout: const Duration(seconds: 1),
      )..setPaused(true);
      final executions = <String>[];
      final contexts = <EvaluationContext>[];
      final manager = DartAutomationQueueManager(
        defaultQueue: defaultQueue,
        execute: (automation, context, item) async {
          executions.add(item.source['name'].toString());
          contexts.add(context);
          return null;
        },
      )..register('alerts', alertsQueue);
      addTearDown(manager.dispose);

      final automation = AutomationData(extra: const {'name': 'Alert'});
      await manager.enqueue(
        automation,
        EvaluationContext(
          locals: {'viewer': 'saita'},
          contextState: {
            'event': {'message': 'hello'},
          },
        ),
        queueId: 'alerts.yaml',
      );

      expect(alertsQueue.pending, hasLength(1));
      expect(defaultQueue.pending, isEmpty);
      expect(executions, isEmpty);

      alertsQueue.setPaused(false);
      await manager.drain('alerts');

      expect(executions, ['Alert']);
      expect(contexts.single.locals, {'viewer': 'saita'});
      expect(contexts.single.contextState, {
        'event': {'message': 'hello'},
      });
      expect(alertsQueue.history.single.status, 'completed');
    },
  );

  test('continues with the next item after an execution failure', () async {
    final queue = DartActionQueue();
    final manager = DartAutomationQueueManager(
      defaultQueue: queue,
      execute: (automation, context, item) async {
        if (item.source['name'] == 'bad') throw StateError('broken');
        return null;
      },
    );
    addTearDown(manager.dispose);

    await manager.enqueue(
      AutomationData(extra: const {'name': 'bad'}),
      EvaluationContext(),
    );
    await manager.enqueue(
      AutomationData(extra: const {'name': 'good'}),
      EvaluationContext(),
    );
    await manager.drain(null);

    expect(queue.history.map((item) => item.status), ['completed', 'failed']);
  });
}
