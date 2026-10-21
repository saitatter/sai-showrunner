import 'dart:convert';
import '../domain/automation_document.dart';

/// Canonical semantic payload, with full equality at the cache boundary.
String graphProgramSignature(
  AutomationDocument automation, {
  String? entryNodeId,
  String entrySpaceId = mainAutomationSpace,
}) => jsonEncode(
  _canonical({
    'spaces': {
      for (final space in automation.graph.spaces.values)
        space.id: {
          'nodes': {
            for (final node in space.nodes.values)
              node.id: {
                'id': node.id,
                'type': node.type,
                'data': node.data,
                'metadata': node.metadata,
              },
          },
          'connections': {
            for (final edge in space.connections.values)
              edge.id: {
                'id': edge.id,
                'kind': edge.kind.name,
                'from': {
                  'nodeId': edge.from.nodeId,
                  'portId': edge.from.portId,
                },
                'to': {'nodeId': edge.to.nodeId, 'portId': edge.to.portId},
                'data': edge.data,
              },
          },
          'metadata': space.metadata,
        },
    },
    'subgraphs': {
      for (final entry in automation.subgraphs.entries)
        entry.key: entry.value.toJson(),
    },
    'entrySpaceId': entrySpaceId,
    'entryNodeId':
        entryNodeId ??
        (entrySpaceId == mainAutomationSpace
            ? automation.entryNodeId
            : automation.subgraphs.values
                  .where((signature) => signature.spaceId == entrySpaceId)
                  .firstOrNull
                  ?.entryNodeId),
  }),
);

Object? _canonical(Object? value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return {for (final key in keys) key: _canonical(value[key])};
  }
  if (value is List) return value.map(_canonical).toList();
  return value;
}
