import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/features/queue/queue_workspace.dart';
import 'package:showrunner_flutter/runtime/action_queue.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';

void main() {
  testWidgets('exposes skip control for pending queue work', (tester) async {
    final directory = await tester.runAsync(
      () => Directory.systemTemp.createTemp('showrunner-queue-widget-fixture-'),
    );
    if (directory == null) throw StateError('Could not create test directory.');
    final queue = DartActionQueue();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await queue.dispose();
      await directory.delete(recursive: true);
    });
    queue.enqueue({'name': 'Alert'}, {});

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QueueWorkspace(
            dataService: ShowRunnerDataService(directory),
            queue: queue,
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byTooltip('Open runtime queue'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byTooltip('Skip'), findsOneWidget);
    await tester.tap(find.byTooltip('Skip'));
    await tester.pump();

    expect(queue.pending, isEmpty);
    expect(queue.history.single.status, 'skipped');
    expect(queue.history.single.reason, 'Skipped by operator');
  });

  testWidgets('shows a parity queue table and creates queues by name', (
    tester,
  ) async {
    final directory = await tester.runAsync(
      () => Directory.systemTemp.createTemp('showrunner-queue-table-fixture-'),
    );
    if (directory == null) throw StateError('Could not create test directory.');
    final queue = DartActionQueue();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await queue.dispose();
      await directory.delete(recursive: true);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QueueWorkspace(
            dataService: ShowRunnerDataService(directory),
            queue: queue,
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 100));

    for (final heading in const [
      'Status',
      'Name',
      'Current Item',
      'Pending',
      'Recent',
      'Next Automation',
    ]) {
      expect(find.text(heading), findsOneWidget);
    }
    expect(find.text('No queues configured'), findsNothing);
    expect(find.text('Runtime queue'), findsNothing);
  });
}
