import 'package:sai_nodes_core/sai_nodes_core.dart' as core;
import '../../schema/json.dart';
import '../domain/automation_document.dart';
import '../definitions/showrunner_graph_types.dart';
import 'runtime_values.dart';

export '../../schema/json.dart';

/// A compiler input view of the canonical document, never a persisted graph.
/// Wrappers retain original entities/IDs. Port names are decoded to runtime
/// config/result paths; there is no editor/schema node-ID mapping.
final class AutomationRuntimeProjection {
  AutomationRuntimeProjection(this.document) {
    graph = RuntimeGraph(
      this,
      document.graph.spaces[mainAutomationSpace]!,
      document.entryNodeId,
    );
    subgraphs = List.unmodifiable(
      document.subgraphs.values.map(
        (signature) => RuntimeSubgraph(this, signature),
      ),
    );
  }
  final AutomationDocument document;
  late final RuntimeValueResolver values = RuntimeValueResolver(this);
  late final RuntimeGraph graph;
  late final List<RuntimeSubgraph> subgraphs;
  List<RuntimeValueBinding> get dataWires => graph.dataWires;
  List<JsonMap> get triggerNodes => List.unmodifiable(
    graph.nodes
        .where((node) => node.type == 'trigger')
        .map((node) => {'id': node.id, ...node.data}),
  );
  Map<String, RuntimeVariableBinding> get variables => Map.unmodifiable({
    for (final space in document.graph.spaces.values)
      for (final node in space.nodes.values)
        if (node.type == 'showrunner.variable')
          node.id: RuntimeVariableBinding(node, space.id),
  });
  Map<String, String> get parameterNodes => Map.unmodifiable({
    for (final signature in document.subgraphs.values)
      for (final node
          in document.graph.spaces[signature.spaceId]?.nodes.values ??
              <core.GraphNode>[])
        if (node.type == 'showrunner.parameter')
          node.id:
              signature.parameters
                  .where(
                    (parameter) => parameter.id == node.data['parameterId'],
                  )
                  .firstOrNull
                  ?.name ??
              '',
  });
  AutomationSubgraph? signatureForSpace(String id) => document.subgraphs.values
      .where((signature) => signature.spaceId == id)
      .firstOrNull;
  JsonMap get extra => Map<String, dynamic>.from(document.settings);
  void validate() {
    final issues = const core.GraphDocumentValidator().validate(document.graph);
    if (issues.isNotEmpty) {
      throw StateError(
        'Invalid automation: ${issues.map((issue) => issue.message).join('; ')}',
      );
    }
    const supported = {
      'action',
      'trigger',
      'if',
      'switch',
      'for',
      'forEach',
      'while',
      'break',
      'continue',
      'return',
      'subgraphCall',
      'variable',
      'parameter',
    };
    for (final space in document.graph.spaces.values) {
      if (space.connections.values.any(
        (connection) => connection.kind == core.GraphConnectionKind.custom,
      )) {
        throw StateError(
          'Custom connections are not executable automation connections.',
        );
      }
      for (final node in space.nodes.values) {
        if (!supported.contains(automationNodeKind(node.type))) {
          throw StateError('Unresolved node ${node.id}: ${node.type}');
        }
      }
      final executable = space.nodes.values
          .where(
            (node) => !{
              'variable',
              'parameter',
            }.contains(automationNodeKind(node.type)),
          )
          .map((node) => node.id)
          .toSet();
      for (final edge in space.connections.values.where(
        (edge) => edge.kind == core.GraphConnectionKind.control,
      )) {
        if (!executable.contains(edge.from.nodeId) ||
            !executable.contains(edge.to.nodeId)) {
          throw StateError(
            'Control connection ${edge.id} references a data-only node.',
          );
        }
      }
    }
    void entry(RuntimeGraph space) {
      if (space.entryNodeId.isNotEmpty &&
          !space.nodes.any((node) => node.id == space.entryNodeId)) {
        throw StateError(
          'Missing executable entry ${space.entryNodeId} in ${space.space.id}.',
        );
      }
    }

    entry(graph);
    for (final subgraph in subgraphs) {
      entry(subgraph.body);
    }
    for (final subgraph in subgraphs) {
      if (!document.graph.spaces.containsKey(subgraph.signature.spaceId)) {
        throw StateError(
          'Missing subgraph space: ${subgraph.signature.spaceId}',
        );
      }
    }
    if (parameterNodes.values.any((name) => name.isEmpty)) {
      throw StateError('Unresolved subgraph parameter node.');
    }
  }
}

final class RuntimeGraph {
  RuntimeGraph(this.projection, this.space, this.entryNodeId);
  final AutomationRuntimeProjection projection;
  final core.GraphSpace space;
  final String entryNodeId;
  late final List<RuntimeNode> nodes = List.unmodifiable(
    space.nodes.values
        .where(
          (node) => !{
            'variable',
            'parameter',
          }.contains(automationNodeKind(node.type)),
        )
        .map((node) => RuntimeNode(projection, space, node)),
  );
  late final List<RuntimeControlEdge> edges = List.unmodifiable(
    space.connections.values
        .where(
          (connection) => connection.kind == core.GraphConnectionKind.control,
        )
        .map(RuntimeControlEdge.new),
  );
  late final List<RuntimeValueBinding> dataWires = List.unmodifiable(
    space.connections.values
        .where((connection) => connection.kind == core.GraphConnectionKind.data)
        .map(
          (connection) => RuntimeValueBinding(projection, space, connection),
        ),
  );
}

final class RuntimeSubgraph {
  RuntimeSubgraph(this.projection, this.signature);
  final AutomationRuntimeProjection projection;
  final AutomationSubgraph signature;
  String get id => signature.id;
  String get name => signature.name;
  String get entryNodeId => signature.entryNodeId;
  late final RuntimeGraph body = RuntimeGraph(
    projection,
    projection.document.graph.spaces[signature.spaceId] ??
        core.GraphSpace(id: signature.spaceId),
    entryNodeId,
  );
  List<RuntimeNode> get nodes => body.nodes;
  List<RuntimeControlEdge> get edges => body.edges;
  List<RuntimeValueBinding> get dataWires => body.dataWires;
  List<JsonMap> get parameters => List.unmodifiable(
    signature.parameters.map(
      (port) => {
        'id': port.id,
        'name': port.name,
        'type': port.type,
        'default': port.defaultValue,
      },
    ),
  );
  List<JsonMap> get outputs => List.unmodifiable(
    signature.outputs.map(
      (port) => {
        'id': port.id,
        'name': port.name,
        'type': port.type,
        'expression': port.defaultValue,
      },
    ),
  );
}

final class RuntimeNode {
  RuntimeNode(this.projection, this.space, this.source);
  final AutomationRuntimeProjection projection;
  final core.GraphSpace space;
  final core.GraphNode source;
  String get id => source.id;
  String get type => automationNodeKind(source.type);
  late final JsonMap data = _data();
  JsonMap _data() {
    final action = decodeContractNodeType(source.type, 'action'),
        trigger = decodeContractNodeType(source.type, 'trigger');
    if (action != null) {
      return Map.unmodifiable({
        ...source.data,
        'plugin': action.$1,
        'action': action.$2,
      });
    }
    if (trigger != null) {
      return Map.unmodifiable({
        ...source.data,
        'plugin': trigger.$1,
        'trigger': trigger.$2,
      });
    }
    if (type == 'switch') {
      return Map.unmodifiable({
        ...source.data,
        'cases': List.unmodifiable([
          for (final item
              in (source.data['cases'] as List? ?? []).whereType<Map>())
            Map.unmodifiable({...item, 'port': 'case:${item['id']}'}),
        ]),
      });
    }
    if (type == 'subgraphCall') {
      final signature =
          projection.document.subgraphs[source.data['subgraphId']];
      final arguments = source.data['arguments'];
      return Map.unmodifiable({
        ...source.data,
        'inputs': Map.unmodifiable({
          for (final parameter
              in signature?.parameters ?? <AutomationParameter>[])
            if (arguments is Map && arguments.containsKey(parameter.id))
              parameter.name: arguments[parameter.id],
        }),
      });
    }
    if (type == 'return') {
      final outputs = source.data['outputs'];
      final signature = projection.signatureForSpace(space.id);
      return Map.unmodifiable({
        ...source.data,
        'outputs': Map.unmodifiable({
          if (outputs is Map)
            for (final entry in outputs.entries)
              (signature?.outputs
                          .where((output) => output.id == entry.key)
                          .firstOrNull
                          ?.name ??
                      entry.key.toString()):
                  entry.value,
        }),
      });
    }
    return Map.unmodifiable(source.data);
  }
}

final class RuntimeControlEdge {
  const RuntimeControlEdge(this.source);
  final core.GraphConnection source;
  String get id => source.id;
  String get from => source.from.nodeId;
  String get to => source.to.nodeId;
  String? get port => source.from.portId == 'exec.out'
      ? null
      : source.from.portId.startsWith('flow:')
      ? source.from.portId.substring(5)
      : source.from.portId;
  JsonMap toJson() => {
    'id': id,
    'from': from,
    'to': to,
    'port': port,
    'data': source.data,
  };
}

final class RuntimeValueBinding {
  const RuntimeValueBinding(this.projection, this.space, this.source);
  final AutomationRuntimeProjection projection;
  final core.GraphSpace space;
  final core.GraphConnection source;
  String get id => source.id;
  String get fromNode => source.from.nodeId;
  String get toNode => source.to.nodeId;
  String get fromPort {
    final port = source.from.portId;
    if (port.startsWith('result:')) return port.substring(7);
    if (port == 'result' || port == 'event') return '';
    if (port.startsWith('event:')) return port.substring(6);
    if (port == 'value.out') return 'value';
    if (port.startsWith('output:')) {
      final call = space.nodes[fromNode];
      final signature = projection.document.subgraphs[call?.data['subgraphId']];
      return signature?.outputs
              .where((output) => output.id == port.substring(7))
              .firstOrNull
              ?.name ??
          port;
    }
    return port;
  }

  String get toPort {
    final port = source.to.portId;
    if (port.startsWith('config:')) return port.substring(7);
    if (port == 'value.in') return 'value';
    if (port.startsWith('parameter:')) {
      final call = space.nodes[toNode];
      final signature = projection.document.subgraphs[call?.data['subgraphId']];
      return signature?.parameters
              .where((parameter) => parameter.id == port.substring(10))
              .firstOrNull
              ?.name ??
          port;
    }
    if (port.startsWith('output:')) {
      return projection
              .signatureForSpace(space.id)
              ?.outputs
              .where((output) => output.id == port.substring(7))
              .firstOrNull
              ?.name ??
          port;
    }
    return port;
  }

  JsonMap toJson() => {
    'id': id,
    'fromNode': fromNode,
    'fromPort': fromPort,
    'toNode': toNode,
    'toPort': toPort,
    'data': source.data,
  };
}

final class RuntimeVariableBinding {
  const RuntimeVariableBinding(this.source, this.spaceId);
  final core.GraphNode source;
  final String spaceId;
  String get id => source.id;
  String get name => source.data['name'] as String? ?? id;
  Object? get value => source.data['value'];
}
