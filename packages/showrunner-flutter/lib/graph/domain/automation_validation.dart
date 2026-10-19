import 'package:sai_nodes_core/sai_nodes_core.dart';
import '../definitions/showrunner_graph_types.dart';
import 'automation_document.dart';

/// Read-only product diagnostics. Invalid references are preserved for repair;
/// opening the editor must never remove entities from a document.
List<String> validateAutomationDocument(AutomationDocument document) {
  final issues = const GraphDocumentValidator()
      .validate(document.graph)
      .map((issue) => issue.message)
      .toList();
  final entries = {
    mainAutomationSpace: document.entryNodeId,
    for (final signature in document.subgraphs.values)
      signature.spaceId: signature.entryNodeId,
  };
  for (final entry in entries.entries) {
    final space = document.graph.spaces[entry.key];
    if (space == null) {
      issues.add('Missing space ${entry.key}.');
      continue;
    }
    if (entry.value.isNotEmpty && !space.nodes.containsKey(entry.value)) {
      issues.add('Missing entry node ${entry.value}.');
    }
    for (final node in space.nodes.values) {
      if (automationNodeKind(node.type) == 'unresolved') {
        issues.add('Unknown node type ${node.type}.');
      }
      if (node.type == 'showrunner.subgraphCall' &&
          !document.subgraphs.containsKey(node.data['subgraphId'])) {
        issues.add('Node ${node.id} calls a missing subgraph.');
      }
    }
  }
  return issues;
}
