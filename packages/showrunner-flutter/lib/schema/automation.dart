typedef JsonMap = Map<String, dynamic>;

final class GraphNode {
  const GraphNode({
    required this.id,
    required this.type,
    required this.x,
    required this.y,
    this.data = const <String, dynamic>{},
  });

  final String id;
  final String type;
  final double x;
  final double y;
  final JsonMap data;

  JsonMap toJson() => {'id': id, 'type': type, 'x': x, 'y': y, ...data};

  factory GraphNode.fromJson(JsonMap json) {
    final data = Map<String, dynamic>.from(json)
      ..removeWhere((key, _) => {'id', 'type', 'x', 'y'}.contains(key));
    return GraphNode(
      id: json['id'] as String? ?? '',
      type: json['type'] as String? ?? 'action',
      x: _asDouble(json['x']),
      y: _asDouble(json['y']),
      data: data,
    );
  }
}

final class GraphEdge {
  const GraphEdge({
    required this.id,
    required this.from,
    required this.to,
    this.port,
  });

  final String id;
  final String from;
  final String to;
  final String? port;

  JsonMap toJson() => {
    'id': id,
    'from': from,
    'to': to,
    if (port != null) 'port': port,
  };

  factory GraphEdge.fromJson(JsonMap json) => GraphEdge(
    id: json['id'] as String? ?? '',
    from: json['from'] as String? ?? '',
    to: json['to'] as String? ?? '',
    port: json['port'] as String?,
  );
}

final class DataWire {
  const DataWire({
    required this.id,
    required this.fromNode,
    required this.fromPort,
    required this.toNode,
    required this.toPort,
  });

  final String id;
  final String fromNode;
  final String fromPort;
  final String toNode;
  final String toPort;

  JsonMap toJson() => {
    'id': id,
    'fromNode': fromNode,
    'fromPort': fromPort,
    'toNode': toNode,
    'toPort': toPort,
  };

  factory DataWire.fromJson(JsonMap json) => DataWire(
    id: json['id'] as String? ?? '',
    fromNode: json['fromNode'] as String? ?? '',
    fromPort: json['fromPort'] as String? ?? '',
    toNode: json['toNode'] as String? ?? '',
    toPort: json['toPort'] as String? ?? '',
  );
}

final class AutomationGraph {
  const AutomationGraph({
    this.nodes = const <GraphNode>[],
    this.edges = const <GraphEdge>[],
    this.entryNodeId = '',
  });

  final List<GraphNode> nodes;
  final List<GraphEdge> edges;
  final String entryNodeId;

  JsonMap toJson() => {
    'nodes': nodes.map((node) => node.toJson()).toList(),
    'edges': edges.map((edge) => edge.toJson()).toList(),
    'entryNodeId': entryNodeId,
  };

  factory AutomationGraph.fromJson(JsonMap? json) {
    final nodes = _maps(
      json?['nodes'],
    ).map(GraphNode.fromJson).where((node) => node.id.isNotEmpty).toList();
    final edges = _maps(json?['edges'])
        .map(GraphEdge.fromJson)
        .where(
          (edge) =>
              edge.id.isNotEmpty && edge.from.isNotEmpty && edge.to.isNotEmpty,
        )
        .toList();
    final entryNodeId = json?['entryNodeId'] as String?;
    return AutomationGraph(
      nodes: nodes,
      edges: edges,
      entryNodeId: entryNodeId?.isNotEmpty == true
          ? entryNodeId!
          : nodes.firstOrNull?.id ?? '',
    );
  }
}

final class SubgraphDefinition {
  const SubgraphDefinition({
    required this.id,
    required this.name,
    required this.nodes,
    required this.edges,
    required this.entryNodeId,
    this.parameters = const <JsonMap>[],
    this.outputs = const <JsonMap>[],
    this.dataWires = const <DataWire>[],
  });

  final String id;
  final String name;
  final List<JsonMap> parameters;
  final List<JsonMap> outputs;
  final List<GraphNode> nodes;
  final List<GraphEdge> edges;
  final List<DataWire> dataWires;
  final String entryNodeId;

  SubgraphDefinition copyWith({
    String? id,
    String? name,
    List<JsonMap>? parameters,
    List<JsonMap>? outputs,
    List<GraphNode>? nodes,
    List<GraphEdge>? edges,
    List<DataWire>? dataWires,
    String? entryNodeId,
  }) => SubgraphDefinition(
    id: id ?? this.id,
    name: name ?? this.name,
    parameters: parameters ?? this.parameters,
    outputs: outputs ?? this.outputs,
    nodes: nodes ?? this.nodes,
    edges: edges ?? this.edges,
    dataWires: dataWires ?? this.dataWires,
    entryNodeId: entryNodeId ?? this.entryNodeId,
  );

  JsonMap toJson() => {
    'id': id,
    'name': name,
    'parameters': parameters,
    'outputs': outputs,
    'nodes': nodes.map((node) => node.toJson()).toList(),
    'edges': edges.map((edge) => edge.toJson()).toList(),
    'dataWires': dataWires.map((wire) => wire.toJson()).toList(),
    'entryNodeId': entryNodeId,
  };

  factory SubgraphDefinition.fromJson(JsonMap json) {
    final graph = AutomationGraph.fromJson(json);
    return SubgraphDefinition(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      parameters: _maps(json['parameters']),
      outputs: _maps(json['outputs']),
      nodes: graph.nodes,
      edges: graph.edges,
      dataWires: _maps(json['dataWires']).map(DataWire.fromJson).toList(),
      entryNodeId: json['entryNodeId'] as String? ?? graph.entryNodeId,
    );
  }
}

final class AutomationData {
  const AutomationData({
    this.schemaVersion = 2,
    this.graph = const AutomationGraph(),
    this.subgraphs = const <SubgraphDefinition>[],
    this.dataWires = const <DataWire>[],
    this.variableNodes = const <JsonMap>[],
    this.triggerNodes = const <JsonMap>[],
    this.extra = const <String, dynamic>{},
  });

  final int schemaVersion;
  final AutomationGraph graph;
  final List<SubgraphDefinition> subgraphs;
  final List<DataWire> dataWires;
  final List<JsonMap> variableNodes;
  final List<JsonMap> triggerNodes;
  final JsonMap extra;

  String? get queueId {
    final value = extra['queue'];
    return value is String && value.trim().isNotEmpty ? value.trim() : null;
  }

  JsonMap toJson() => {
    ...extra,
    'schemaVersion': schemaVersion,
    'graph': graph.toJson(),
    'subgraphs': subgraphs.map((subgraph) => subgraph.toJson()).toList(),
    'dataWires': dataWires.map((wire) => wire.toJson()).toList(),
    'variableNodes': variableNodes,
    'triggerNodes': triggerNodes,
  };

  factory AutomationData.fromJson(JsonMap input) {
    final json = Map<String, dynamic>.from(input);
    if (json['schemaVersion'] != 2) {
      throw const FormatException('Automation data must use schemaVersion 2.');
    }
    final rawGraph = json['graph'];
    if (rawGraph is! Map || rawGraph['nodes'] is! List) {
      throw const FormatException(
        'Automation data must contain a graph with a nodes list.',
      );
    }
    final graph = AutomationGraph.fromJson(Map<String, dynamic>.from(rawGraph));
    final subgraphs = _maps(json['subgraphs'])
        .map(SubgraphDefinition.fromJson)
        .where((subgraph) => subgraph.id.isNotEmpty)
        .toList();
    return AutomationData(
      schemaVersion: 2,
      graph: graph,
      subgraphs: subgraphs,
      dataWires: _maps(
        json['dataWires'],
      ).map(DataWire.fromJson).where((wire) => wire.id.isNotEmpty).toList(),
      variableNodes: _maps(json['variableNodes']),
      triggerNodes: _maps(json['triggerNodes']),
      extra: json
        ..removeWhere(
          (key, _) => {
            'schemaVersion',
            'graph',
            'subgraphs',
            'dataWires',
            'variableNodes',
            'triggerNodes',
          }.contains(key),
        ),
    );
  }
}

double _asDouble(Object? value) => value is num ? value.toDouble() : 0;

List<JsonMap> _maps(Object? value) {
  if (value is! List) return <JsonMap>[];
  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
