import 'package:sai_nodes_core/sai_nodes_core.dart';

import '../domain/automation_document.dart';
import 'automation_editor_controller.dart';

/// Clipboard dependencies are an interchange payload, never a second live model.
extension AutomationClipboard on AutomationEditorController {
  GraphFragment captureFragment() {
    final fragment = GraphFragment.capture(graph);
    final signatures = <String, AutomationSubgraph>{};
    final spaces = <String, GraphSpace>{};
    void dependencies(Iterable<GraphNode> nodes) {
      for (final node in nodes) {
        if (node.type != 'showrunner.subgraphCall') continue;
        final id = node.data['subgraphId'];
        final signature = document.subgraphs[id];
        if (signature == null || signatures.containsKey(id)) continue;
        signatures[signature.id] = signature;
        final space = document.graph.spaces[signature.spaceId];
        if (space == null) continue;
        spaces[space.id] = space;
        dependencies(space.nodes.values);
      }
    }

    dependencies(fragment.space.nodes.values);
    return GraphFragment(
      space: fragment.space,
      hostPayload: {
        'showrunner': {
          'version': 1,
          'documentId': document.id,
          'subgraphs': {
            for (final entry in signatures.entries)
              entry.key: entry.value.toJson(),
          },
          'dependencies': GraphDocument(
            id: 'clipboard-dependencies',
            spaces: spaces,
          ).toJson(),
        },
      },
    );
  }

  GraphSelection pasteFragment(GraphFragment fragment) {
    final payload = fragment.hostPayload['showrunner'];
    if (payload == null) {
      return graph.pasteGraphFragment(
        fragment,
        transformRemapped: (space, ids) =>
            _rewriteSpaceData(space, ids, const {}),
      );
    }
    if (payload is! Map ||
        payload['version'] != 1 ||
        payload['subgraphs'] is! Map ||
        payload['dependencies'] is! Map) {
      throw const FormatException('Invalid Showrunner clipboard dependencies.');
    }
    final dependencies = GraphDocument.fromJson(
      Map<String, Object?>.from(payload['dependencies'] as Map),
    );
    final signatures = <String, AutomationSubgraph>{
      for (final entry in (payload['subgraphs'] as Map).entries)
        entry.key.toString(): AutomationSubgraph.fromJson(
          Map<String, Object?>.from(entry.value as Map),
        ),
    };
    if (signatures.entries.any((entry) => entry.key != entry.value.id) ||
        dependencies.spaces.keys.any(
          (id) =>
              !signatures.values.any((signature) => signature.spaceId == id),
        )) {
      throw const FormatException(
        'Clipboard dependency identities do not match.',
      );
    }
    final reserved = <String>{
      ...document.subgraphs.keys,
      for (final space in document.graph.spaces.values) ...[
        ...space.nodes.keys,
        ...space.connections.keys,
        ...space.frames.keys,
        ...space.comments.keys,
      ],
    };
    String allocate() {
      String id;
      do {
        id = newGraphId();
      } while (!reserved.add(id));
      return id;
    }

    final subgraphIds = <String, String>{};
    final nodeIds = <String, String>{};
    final cloned = <String, AutomationSubgraph>{};
    final clonedSpaces = <String, GraphSpace>{};
    for (final signature in signatures.values) {
      final sameSource = payload['documentId'] == document.id;
      final current = document.subgraphs[signature.id];
      // Reuse only an unchanged dependency from this very document. This also
      // keeps ordinary duplicate operations from multiplying declarations.
      if (sameSource &&
          current != null &&
          _equalJson(current.toJson(), signature.toJson()) &&
          document.graph.spaces[signature.spaceId] ==
              dependencies.spaces[signature.spaceId]) {
        continue;
      }
      subgraphIds[signature.id] = allocate();
      final space = dependencies.spaces[signature.spaceId];
      if (space != null) {
        for (final id in space.nodes.keys) {
          nodeIds[id] = allocate();
        }
      }
    }
    for (final signature in signatures.values.where(
      (signature) => subgraphIds.containsKey(signature.id),
    )) {
      final id = subgraphIds[signature.id]!;
      final copy = AutomationSubgraph(
        id: id,
        name: signature.name,
        entryNodeId: nodeIds[signature.entryNodeId] ?? signature.entryNodeId,
        parameters: signature.parameters,
        outputs: signature.outputs,
      );
      cloned[id] = copy;
      final source = dependencies.spaces[signature.spaceId];
      if (source != null) {
        clonedSpaces[copy.spaceId] = _copyDependencySpace(
          source,
          copy.spaceId,
          nodeIds,
          subgraphIds,
          allocate,
        );
      }
    }
    final metadata = document
        .withSubgraphs({...document.subgraphs, ...cloned})
        .graph
        .metadata;
    return graph.pasteGraphFragment(
      fragment,
      // These IDs must also avoid the dependency entities prepared above.
      idFactory: allocate,
      transformRemapped: (space, ids) =>
          _rewriteSpaceData(space, {...nodeIds, ...ids}, subgraphIds),
      prepareTransaction: (tx) {
        for (final space in clonedSpaces.values) {
          tx.execute(AddSpaceCommand(space));
        }
        if (cloned.isNotEmpty) {
          tx.execute(UpdateDocumentMetadataCommand(metadata));
        }
      },
    );
  }
}

GraphSpace _copyDependencySpace(
  GraphSpace source,
  String id,
  Map<String, String> nodes,
  Map<String, String> subgraphs,
  String Function() allocate,
) {
  final edges = {for (final edge in source.connections.keys) edge: allocate()};
  final frames = {for (final frame in source.frames.keys) frame: allocate()};
  final comments = {
    for (final comment in source.comments.keys) comment: allocate(),
  };
  return GraphSpace(
    id: id,
    nodes: {
      for (final node in source.nodes.values)
        nodes[node.id]!: GraphNode(
          id: nodes[node.id]!,
          type: node.type,
          data: _rewriteNodeData(node, nodes, subgraphs),
          metadata: node.metadata,
        ),
    },
    connections: {
      for (final edge in source.connections.values)
        edges[edge.id]!: GraphConnection(
          id: edges[edge.id]!,
          from: PortRef(
            nodeId: nodes[edge.from.nodeId] ?? edge.from.nodeId,
            portId: edge.from.portId,
          ),
          to: PortRef(
            nodeId: nodes[edge.to.nodeId] ?? edge.to.nodeId,
            portId: edge.to.portId,
          ),
          kind: edge.kind,
          data: edge.data,
        ),
    },
    nodePresentations: {
      for (final view in source.nodePresentations.values)
        (nodes[view.nodeId] ?? view.nodeId): NodePresentation(
          nodeId: nodes[view.nodeId] ?? view.nodeId,
          position: view.position,
          size: view.size,
          title: view.title,
          collapsed: view.collapsed,
          metadata: view.metadata,
        ),
    },
    connectionPresentations: {
      for (final view in source.connectionPresentations.values)
        (edges[view.connectionId] ?? view.connectionId): ConnectionPresentation(
          connectionId: edges[view.connectionId] ?? view.connectionId,
          waypoints: view.waypoints,
          label: view.label,
          labelOffset: view.labelOffset,
          metadata: view.metadata,
        ),
    },
    frames: {
      for (final frame in source.frames.values)
        frames[frame.id]!: GraphFrame(
          id: frames[frame.id]!,
          bounds: frame.bounds,
          title: frame.title,
          memberNodeIds: {
            for (final node in frame.memberNodeIds) nodes[node] ?? node,
          },
          autoFit: frame.autoFit,
          metadata: frame.metadata,
        ),
    },
    comments: {
      for (final comment in source.comments.values)
        comments[comment.id]!: GraphComment(
          id: comments[comment.id]!,
          bounds: comment.bounds,
          text: comment.text,
          metadata: comment.metadata,
        ),
    },
    metadata: source.metadata,
  );
}

GraphSpace _rewriteSpaceData(
  GraphSpace space,
  Map<String, String> nodes,
  Map<String, String> subgraphs,
) => space.copyWith(
  nodes: {
    for (final node in space.nodes.values)
      node.id: node.copyWith(data: _rewriteNodeData(node, nodes, subgraphs)),
  },
);

GraphJson _rewriteNodeData(
  GraphNode node,
  Map<String, String> nodes,
  Map<String, String> subgraphs,
) {
  final data = {...node.data};
  if (node.type == 'showrunner.subgraphCall') {
    data['subgraphId'] = subgraphs[data['subgraphId']] ?? data['subgraphId'];
  }
  final fields = switch (node.type) {
    'showrunner.if' || 'showrunner.while' => ['condition'],
    'showrunner.switch' => ['value', 'cases'],
    'showrunner.for' => ['start', 'end', 'step'],
    'showrunner.forEach' => ['collection'],
    'showrunner.subgraphCall' => ['arguments'],
    'showrunner.return' => ['outputs'],
    _ => <String>[],
  };
  for (final field in fields) {
    if (data.containsKey(field)) {
      data[field] = _rewriteExpression(data[field], nodes);
    }
  }
  return data;
}

Object? _rewriteExpression(Object? value, Map<String, String> nodes) {
  if (value is List) {
    return value.map((item) => _rewriteExpression(item, nodes)).toList();
  }
  if (value is! Map || value['type'] == 'literal') return value;
  return {
    for (final entry in value.entries)
      entry.key.toString(): value['type'] == 'port' && entry.key == 'nodeId'
          ? nodes[entry.value] ?? entry.value
          : _rewriteExpression(entry.value, nodes),
  };
}

bool _equalJson(Object? left, Object? right) {
  if (left is Map && right is Map) {
    return left.length == right.length &&
        left.keys.every(
          (key) => right.containsKey(key) && _equalJson(left[key], right[key]),
        );
  }
  if (left is List && right is List) {
    return left.length == right.length &&
        left.indexed.every((item) => _equalJson(item.$2, right[item.$1]));
  }
  return left == right;
}
