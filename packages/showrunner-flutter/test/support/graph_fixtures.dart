import 'package:sai_nodes_core/sai_nodes_core.dart';
import 'package:showrunner_flutter/graph/domain/automation_document.dart';
import 'package:showrunner_flutter/graph/definitions/showrunner_graph_types.dart';

export 'package:sai_nodes_core/sai_nodes_core.dart';
export 'package:showrunner_flutter/graph/domain/automation_document.dart';
export 'package:showrunner_flutter/graph/definitions/showrunner_graph_types.dart';

AutomationDocument automationFixture({
  String? id,
  String? name,
  Iterable<GraphNode> nodes = const [],
  Iterable<GraphConnection> connections = const [],
  String entryNodeId = '',
  GraphJson settings = const {},
  Map<String, AutomationSubgraph> subgraphs = const {},
  Map<String, GraphSpace> spaces = const {},
}) => AutomationDocument(
  graph: GraphDocument(
    id: id ?? newGraphId(),
    spaces: {
      mainAutomationSpace: GraphSpace(
        id: mainAutomationSpace,
        nodes: {for (final node in nodes) node.id: node},
        connections: {
          for (final connection in connections) connection.id: connection,
        },
        nodePresentations: {
          for (final (index, node) in nodes.indexed)
            node.id: NodePresentation(
              nodeId: node.id,
              position: GraphPoint(80 + index * 340, 80),
            ),
        },
      ),
      ...spaces,
    },
  ),
  settings: {'entryNodeId': entryNodeId, ...settings},
  subgraphs: subgraphs,
  metadata: {'name': ?name},
);

GraphNode actionFixture(
  String id, {
  String plugin = 'test',
  String action = 'record',
  GraphJson config = const {},
  GraphJson data = const {},
}) => GraphNode(
  id: id,
  type: actionNodeType(plugin, action),
  data: {'config': config, ...data},
);
GraphConnection controlFixture(
  String id,
  String from,
  String to, {
  String port = 'exec.out',
}) => GraphConnection(
  id: id,
  from: PortRef(nodeId: from, portId: port),
  to: PortRef(nodeId: to, portId: 'exec.in'),
  kind: GraphConnectionKind.control,
);
GraphConnection valueFixture(
  String id,
  String from,
  String output,
  String to,
  String input,
) => GraphConnection(
  id: id,
  from: PortRef(nodeId: from, portId: output),
  to: PortRef(nodeId: to, portId: input),
  kind: GraphConnectionKind.data,
);

AutomationDocument eventFixture({
  required String id,
  String plugin = 'test',
  String trigger = 'chat',
  GraphJson config = const {},
  Iterable<GraphNode> nodes = const [],
  Iterable<GraphConnection> connections = const [],
  String? next,
  bool stop = false,
  String? queue,
}) => automationFixture(
  nodes: [
    GraphNode(
      id: id,
      type: triggerNodeType(plugin, trigger),
      data: {'config': config, 'stop': stop},
    ),
    ...nodes,
  ],
  connections: [
    if (next != null) controlFixture('$id:next', id, next),
    ...connections,
  ],
  entryNodeId: id,
  settings: {'queue': ?queue},
);
