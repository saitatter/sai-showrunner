import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/runtime/action_queue.dart';
import 'package:showrunner_flutter/runtime/automation_queue_manager.dart';
import 'package:showrunner_flutter/runtime/expression.dart';
import '../support/graph_fixtures.dart';

void main() {
  test(
    'concurrent drains await the same execution through queue lookup',
    () async {
      final entered = Completer<void>();
      final finish = Completer<void>();
      final queue = DartActionQueue()..setPaused(true);
      var executions = 0;
      final manager = DartAutomationQueueManager(
        defaultQueue: queue,
        execute: (_, _, _) async {
          executions++;
          entered.complete();
          await finish.future;
          return null;
        },
      );
      addTearDown(manager.dispose);
      await manager.enqueue(AutomationDocument.empty(), EvaluationContext());
      queue.setPaused(false);
      var completed = 0;
      final drains = List.generate(
        10,
        (_) => manager.drain(null).then((_) => completed++),
      );
      await entered.future;
      await Future<void>.delayed(Duration.zero);
      expect(completed, 0);
      expect(executions, 1);
      finish.complete();
      await Future.wait(drains);
      expect(completed, 10);
      expect(queue.history, hasLength(1));
    },
  );
  testWidgets('shutdown cancels queue gap timers and preserves pending work', (
    tester,
  ) async {
    final queue = DartActionQueue(defaultGap: const Duration(hours: 1))
      ..setPaused(true);
    final manager = DartAutomationQueueManager(
      defaultQueue: queue,
      execute: (_, _, _) async => null,
    );
    for (var i = 0; i < 2; i++) {
      await manager.enqueue(AutomationDocument.empty(), EvaluationContext());
    }
    queue.setPaused(false);
    final draining = manager.drain(null);
    await tester.pump();
    expect(queue.history, hasLength(1));
    expect(queue.pending, hasLength(1));
    await manager.dispose();
    await draining;
    expect(queue.pending, hasLength(1));
    // The widget-test binding also fails if the hour-long timer remains live.
  });
  test(
    'shutdown cancels and awaits the active action before closing queue sinks',
    () async {
      final entered = Completer<void>();
      var actionStopped = false;
      final manager = DartAutomationQueueManager(
        defaultQueue: DartActionQueue(),
        execute: (_, context, _) async {
          entered.complete();
          await context.cancellationToken!.whenCancelled;
          actionStopped = true;
          return null;
        },
      );
      final item = await manager.enqueue(
        AutomationDocument.empty(),
        EvaluationContext(),
      );
      await entered.future;
      await Future.wait([manager.dispose(), manager.dispose()]);
      expect(actionStopped, true);
      expect(item.status, 'cancelled');
    },
  );
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

      final automation = AutomationDocument.empty().withMetadata({
        'name': 'Alert',
      });
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
      AutomationDocument.empty().withMetadata({'name': 'bad'}),
      EvaluationContext(),
    );
    await manager.enqueue(
      AutomationDocument.empty().withMetadata({'name': 'good'}),
      EvaluationContext(),
    );
    await manager.drain(null);

    expect(queue.history.map((item) => item.status), ['completed', 'failed']);
  });
}
