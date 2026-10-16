import 'package:sai_nodes_core/sai_nodes_core.dart';
import '../definitions/showrunner_graph_types.dart';
import 'automation_document.dart';

AutomationDocument createEventAutomation({
  required String plugin,
  required String trigger,
  GraphJson config = const {},
  String? nodeId,
}) {
  final id = nodeId ?? newGraphId();
  final document = AutomationDocument.empty();
  return AutomationDocument(
    graph: document.graph.copyWith(
      spaces: {
        mainAutomationSpace: GraphSpace(
          id: mainAutomationSpace,
          nodes: {
            id: GraphNode(
              id: id,
              type: triggerNodeType(plugin, trigger),
              data: {'config': config},
            ),
          },
          nodePresentations: {
            id: NodePresentation(
              nodeId: id,
              position: const GraphPoint(80, 100),
            ),
          },
        ),
      },
    ),
    settings: {'entryNodeId': id},
  );
}

AutomationDocument createSampleAutomation() {
  final empty = AutomationDocument.empty();
  final condition = newGraphId(),
      flag = newGraphId(),
      done = newGraphId(),
      wire = newGraphId(),
      flow = newGraphId();
  return AutomationDocument(
    graph: empty.graph.copyWith(
      spaces: {
        mainAutomationSpace: GraphSpace(
          id: mainAutomationSpace,
          nodes: {
            flag: GraphNode(
              id: flag,
              type: 'showrunner.variable',
              data: {
                'name': 'enabled',
                'dataType': 'core.boolean',
                'value': true,
              },
            ),
            condition: GraphNode(
              id: condition,
              type: 'showrunner.if',
              data: {'condition': false},
            ),
            done: GraphNode(id: done, type: 'showrunner.return'),
          },
          nodePresentations: {
            flag: NodePresentation(
              nodeId: flag,
              position: const GraphPoint(40, 80),
            ),
            condition: NodePresentation(
              nodeId: condition,
              position: const GraphPoint(380, 80),
            ),
            done: NodePresentation(
              nodeId: done,
              position: const GraphPoint(720, 80),
            ),
          },
          connections: {
            wire: GraphConnection(
              id: wire,
              kind: GraphConnectionKind.data,
              from: PortRef(nodeId: flag, portId: 'value.out'),
              to: PortRef(nodeId: condition, portId: 'config:condition'),
            ),
            flow: GraphConnection(
              id: flow,
              kind: GraphConnectionKind.control,
              from: PortRef(nodeId: condition, portId: 'flow:then'),
              to: PortRef(nodeId: done, portId: 'exec.in'),
            ),
          },
        ),
      },
    ),
    settings: {'entryNodeId': condition},
    metadata: {'name': 'Example branch'},
  );
}
