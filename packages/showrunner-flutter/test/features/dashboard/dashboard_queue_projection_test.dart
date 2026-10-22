import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/features/dashboard/queue_dashboard_card.dart';
import 'package:showrunner_flutter/features/dashboard/dashboard_widgets.dart';
import 'package:showrunner_flutter/runtime/action_queue.dart';
import 'package:showrunner_flutter/runtime/automation_queue_manager.dart';

void main() {
  testWidgets(
    'named queue cards use their own queue and observe counter changes',
    (tester) async {
      final fallback = DartActionQueue(),
          a = DartActionQueue(),
          b = DartActionQueue();
      final manager = DartAutomationQueueManager(
        defaultQueue: fallback,
        execute: (_, context, item) async => null,
      );
      manager.register('a.yaml', a);
      manager.register('b.yaml', b);
      a.setPaused(true);
      b.setPaused(true);
      a.enqueue({}, {});
      b.enqueue({}, {});
      b.enqueue({}, {});
      addTearDown(manager.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                QueueDashboardCard(
                  name: 'A',
                  queue: fallback,
                  queueManager: manager,
                  queueId: 'a.yaml',
                  onOpen: () {},
                ),
                QueueDashboardCard(
                  name: 'B',
                  queue: fallback,
                  queueManager: manager,
                  queueId: 'b.yaml',
                  onOpen: () {},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Finder card(String name) => find.ancestor(
        of: find.text(name),
        matching: find.byType(DashboardCard),
      );
      expect(
        find.descendant(of: card('A'), matching: find.text('1')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card('B'), matching: find.text('2')),
        findsOneWidget,
      );
      a.enqueue({}, {});
      await tester.pump();
      await tester.pump();
      expect(
        find.descendant(of: card('A'), matching: find.text('2')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card('B'), matching: find.text('2')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
