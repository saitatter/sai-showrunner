import 'package:showrunner_flutter/schema/automation.dart';

AutomationData twitchChatProofGraph() => AutomationData(
  graph: AutomationGraph(
    entryNodeId: 'condition',
    nodes: const [
      GraphNode(
        id: 'condition',
        type: 'if',
        x: 0,
        y: 0,
        data: {
          'condition': {
            'type': 'binary',
            'op': '==',
            'left': {'type': 'variable', 'name': 'message'},
            'right': {'type': 'literal', 'value': 'showrunner-test'},
          },
        },
      ),
      GraphNode(
        id: 'matched',
        type: 'action',
        x: 300,
        y: 0,
        data: {
          'plugin': 'variables',
          'action': 'set',
          'config': {'variable': 'twitchProof', 'value': '{{message}}'},
        },
      ),
    ],
    edges: const [
      GraphEdge(id: 'yes', from: 'condition', to: 'matched', port: 'then'),
    ],
  ),
);
