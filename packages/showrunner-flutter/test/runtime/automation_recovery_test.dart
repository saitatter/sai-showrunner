import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/runtime/automation_recovery.dart';
import 'package:showrunner_flutter/schema/automation.dart';

void main() {
  test('validates and repairs malformed automation graph references', () {
    const automation = AutomationData(
      graph: AutomationGraph(
        entryNodeId: 'missing',
        nodes: [
          GraphNode(id: 'start', type: 'action', x: 0, y: 0),
          GraphNode(id: 'start', type: 'action', x: 10, y: 10),
          GraphNode(id: 'unknown', type: 'unsupported', x: 0, y: 0),
        ],
        edges: [GraphEdge(id: 'bad', from: 'start', to: 'missing')],
      ),
      dataWires: [
        DataWire(
          id: 'wire',
          fromNode: 'trigger',
          fromPort: 'event',
          toNode: 'missing',
          toPort: 'value',
        ),
      ],
    );
    expect(validateAutomationGraph(automation), isNotEmpty);
    final repaired = repairAutomation(automation);
    expect(repaired.graph.nodes.map((node) => node.id), ['start']);
    expect(repaired.graph.edges, isEmpty);
    expect(repaired.graph.entryNodeId, 'start');
    expect(repaired.dataWires, isEmpty);
    expect(validateAutomationGraph(repaired), isEmpty);
  });

  test('keeps valid variable nodes and their data wires', () {
    const automation = AutomationData(
      graph: AutomationGraph(
        nodes: [GraphNode(id: 'action', type: 'action', x: 0, y: 0)],
        entryNodeId: 'action',
      ),
      variableNodes: [
        {'id': 'message', 'name': '', 'type': 'string', 'value': ''},
      ],
      dataWires: [
        DataWire(
          id: 'message-wire',
          fromNode: 'message',
          fromPort: 'value',
          toNode: 'action',
          toPort: 'message',
        ),
      ],
    );
    expect(validateAutomationGraph(automation), isEmpty);
    final repaired = repairAutomation(automation);
    expect(repaired.variableNodes, automation.variableNodes);
    expect(repaired.dataWires, automation.dataWires);
  });

  test('keeps dynamic plugin triggers during graph repair', () {
    const automation = AutomationData(
      graph: AutomationGraph(
        nodes: [
          GraphNode(id: 'trigger', type: 'trigger.twitch.chat', x: 0, y: 0),
        ],
        entryNodeId: 'trigger',
      ),
      subgraphs: [
        SubgraphDefinition(
          id: 'nested',
          name: 'Nested',
          nodes: [
            GraphNode(
              id: 'nested-trigger',
              type: 'trigger.discord.message',
              x: 0,
              y: 0,
            ),
          ],
          edges: [],
          entryNodeId: 'nested-trigger',
        ),
      ],
    );

    final repaired = repairAutomation(automation);

    expect(repaired.graph.nodes.single.type, 'trigger.twitch.chat');
    expect(
      repaired.subgraphs.single.nodes.single.type,
      'trigger.discord.message',
    );
  });

  test('reports circular data-wire dependencies', () {
    const automation = AutomationData(
      graph: AutomationGraph(
        nodes: [
          GraphNode(id: 'a', type: 'action', x: 0, y: 0),
          GraphNode(id: 'b', type: 'action', x: 100, y: 0),
        ],
        entryNodeId: 'a',
      ),
      dataWires: [
        DataWire(
          id: 'a-to-b',
          fromNode: 'a',
          fromPort: 'value',
          toNode: 'b',
          toPort: 'value',
        ),
        DataWire(
          id: 'b-to-a',
          fromNode: 'b',
          fromPort: 'value',
          toNode: 'a',
          toPort: 'value',
        ),
      ],
    );

    final issues = validateAutomationGraph(automation);

    expect(issues, contains('Data wire a-to-b creates a circular dependency.'));
    expect(issues, contains('Data wire b-to-a creates a circular dependency.'));
  });

  test(
    'reports invalid flow and data ports with edge-specific diagnostics',
    () {
      const automation = AutomationData(
        graph: AutomationGraph(
          nodes: [
            GraphNode(id: 'condition', type: 'if', x: 0, y: 0),
            GraphNode(id: 'target', type: 'action', x: 100, y: 0),
          ],
          edges: [
            GraphEdge(
              id: 'bad-flow',
              from: 'condition',
              to: 'target',
              port: 'missing',
            ),
          ],
          entryNodeId: 'condition',
        ),
        variableNodes: [
          {'id': 'text', 'name': 'Text', 'type': 'string', 'value': ''},
          {'id': 'count', 'name': 'Count', 'type': 'number', 'value': 0},
        ],
        dataWires: [
          DataWire(
            id: 'bad-data-port',
            fromNode: 'text',
            fromPort: 'missing',
            toNode: 'target',
            toPort: 'value',
          ),
          DataWire(
            id: 'bad-data-type',
            fromNode: 'text',
            fromPort: 'value',
            toNode: 'count',
            toPort: 'value',
          ),
        ],
      );

      final issues = validateAutomationGraph(automation);

      expect(
        issues,
        contains('Edge bad-flow uses missing output port: condition.missing'),
      );
      expect(
        issues,
        contains(
          'Data wire bad-data-port uses missing source port: text.missing',
        ),
      );
      expect(
        issues,
        contains('Data wire bad-data-type is incompatible: string -> number'),
      );
    },
  );

  test('repairs invalid flow ports and incompatible data wires', () {
    const automation = AutomationData(
      graph: AutomationGraph(
        nodes: [
          GraphNode(id: 'condition', type: 'if', x: 0, y: 0),
          GraphNode(id: 'target', type: 'action', x: 100, y: 0),
        ],
        edges: [
          GraphEdge(
            id: 'invalid-flow',
            from: 'condition',
            to: 'target',
            port: 'missing',
          ),
        ],
        entryNodeId: 'condition',
      ),
      variableNodes: [
        {'id': 'text', 'name': 'Text', 'type': 'string', 'value': ''},
        {'id': 'count', 'name': 'Count', 'type': 'number', 'value': 0},
      ],
      dataWires: [
        DataWire(
          id: 'invalid-data',
          fromNode: 'text',
          fromPort: 'value',
          toNode: 'count',
          toPort: 'value',
        ),
      ],
    );

    final repaired = repairAutomation(automation);

    expect(repaired.graph.edges, isEmpty);
    expect(repaired.dataWires, isEmpty);
  });

  test('validates and repairs subgraph boundary wires', () {
    const subgraph = SubgraphDefinition(
      id: 'nested',
      name: 'Nested',
      parameters: [
        {'name': 'text', 'type': 'string'},
      ],
      outputs: [
        {'name': 'message', 'type': 'string'},
      ],
      nodes: [GraphNode(id: 'action', type: 'action', x: 0, y: 0)],
      edges: [],
      dataWires: [
        DataWire(
          id: 'valid-input',
          fromNode: '__param:text',
          fromPort: 'value',
          toNode: 'action',
          toPort: 'value',
        ),
        DataWire(
          id: 'valid-output',
          fromNode: 'action',
          fromPort: 'value',
          toNode: '__output:message',
          toPort: 'value',
        ),
        DataWire(
          id: 'invalid-input',
          fromNode: '__param:missing',
          fromPort: 'value',
          toNode: 'action',
          toPort: 'value',
        ),
      ],
      entryNodeId: 'action',
    );
    final graph = AutomationGraph(
      nodes: subgraph.nodes,
      edges: subgraph.edges,
      entryNodeId: subgraph.entryNodeId,
    );

    final issues = validateAutomationGraph(
      AutomationData(graph: graph, dataWires: subgraph.dataWires),
      parameters: subgraph.parameters,
      outputs: subgraph.outputs,
    );
    expect(
      issues,
      contains(
        'Data wire invalid-input starts at missing node: __param:missing',
      ),
    );

    final repaired = repairAutomation(AutomationData(subgraphs: [subgraph]));
    expect(repaired.subgraphs.single.dataWires.map((wire) => wire.id), [
      'valid-input',
      'valid-output',
    ]);
  });

  test('removes variable nodes without ids or supported types', () {
    const automation = AutomationData(
      variableNodes: [
        {'id': '', 'type': 'number'},
        {'id': 'bad', 'type': 'date'},
      ],
    );
    expect(validateAutomationGraph(automation), hasLength(2));
    expect(repairAutomation(automation).variableNodes, isEmpty);
  });
}
