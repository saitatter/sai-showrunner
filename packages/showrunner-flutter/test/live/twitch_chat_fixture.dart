import '../support/graph_fixtures.dart';

AutomationDocument twitchChatProofGraph() => automationFixture(
  entryNodeId: 'condition',
  nodes: [
    GraphNode(
      id: 'condition',
      type: 'showrunner.if',
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
      type: actionNodeType('variables', 'set'),
      data: {
        'config': {'variable': 'twitchProof', 'value': '{{message}}'},
      },
    ),
  ],
  connections: [
    controlFixture('yes', 'condition', 'matched', port: 'flow:then'),
  ],
);
