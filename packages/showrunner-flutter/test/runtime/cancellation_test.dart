import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/runtime/cancellation.dart';
import 'package:showrunner_flutter/runtime/expression.dart';
import 'package:showrunner_flutter/runtime/graph_runtime.dart';
import 'package:showrunner_flutter/schema/automation.dart';

void main() {
  test(
    'notifies listeners and supports listeners added after cancellation',
    () {
      final token = DartCancellationToken(id: 'test-cancel');
      var calls = 0;

      token.addListener(() => calls++);
      token.cancel();
      token.addListener(() => calls++);

      expect(token.isCancelled, isTrue);
      expect(calls, 2);
      expect(
        () => token.throwIfCancelled(),
        throwsA(isA<DartCancelledException>()),
      );
    },
  );

  test('graph runtime stops before invoking a cancelled action', () async {
    final token = DartCancellationToken(id: 'graph-cancel');
    token.cancel();
    var invoked = false;

    final graph = AutomationGraph(
      entryNodeId: 'action',
      nodes: [
        GraphNode(
          id: 'action',
          type: 'action',
          x: 0,
          y: 0,
          data: const {'plugin': 'test', 'action': 'run'},
        ),
      ],
    );

    await expectLater(
      const DartGraphRuntime().execute(
        graph: graph,
        context: EvaluationContext(cancellationToken: token),
        action: (node, config, context) async {
          invoked = true;
          return null;
        },
      ),
      throwsA(isA<DartCancelledException>()),
    );
    expect(invoked, isFalse);
  });
}
