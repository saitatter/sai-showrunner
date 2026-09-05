import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/runtime/graph_runtime.dart';
import 'package:showrunner_flutter/runtime/expression.dart';
import 'package:showrunner_flutter/schema/automation.dart';

void main() {
  test(
    'executes the old queue node through the canonical queue action',
    () async {
      GraphNode? executed;
      RuntimeMap? config;

      final result = await const DartGraphRuntime().execute(
        graph: const AutomationGraph(
          nodes: [
            GraphNode(
              id: 'queue',
              type: 'queue.addItem',
              x: 0,
              y: 0,
              data: {'queueName': 'alerts'},
            ),
          ],
          entryNodeId: 'queue',
        ),
        context: EvaluationContext(),
        action: (node, nextConfig, context) async {
          executed = node;
          config = nextConfig;
          return null;
        },
      );

      expect(result.completed, isTrue);
      expect(executed?.type, 'action');
      expect(executed?.data['plugin'], 'ShowRunner');
      expect(executed?.data['action'], 'addToQueue');
      expect(config?['queue'], 'alerts');
    },
  );

  test(
    'executes the old overlay node through the canonical overlay action',
    () async {
      GraphNode? executed;
      final result = await const DartGraphRuntime().execute(
        graph: const AutomationGraph(
          nodes: [
            GraphNode(
              id: 'overlay',
              type: 'overlay.pushChat',
              x: 0,
              y: 0,
              data: {'message': 'Hello'},
            ),
          ],
          entryNodeId: 'overlay',
        ),
        context: EvaluationContext(),
        action: (node, config, context) async {
          executed = node;
          return null;
        },
      );

      expect(result.completed, isTrue);
      expect(executed?.type, 'action');
      expect(executed?.data['plugin'], 'overlays');
      expect(executed?.data['action'], 'pushChatMessage');
    },
  );
}
