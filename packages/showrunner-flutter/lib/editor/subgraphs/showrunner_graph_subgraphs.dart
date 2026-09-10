part of '../showrunner_graph_editor.dart';

/// ShowRunner subgraph orchestration.
///
/// Subgraphs are product resources, so their persistence, navigation, and
/// call-node metadata stay in the ShowRunner adapter. Generic node and port
/// behavior remains owned by sai_nodes.
extension ShowRunnerGraphEditorSubgraphs on ShowRunnerGraphEditor {
  String addSubgraph({String? name}) {
    final existingIds = subgraphs.value.map((subgraph) => subgraph.id).toSet();
    var index = subgraphs.value.length + 1;
    var id = 'subgraph-$index';
    while (existingIds.contains(id)) {
      index++;
      id = 'subgraph-$index';
    }
    final subgraph = SubgraphDefinition(
      id: id,
      name: name?.trim().isNotEmpty == true ? name!.trim() : 'Subgraph $index',
      nodes: const [],
      edges: const [],
      entryNodeId: '',
    );
    subgraphs.value = [...subgraphs.value, subgraph];
    return id;
  }

  void addSubgraphParameter(String subgraphId, {bool output = false}) {
    final subgraph = _findSubgraph(subgraphId);
    if (subgraph == null) return;
    final values = [
      ...(output ? subgraph.outputs : subgraph.parameters),
      <String, dynamic>{
        'name':
            '${output ? 'output' : 'input'}${(output ? subgraph.outputs : subgraph.parameters).length + 1}',
        'type': 'string',
        if (!output) 'default': '',
      },
    ];
    _updateSubgraph(
      subgraph,
      output
          ? subgraph.copyWith(outputs: values)
          : subgraph.copyWith(parameters: values),
    );
  }

  void deleteSubgraphParameter(
    String subgraphId,
    int index, {
    bool output = false,
  }) {
    final subgraph = _findSubgraph(subgraphId);
    if (subgraph == null) return;
    final values = [...(output ? subgraph.outputs : subgraph.parameters)];
    if (index < 0 || index >= values.length) return;
    values.removeAt(index);
    _updateSubgraph(
      subgraph,
      output
          ? subgraph.copyWith(outputs: values)
          : subgraph.copyWith(parameters: values),
    );
  }

  void updateSubgraphParameter(
    String subgraphId,
    int index, {
    required String field,
    required dynamic value,
    bool output = false,
  }) {
    final subgraph = _findSubgraph(subgraphId);
    if (subgraph == null) return;
    final values = [
      for (final item in (output ? subgraph.outputs : subgraph.parameters))
        Map<String, dynamic>.from(item),
    ];
    if (index < 0 || index >= values.length) return;
    final item = values[index];
    if (field == 'name') {
      final fallback = '${output ? 'output' : 'input'}${index + 1}';
      item['name'] = value.toString().trim().isEmpty
          ? fallback
          : value.toString().trim();
    } else if (field == 'type') {
      final type = value.toString();
      item['type'] = ShowRunnerGraphEditor.subgraphParameterTypes.contains(type)
          ? type
          : 'any';
      if (!output) {
        item['default'] = ShowRunnerGraphEditor._coerceSubgraphDefault(
          item['type'],
          item['default'],
        );
      }
    } else if (field == 'default' && !output) {
      item['default'] = ShowRunnerGraphEditor._coerceSubgraphDefault(
        item['type']?.toString() ?? 'any',
        value,
      );
    } else {
      return;
    }
    _updateSubgraph(
      subgraph,
      output
          ? subgraph.copyWith(outputs: values)
          : subgraph.copyWith(parameters: values),
    );
  }

  SubgraphDefinition? _findSubgraph(String id) =>
      subgraphs.value.where((subgraph) => subgraph.id == id).firstOrNull;

  void _updateSubgraph(
    SubgraphDefinition original,
    SubgraphDefinition updated,
  ) {
    final values = [...subgraphs.value];
    final index = values.indexWhere((subgraph) => subgraph.id == original.id);
    if (index < 0) return;
    values[index] = updated;
    subgraphs.value = values;
    _refreshSubgraphCallNodes(original.id, updated);
  }

  void _refreshSubgraphCallNodes(
    String subgraphId,
    SubgraphDefinition subgraph,
  ) {
    final prototypeId = ShowRunnerGraphEditor._subgraphCallPrototypeId(
      subgraphId,
    );
    for (final target in _controllers.values) {
      _ensureSubgraphCallPrototype(subgraph, target: target);
      for (final node in target.nodes.values.where(
        (node) => _nodeDataByEditorId[node.id]?['subgraphId'] == subgraphId,
      )) {
        final prototype = target.nodePrototypes[prototypeId];
        if (prototype == null) continue;
        target.reconcileNodePorts(node.id, prototype.ports);
      }
      final selected = target.selectedNodeIds.toSet();
      target.clearSelection();
      if (selected.isNotEmpty) target.selectNodesById(selected);
    }
    nodeRevision.value++;
  }

  // Each subgraph gets its own controller. Sync before navigation so edits in
  // a nested canvas are persisted before another controller becomes active.
  bool enterSubgraph(String subgraphId) {
    final subgraph = subgraphs.value
        .where((candidate) => candidate.id == subgraphId)
        .firstOrNull;
    if (subgraph == null) return false;
    _syncActiveGraph();
    final target = _controllers[subgraphId] ??= _createController();
    if (!_entryNodeIdByGraph.containsKey(subgraphId)) {
      final wasSuspended = _suspendDirtyTracking;
      _suspendDirtyTracking = true;
      try {
        _loadGraphIntoController(
          target,
          AutomationGraph(
            nodes: subgraph.nodes,
            edges: subgraph.edges,
            entryNodeId: subgraph.entryNodeId,
          ),
          graphKey: subgraphId,
          dataWires: subgraph.dataWires,
        );
      } finally {
        _suspendDirtyTracking = wasSuspended;
      }
    }
    controller = target;
    activeGraphPath.value = [...activeGraphPath.value, subgraphId];
    return true;
  }

  bool goBackToParentGraph() {
    if (activeGraphPath.value.isEmpty) return false;
    _syncActiveGraph();
    final path = [...activeGraphPath.value]..removeLast();
    controller =
        _controllers[path.lastOrNull ?? ShowRunnerGraphEditor._mainGraphKey]!;
    activeGraphPath.value = path;
    return true;
  }

  bool navigateToGraphDepth(int depth) {
    if (depth < 0 || depth > activeGraphPath.value.length) return false;
    var changed = false;
    while (activeGraphPath.value.length > depth) {
      changed = goBackToParentGraph() || changed;
    }
    return changed;
  }

  void deleteSubgraph(String subgraphId) {
    if (!subgraphs.value.any((subgraph) => subgraph.id == subgraphId)) return;
    if (activeGraphPath.value.contains(subgraphId)) {
      controller = _controllers[ShowRunnerGraphEditor._mainGraphKey]!;
      activeGraphPath.value = const [];
    }
    final mainCallIds = controller.nodes.values
        .where(
          (node) =>
              _nodeDataByEditorId[node.id]?['subgraphId']?.toString() ==
              subgraphId,
        )
        .map((node) => node.id)
        .toList();
    for (final nodeId in mainCallIds) {
      controller.removeNodeById(nodeId);
    }
    subgraphs.value = subgraphs.value
        .where((subgraph) => subgraph.id != subgraphId)
        .map((subgraph) => _removeSubgraphCalls(subgraph, subgraphId))
        .toList();
    final deletedController = _controllers.remove(subgraphId);
    _entryNodeIdByGraph.remove(subgraphId);
    if (deletedController != null) {
      _fieldEvents.remove(deletedController)?.cancel();
      deletedController.dispose();
    }
    _markDocumentDirty();
  }

  String? addSubgraphCall(
    String subgraphId, {
    String? title,
    Offset offset = const Offset(80, 80),
  }) {
    final subgraph = subgraphs.value
        .where((candidate) => candidate.id == subgraphId)
        .firstOrNull;
    if (subgraph == null) return null;
    final nodeTitle = title?.trim().isNotEmpty == true
        ? title!.trim()
        : subgraph.name;
    _ensureSubgraphCallPrototype(subgraph);
    final node = controller.addNode(
      ShowRunnerGraphEditor._subgraphCallPrototypeId(subgraphId),
      offset: offset,
    );
    _nodeDataByEditorId[node.id] = {
      'subgraphId': subgraphId,
      'inputs': <String, dynamic>{},
      if (nodeTitle.isNotEmpty) 'title': nodeTitle,
    };
    if (nodeTitle.isNotEmpty) _nodeTitles[node.id] = nodeTitle;
    _markDocumentDirty();
    return node.id;
  }

  void renameSubgraph(String subgraphId, String name) {
    final index = subgraphs.value.indexWhere(
      (subgraph) => subgraph.id == subgraphId,
    );
    if (index < 0) return;
    final normalized = name.trim().isEmpty ? 'Subgraph' : name.trim();
    final updated = [...subgraphs.value];
    updated[index] = SubgraphDefinition(
      id: updated[index].id,
      name: normalized,
      parameters: updated[index].parameters,
      outputs: updated[index].outputs,
      nodes: updated[index].nodes,
      edges: updated[index].edges,
      dataWires: updated[index].dataWires,
      entryNodeId: updated[index].entryNodeId,
    );
    subgraphs.value = updated;
    _markDocumentDirty();
  }
}
