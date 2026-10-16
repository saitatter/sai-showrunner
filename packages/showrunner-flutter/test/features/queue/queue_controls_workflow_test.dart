import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/features/queue/queue_workspace.dart';
import 'package:showrunner_flutter/persistence/queue_config_repository.dart';
import 'package:showrunner_flutter/runtime/action_queue.dart';
import 'package:showrunner_flutter/runtime/automation_queue_manager.dart';
import 'package:showrunner_flutter/schema/queue.dart';
import 'package:showrunner_flutter/schema/automation.dart';
import 'package:showrunner_flutter/runtime/expression.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';

void main() {
  testWidgets(
    'new queue controls operate on that queue rather than the previous selection',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('showrunner-queue-ui-'),
      ))!;
      addTearDown(() => root.delete(recursive: true));
      final repository = QueueConfigRepository(
        Directory('${root.path}/queues'),
      );
      await tester.runAsync(
        () => repository.save(
          'old.yaml',
          const QueueConfig(name: 'Old queue', paused: true),
        ),
      );
      final defaultQueue = DartActionQueue();
      final manager = DartAutomationQueueManager(
        defaultQueue: defaultQueue,
        execute: (_, _, _) async => null,
        loadConfig: (key) =>
            repository.load(File('${root.path}/queues/$key.yaml')),
      );
      addTearDown(manager.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QueueWorkspace(
              dataService: ShowRunnerDataService(root),
              queue: defaultQueue,
              queueManager: manager,
            ),
          ),
        ),
      );
      await _until(tester, find.text('Old queue'));
      final old = manager.registeredQueue('old.yaml')!;
      old.enqueue({'name': 'Old queued action'}, {});
      await tester.tap(find.text('Create Queue'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == 'Name',
        ),
        'New queue',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await _until(
        tester,
        find.descendant(
          of: find.byType(DataTable),
          matching: find.text('New queue'),
        ),
      );
      final entries = (await tester.runAsync(repository.list))!;
      final newKey = entries
          .singleWhere((e) => e.config?.name == 'New queue')
          .fileName;
      final created = manager.registeredQueue(newKey)!;
      await tester.tap(find.byTooltip('Open runtime queue'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Old queued action'),
        ),
        findsNothing,
      );
      expect(find.text('Queue is empty'), findsOneWidget);
      await tester.tap(find.byTooltip('Pause queue'));
      await tester.pumpAndSettle();
      expect(created.paused, true);
      expect(old.paused, true);
      expect(old.pending, hasLength(1));
      await manager.enqueue(
        const AutomationData(extra: {'name': 'Run after resume'}),
        EvaluationContext(),
        queueId: newKey,
      );
      await manager.drain(newKey);
      expect(created.pending, hasLength(1));
      await tester.tap(find.byTooltip('Resume queue'));
      await tester.pumpAndSettle();
      expect(created.history.single.status, 'completed');
      expect(created.pending, isEmpty);
      expect(old.pending, hasLength(1));
      await tester.tap(find.byTooltip('Replay'));
      await tester.pumpAndSettle();
      expect(created.history, hasLength(2));
      expect(created.history.every((item) => item.status == 'completed'), true);
    },
  );
}

Future<void> _until(WidgetTester tester, Finder target) async {
  for (var i = 0; i < 200; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    if (target.evaluate().isNotEmpty) return;
  }
  throw TestFailure(
    'Missing $target; visible text: ${tester.widgetList<Text>(find.byType(Text)).map((w) => w.data).toList()}',
  );
}
