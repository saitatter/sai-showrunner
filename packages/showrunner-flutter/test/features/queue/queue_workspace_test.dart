import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/features/queue/queue_workspace.dart';
import 'package:showrunner_flutter/runtime/action_queue.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';

void main() {
  testWidgets('exposes skip control for pending queue work', (tester) async {
    final directory = Directory(
      '${Directory.systemTemp.path}/showrunner-queue-widget-fixture',
    );
    final queue = DartActionQueue();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await queue.dispose();
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

    expect(find.byTooltip('Skip'), findsOneWidget);
    await tester.tap(find.byTooltip('Skip'));
    await tester.pump();

    expect(queue.pending, isEmpty);
    expect(queue.history.single.status, 'skipped');
    expect(queue.history.single.reason, 'Skipped by operator');
  });
}
