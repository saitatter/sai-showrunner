part of '../showrunner_graph_editor.dart';

/// Validation and repair actions for the ShowRunner graph adapter.
///
/// Generic node/link invariants are provided by the shared editor package;
/// this layer also validates persisted ShowRunner metadata and retained
/// invalid user data.
extension ShowRunnerGraphDiagnostics on ShowRunnerGraphEditor {
  List<String> currentGraphIssues() {
    final saved = toAutomation(const AutomationData());
    final subgraphId = activeSubgraphId;
    if (subgraphId == null) return validateAutomationGraph(saved);
    final subgraph = saved.subgraphs
        .where((candidate) => candidate.id == subgraphId)
        .firstOrNull;
    if (subgraph == null) return const ['Active subgraph does not exist.'];
    return validateAutomationGraph(
      AutomationData(
        graph: AutomationGraph(
          nodes: subgraph.nodes,
          edges: subgraph.edges,
          entryNodeId: subgraph.entryNodeId,
        ),
        dataWires: subgraph.dataWires,
      ),
      parameters: subgraph.parameters,
      outputs: subgraph.outputs,
    );
  }

  void discardInvalidFlowEdge(String edgeId) {
    final graphKey = activeSubgraphId ?? ShowRunnerGraphEditor._mainGraphKey;
    final invalid = _invalidFlowEdgesByGraph[graphKey];
    if (invalid == null) return;
    final remaining = invalid.where((edge) => edge.id != edgeId).toList();
    if (remaining.length == invalid.length) return;
    _invalidFlowEdgesByGraph[graphKey] = remaining;
    if (selectedInvalidFlowEdgeId.value == edgeId) {
      selectedInvalidFlowEdgeId.value = null;
    }
    nodeRevision.value++;
  }

  void discardInvalidDataWire(String wireId) {
    final graphKey = activeSubgraphId ?? ShowRunnerGraphEditor._mainGraphKey;
    final invalid = _invalidDataWiresByGraph[graphKey];
    if (invalid == null) return;
    final remaining = invalid.where((wire) => wire.id != wireId).toList();
    if (remaining.length == invalid.length) return;
    _invalidDataWiresByGraph[graphKey] = remaining;
    if (selectedInvalidDataWireId.value == wireId) {
      selectedInvalidDataWireId.value = null;
    }
    nodeRevision.value++;
  }

  void selectInvalidFlowEdge(String edgeId) {
    if (!invalidFlowEdges.any((edge) => edge.id == edgeId)) return;
    selectedInvalidFlowEdgeId.value = edgeId;
    selectedInvalidDataWireId.value = null;
    selectedFrameId.value = null;
    controller.clearSelection();
  }

  void selectInvalidDataWire(String wireId) {
    if (!invalidDataWires.any((wire) => wire.id == wireId)) return;
    selectedInvalidDataWireId.value = wireId;
    selectedInvalidFlowEdgeId.value = null;
    selectedFrameId.value = null;
    controller.clearSelection();
  }

  void clearInvalidSelection() {
    selectedInvalidFlowEdgeId.value = null;
    selectedInvalidDataWireId.value = null;
  }

  void repairCurrentGraph() {
    loadAutomation(repairAutomation(toAutomation(const AutomationData())));
  }
}
