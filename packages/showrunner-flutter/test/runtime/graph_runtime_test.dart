import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/runtime/graph_runtime.dart';
import 'package:showrunner_flutter/runtime/expression.dart';
import 'package:showrunner_flutter/schema/automation.dart';

void main() {
  test('executes a canonical action node', () async {
    GraphNode? executed;
    RuntimeMap? config;

    final result = await const DartGraphRuntime().execute(
      graph: const AutomationGraph(
        nodes: [
          GraphNode(
            id: 'queue',
            type: 'action',
            x: 0,
            y: 0,
            data: {
              'plugin': 'ShowRunner',
              'action': 'addToQueue',
              'config': {'queue': 'alerts'},
            },
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
  });
}
