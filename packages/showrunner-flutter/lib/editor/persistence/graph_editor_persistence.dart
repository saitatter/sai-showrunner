part of '../showrunner_graph_editor.dart';

/// Persistence orchestration for the ShowRunner graph adapter.
///
/// The generic controller owns the live graph model. This extension owns the
/// boundary between that model and ShowRunner's persisted automation schema.
extension ShowRunnerGraphEditorPersistence on ShowRunnerGraphEditor {
  void loadAutomation(AutomationData automation) {
    final wasSuspended = _suspendDirtyTracking;
    var completed = false;
    _suspendDirtyTracking = true;
    try {
      final restoredFrames = _framesFromExtra(automation.extra);
      for (final entry in _controllers.entries.where(
        (entry) => entry.key != ShowRunnerGraphEditor._mainGraphKey,
      )) {
        _fieldEvents.remove(entry.value)?.cancel();
        entry.value.dispose();
      }
      _controllers.removeWhere(
        (key, _) => key != ShowRunnerGraphEditor._mainGraphKey,
      );
      controller = _controllers[ShowRunnerGraphEditor._mainGraphKey]!;
      controller.clear();
      selectedFrameId.value = null;
      clearInvalidSelection();
      subgraphs.value = automation.subgraphs;
      activeGraphPath.value = const [];
      searchMatchIndex.value = 0;
      searchQuery.value = '';
      graphFeedback.value = null;
      _entryNodeIdByGraph.clear();
      _variableEditorIds.clear();
      _triggerEditorIds.clear();
      _triggerNodeStateInitialized = automation.triggerNodes.isNotEmpty;
      _nodeDataByEditorId.clear();
      _nodeTitles.clear();
      _schemaIdByEditorId.clear();
      _schemaIdByLinkSignature.clear();
      _loadGraphIntoController(
        controller,
        automation.graph,
        graphKey: ShowRunnerGraphEditor._mainGraphKey,
        dataWires: automation.dataWires,
        variableNodes: automation.variableNodes,
        triggerNodes: automation.triggerNodes,
      );
      controller.restoreFrames(
        restoredFrames.map(
          (frame) => frame.copyWith(
            members: frame.members
                .map(
                  (id) =>
                      editorNodeIdForSchema(id) ??
                      (controller.nodes.containsKey(id) ? id : null),
                )
                .whereType<String>(),
          ),
        ),
      );
      _syncFrameProjection(controller);
      completed = true;
    } finally {
      _suspendDirtyTracking = wasSuspended;
      if (completed) markDocumentClean();
    }
  }

  AutomationData toAutomation(AutomationData original) {
    _syncActiveGraph();
    for (final entry in _controllers.entries) {
      if (entry.key == ShowRunnerGraphEditor._mainGraphKey ||
          entry.key == activeSubgraphId) {
        continue;
      }
      final subgraph = subgraphs.value
          .where((candidate) => candidate.id == entry.key)
          .firstOrNull;
      if (subgraph != null) {
        _syncControllerToSubgraph(entry.key, entry.value, subgraph);
      }
    }
    final main = _serializeGraph(
      controller: _controllers[ShowRunnerGraphEditor._mainGraphKey]!,
      graphKey: ShowRunnerGraphEditor._mainGraphKey,
      original: original.graph,
      dataWires: original.dataWires,
    );
    final savedSubgraphs = subgraphs.value;
    return AutomationData(
      schemaVersion: original.schemaVersion,
      graph: main.graph,
      subgraphs: savedSubgraphs,
      dataWires: main.dataWires,
      variableNodes: _serializeVariableNodes(
        _controllers[ShowRunnerGraphEditor._mainGraphKey]!,
      ),
      triggerNodes: _triggerNodeStateInitialized
          ? _serializeTriggerNodes(
              _controllers[ShowRunnerGraphEditor._mainGraphKey]!,
            )
          : original.triggerNodes,
      extra: {
        ...original.extra,
        'editorFrames': _controllers[ShowRunnerGraphEditor._mainGraphKey]!
            .frames
            .values
            .map(_serializeFrame)
            .toList(),
      },
    );
  }
}
