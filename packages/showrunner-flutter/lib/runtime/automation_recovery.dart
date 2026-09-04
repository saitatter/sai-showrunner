import '../schema/automation.dart';

const _validNodeTypes = {
  'action',
  'if',
  'switch',
  'for',
  'forEach',
  'while',
  'break',
  'continue',
  'return',
  'subgraphCall',
  'trigger.chatMessage',
  'queue.addItem',
  'overlay.pushChat',
};
const _validVariableTypes = {'string', 'number', 'boolean', 'color'};

List<String> validateAutomationGraph(
  AutomationData automation, {
  List<JsonMap> parameters = const <JsonMap>[],
  List<JsonMap> outputs = const <JsonMap>[],
}) {
  final issues = <String>[];
  final graph = automation.graph;
  final nodeIds = <String>{};
  final nodeById = <String, GraphNode>{};
  for (final node in graph.nodes) {
    if (node.id.trim().isEmpty) {
      issues.add('A graph node is missing an id.');
      continue;
    }
    if (!nodeIds.add(node.id)) issues.add('Duplicate node id: ${node.id}');
    nodeById[node.id] = node;
    if (!_isSupportedNodeType(node.type)) {
      issues.add('Unsupported node type on ${node.id}: ${node.type}');
    }
  }
  if (graph.entryNodeId.isNotEmpty && !nodeIds.contains(graph.entryNodeId)) {
    issues.add('Entry node does not exist: ${graph.entryNodeId}');
  }
  for (final edge in graph.edges) {
    if (edge.id.trim().isEmpty) {
      issues.add('A graph edge is missing an id.');
    }
    if (!nodeIds.contains(edge.from)) {
      issues.add('Edge ${edge.id} starts at missing node: ${edge.from}');
    }
    if (!nodeIds.contains(edge.to)) {
      issues.add('Edge ${edge.id} ends at missing node: ${edge.to}');
    }
    final source = nodeById[edge.from];
    if (source != null &&
        !_flowOutputPorts(source).contains(edge.port ?? 'completed')) {
      issues.add(
        'Edge ${edge.id} uses missing output port: ${edge.from}.${edge.port ?? 'completed'}',
      );
    }
    final target = nodeById[edge.to];
    if (target != null && target.type.startsWith('trigger.')) {
      issues.add('Edge ${edge.id} uses missing input port: ${edge.to}.exec');
    }
  }
  final variableIds = <String>{};
  final variableTypes = <String, String>{};
  for (final variable in automation.variableNodes) {
    final id = variable['id']?.toString() ?? '';
    final type = variable['type']?.toString() ?? '';
    if (id.isEmpty) {
      issues.add('A variable node is missing an id.');
    }
    if (!_validVariableTypes.contains(type)) {
      issues.add('Variable ${variable['name'] ?? id} has an unsupported type.');
    }
    if (id.isNotEmpty && _validVariableTypes.contains(type)) {
      variableIds.add(id);
      variableTypes[id] = type;
    }
  }
  final sourceIds = {...nodeIds, ...variableIds, 'trigger'};
  final targetIds = {...nodeIds, ...variableIds};
  final parameterTypes = _boundaryTypes(parameters);
  final outputTypes = _boundaryTypes(outputs);
  sourceIds.addAll(parameterTypes.keys.map((name) => '__param:$name'));
  targetIds.addAll(outputTypes.keys.map((name) => '__output:$name'));
  final dataDependencies = <String, Set<String>>{};
  for (final wire in automation.dataWires) {
    if (wire.id.trim().isEmpty) {
      issues.add('A data wire is missing an id.');
    }
    if (!sourceIds.contains(wire.fromNode)) {
      issues.add(
        'Data wire ${wire.id} starts at missing node: ${wire.fromNode}',
      );
    }
    if (!targetIds.contains(wire.toNode)) {
      issues.add('Data wire ${wire.id} ends at missing node: ${wire.toNode}');
    }
    if (wire.fromPort.isEmpty || wire.toPort.isEmpty) {
      issues.add('Data wire ${wire.id} is missing a port.');
    }
    if (sourceIds.contains(wire.fromNode) && targetIds.contains(wire.toNode)) {
      dataDependencies.putIfAbsent(wire.fromNode, () => {}).add(wire.toNode);
    }
    final sourceType = _dataPortType(
      nodeId: wire.fromNode,
      port: wire.fromPort,
      output: true,
      nodeById: nodeById,
      variableTypes: variableTypes,
      parameterTypes: parameterTypes,
      outputTypes: outputTypes,
    );
    if (sourceType == null) {
      issues.add(
        'Data wire ${wire.id} uses missing source port: ${wire.fromNode}.${wire.fromPort}',
      );
    }
    final targetType = _dataPortType(
      nodeId: wire.toNode,
      port: wire.toPort,
      output: false,
      nodeById: nodeById,
      variableTypes: variableTypes,
      parameterTypes: parameterTypes,
      outputTypes: outputTypes,
    );
    if (targetType == null) {
      issues.add(
        'Data wire ${wire.id} uses missing target port: ${wire.toNode}.${wire.toPort}',
      );
    } else if (sourceType != null &&
        !_dataTypesCompatible(sourceType, targetType)) {
      issues.add(
        'Data wire ${wire.id} is incompatible: $sourceType -> $targetType',
      );
    }
  }
  for (final wire in automation.dataWires) {
    if (!sourceIds.contains(wire.fromNode) ||
        !targetIds.contains(wire.toNode)) {
      continue;
    }
    if (_hasDataDependencyPath(dataDependencies, wire.toNode, wire.fromNode)) {
      issues.add('Data wire ${wire.id} creates a circular dependency.');
    }
  }
  return issues;
}

Set<String> _flowOutputPorts(GraphNode node) => switch (node.type) {
  'if' => {'then', 'else'},
  'switch' => {
    'default',
    ...((node.data['cases'] is List
            ? (node.data['cases'] as List).whereType<Map>()
            : const <Map>[])
        .map((item) => item['port']?.toString())
        .whereType<String>()
        .where((port) => port.isNotEmpty)),
  },
  'for' || 'forEach' || 'while' => {'body', 'next'},
  'break' || 'continue' || 'return' => const {},
  'overlay.pushChat' => const {},
  _ => {'completed'},
};

String? _dataPortType({
  required String nodeId,
  required String port,
  required bool output,
  required Map<String, GraphNode> nodeById,
  required Map<String, String> variableTypes,
  Map<String, String> parameterTypes = const <String, String>{},
  Map<String, String> outputTypes = const <String, String>{},
}) {
  if (nodeId == 'trigger') return output ? 'any' : null;
  if (nodeId.startsWith('__param:')) {
    final name = nodeId.substring('__param:'.length);
    return output && port == 'value' ? parameterTypes[name] : null;
  }
  if (nodeId.startsWith('__output:')) {
    final name = nodeId.substring('__output:'.length);
    return !output && port == 'value' ? outputTypes[name] : null;
  }
  final variableType = variableTypes[nodeId];
  if (variableType != null) return port == 'value' ? variableType : null;
  final node = nodeById[nodeId];
  if (node == null) return null;
  if (node.type.startsWith('trigger.')) {
    return output && port == 'payload' ? 'any' : null;
  }
  if (node.type == 'queue.addItem' || node.type == 'overlay.pushChat') {
    return port == 'payload' ? 'any' : null;
  }
  if (node.type == 'action') return 'any';
  return null;
}

Map<String, String> _boundaryTypes(List<JsonMap> definitions) => {
  for (final definition in definitions)
    if (definition['name']?.toString().trim().isNotEmpty == true)
      definition['name'].toString(): definition['type']?.toString() ?? 'any',
};

bool _dataTypesCompatible(String source, String target) =>
    source == 'any' || target == 'any' || source == target;

bool _hasDataDependencyPath(
  Map<String, Set<String>> dependencies,
  String start,
  String target,
) {
  final pending = <String>[start];
  final visited = <String>{};
  while (pending.isNotEmpty) {
    final node = pending.removeLast();
    if (node == target) return true;
    if (!visited.add(node)) continue;
    pending.addAll(dependencies[node] ?? const <String>{});
  }
  return false;
}

AutomationData repairAutomation(AutomationData automation) {
  final graph = _repairGraph(automation.graph);
  final variables = automation.variableNodes
      .where((node) {
        final id = node['id']?.toString() ?? '';
        return id.isNotEmpty &&
            _validVariableTypes.contains(node['type']?.toString());
      })
      .map((node) => Map<String, dynamic>.from(node))
      .toList();
  final sources = {
    ...graph.nodes.map((node) => node.id),
    ...variables.map((node) => node['id'].toString()),
    'trigger',
  };
  final targets = {
    ...graph.nodes.map((node) => node.id),
    ...variables.map((node) => node['id'].toString()),
  };
  final nodeById = {for (final node in graph.nodes) node.id: node};
  final variableTypes = {
    for (final variable in variables)
      variable['id'].toString(): variable['type'].toString(),
  };
  final wires = automation.dataWires
      .where(
        (wire) =>
            wire.id.isNotEmpty &&
            sources.contains(wire.fromNode) &&
            targets.contains(wire.toNode) &&
            wire.fromPort.isNotEmpty &&
            wire.toPort.isNotEmpty &&
            _isValidDataWire(
              wire,
              nodeById: nodeById,
              variableTypes: variableTypes,
            ),
      )
      .toList();
  return AutomationData(
    schemaVersion: automation.schemaVersion,
    graph: graph,
    subgraphs: automation.subgraphs.map(_repairSubgraph).toList(),
    dataWires: wires,
    variableNodes: variables,
    triggerNodes: automation.triggerNodes,
    extra: automation.extra,
  );
}

SubgraphDefinition _repairSubgraph(SubgraphDefinition subgraph) {
  final graph = _repairGraph(
    AutomationGraph(
      nodes: subgraph.nodes,
      edges: subgraph.edges,
      entryNodeId: subgraph.entryNodeId,
    ),
  );
  final nodeById = {for (final node in graph.nodes) node.id: node};
  final wires = subgraph.dataWires
      .where(
        (wire) =>
            wire.id.isNotEmpty &&
            wire.fromPort.isNotEmpty &&
            wire.toPort.isNotEmpty &&
            _isValidDataWire(
              wire,
              nodeById: nodeById,
              variableTypes: const <String, String>{},
              parameterTypes: _boundaryTypes(subgraph.parameters),
              outputTypes: _boundaryTypes(subgraph.outputs),
            ),
      )
      .toList();
  return subgraph.copyWith(
    nodes: graph.nodes,
    edges: graph.edges,
    dataWires: wires,
    entryNodeId: graph.entryNodeId,
  );
}

AutomationGraph _repairGraph(AutomationGraph graph) {
  final seen = <String>{};
  final nodes = graph.nodes
      .where(
        (node) =>
            node.id.isNotEmpty &&
            _isSupportedNodeType(node.type) &&
            seen.add(node.id),
      )
      .toList();
  final ids = nodes.map((node) => node.id).toSet();
  final edges = graph.edges
      .where(
        (edge) =>
            edge.id.isNotEmpty &&
            ids.contains(edge.from) &&
            ids.contains(edge.to) &&
            _isValidFlowEdge(edge, {for (final node in nodes) node.id: node}),
      )
      .toList();
  return AutomationGraph(
    nodes: nodes,
    edges: edges,
    entryNodeId: ids.contains(graph.entryNodeId)
        ? graph.entryNodeId
        : nodes.firstOrNull?.id ?? '',
  );
}

bool _isSupportedNodeType(String type) =>
    _validNodeTypes.contains(type) || type.startsWith('trigger.');

bool _isValidFlowEdge(GraphEdge edge, Map<String, GraphNode> nodeById) {
  final source = nodeById[edge.from];
  final target = nodeById[edge.to];
  return source != null &&
      target != null &&
      _flowOutputPorts(source).contains(edge.port ?? 'completed') &&
      !target.type.startsWith('trigger.');
}

bool _isValidDataWire(
  DataWire wire, {
  required Map<String, GraphNode> nodeById,
  required Map<String, String> variableTypes,
  Map<String, String> parameterTypes = const <String, String>{},
  Map<String, String> outputTypes = const <String, String>{},
}) {
  final sourceType = _dataPortType(
    nodeId: wire.fromNode,
    port: wire.fromPort,
    output: true,
    nodeById: nodeById,
    variableTypes: variableTypes,
    parameterTypes: parameterTypes,
    outputTypes: outputTypes,
  );
  final targetType = _dataPortType(
    nodeId: wire.toNode,
    port: wire.toPort,
    output: false,
    nodeById: nodeById,
    variableTypes: variableTypes,
    parameterTypes: parameterTypes,
    outputTypes: outputTypes,
  );
  return sourceType != null &&
      targetType != null &&
      _dataTypesCompatible(sourceType, targetType);
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
