part of '../showrunner_graph_editor.dart';

/// Persistence orchestration for the ShowRunner graph adapter.
///
/// The generic controller owns the live graph model. This extension owns the
/// boundary between that model and ShowRunner's persisted automation schema.
extension ShowRunnerAutomationGraphSerializer on ShowRunnerGraphEditor {
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

/// Schema/editor graph loading and serialization helpers.
extension ShowRunnerAutomationGraphSchemaSerializer on ShowRunnerGraphEditor {
  void _loadGraphIntoController(
    NodeEditorController target,
    AutomationGraph graph, {
    required String graphKey,
    List<DataWire> dataWires = const <DataWire>[],
    List<JsonMap> variableNodes = const <JsonMap>[],
    List<JsonMap> triggerNodes = const <JsonMap>[],
  }) {
    target.clear();
    _entryNodeIdByGraph[graphKey] = graph.entryNodeId;
    final switchPorts = <String>{'default'};
    for (final node in graph.nodes.where((node) => node.type == 'switch')) {
      final cases = node.data['cases'];
      if (cases is List) {
        for (final item in cases.whereType<Map>()) {
          final port = item['port']?.toString();
          if (port != null && port.isNotEmpty) switchPorts.add(port);
        }
      }
    }
    if (switchPorts.length > 1) {
      _registerSwitchPrototype(switchPorts, target: target);
    }
    final nodes = <String, NodeDataModel>{};
    for (final node in graph.nodes) {
      final subgraphId = node.data['subgraphId']?.toString();
      final subgraph = subgraphId == null ? null : _findSubgraph(subgraphId);
      // Persisted action nodes use the schema type `action` and keep their
      // plugin/action identity in the payload. Rehydrate them with the
      // Rehydrate action documents with their canonical editor prototype so
      // the canvas always exposes the plugin's actual ports and fields.
      final actionPlugin = node.data['plugin']?.toString().trim();
      final actionId = node.data['action']?.toString().trim();
      final canonicalActionType =
          actionPlugin != null &&
              actionPlugin.isNotEmpty &&
              actionId != null &&
              actionId.isNotEmpty
          ? '$actionPlugin.$actionId'
          : null;
      final editorNodeType = node.type == 'subgraphCall' && subgraph != null
          ? _subgraphCallPrototypeId(subgraph.id)
          : node.type == 'action' && canonicalActionType != null
          ? canonicalActionType
          : node.type;
      if (subgraph != null) {
        _ensureSubgraphCallPrototype(subgraph, target: target);
      } else {
        _ensurePrototype(editorNodeType, target: target);
      }
      final editorNode = target.addNode(
        editorNodeType,
        offset: Offset(node.x, node.y),
        snapToGrid: false,
      );
      nodes[node.id] = editorNode;
      _nodeDataByEditorId[editorNode.id] = Map<String, dynamic>.from(node.data);
      _schemaIdByEditorId[editorNode.id] = node.id;
      final title = node.data['title'];
      if (title is String && title.trim().isNotEmpty) {
        final normalizedTitle = title.trim();
        _nodeTitles[editorNode.id] = normalizedTitle;
        editorNode.customTitle = normalizedTitle;
      }
      final editorSize = _editorSizeFromJson(
        node.data['editorSize'],
        target.config,
      );
      if (editorSize != null) {
        editorNode.customSize = editorSize;
      }
      for (final field in editorNode.fields.values) {
        final value = node.data[field.prototype.idName];
        if (value is String) {
          target.setFieldData(
            editorNode.id,
            field.prototype.idName,
            data: value,
            eventType: FieldEventType.submit,
          );
        }
      }
    }
    _loadTriggerNodes(target, triggerNodes, nodes, graph.entryNodeId);
    if (graphKey == ShowRunnerGraphEditor._mainGraphKey) {
      _loadVariableNodes(target, variableNodes, nodes);
    }
    final invalidFlowEdges = <GraphEdge>[];
    for (final edge in graph.edges) {
      final from = nodes[edge.from];
      final to = nodes[edge.to];
      if (from == null || to == null) {
        invalidFlowEdges.add(edge);
        continue;
      }
      final link = target.addLink(
        from.id,
        edge.port ?? 'completed',
        to.id,
        'exec',
        label: _flowLinkLabel(
          edge.port,
          source: graph.nodes.where((node) => node.id == edge.from).firstOrNull,
        ),
        eventId: edge.id,
      );
      if (link == null) {
        invalidFlowEdges.add(edge);
        continue;
      }
      _schemaIdByLinkSignature[ShowRunnerGraphEditor._linkSignature(
            from.id,
            edge.port ?? 'completed',
            to.id,
            'exec',
          )] =
          edge.id;
    }
    _invalidFlowEdgesByGraph[graphKey] = invalidFlowEdges;
    final invalidDataWires = <DataWire>[];
    for (final wire in dataWires) {
      final from = nodes[wire.fromNode];
      final to = nodes[wire.toNode];
      if (from == null || to == null) {
        invalidDataWires.add(wire);
        continue;
      }
      final link = target.addLink(
        from.id,
        _editorDataOutputPortId(from, wire.fromPort),
        to.id,
        _editorDataInputPortId(to, wire.toPort),
        eventId: wire.id,
      );
      if (link == null) {
        invalidDataWires.add(wire);
        continue;
      }
      _schemaIdByLinkSignature[ShowRunnerGraphEditor._linkSignature(
            from.id,
            wire.fromPort,
            to.id,
            wire.toPort,
          )] =
          wire.id;
    }
    _invalidDataWiresByGraph[graphKey] = invalidDataWires;
  }

  void _loadTriggerNodes(
    NodeEditorController target,
    List<JsonMap> triggerNodes,
    Map<String, NodeDataModel> nodes,
    String entryNodeId,
  ) {
    if (triggerNodes.isEmpty) return;
    for (final trigger in triggerNodes) {
      final schemaId = trigger['id']?.toString() ?? '';
      if (schemaId.isEmpty) continue;
      final existing = nodes[schemaId];
      if (existing != null) {
        _triggerEditorIds.add(existing.id);
        continue;
      }
      final plugin = trigger['plugin']?.toString();
      final triggerId = trigger['trigger']?.toString();
      final type =
          plugin != null &&
              plugin.isNotEmpty &&
              triggerId != null &&
              triggerId.isNotEmpty
          ? 'trigger.$plugin.$triggerId'
          : 'trigger';
      _ensurePrototype(type, target: target);
      final offset = Offset(_number(trigger['x']), _number(trigger['y']));
      final editorNode = target.addNode(
        type,
        offset: offset,
        snapToGrid: false,
      );
      nodes[schemaId] = editorNode;
      _triggerEditorIds.add(editorNode.id);
      _schemaIdByEditorId[editorNode.id] = schemaId;
      _nodeDataByEditorId[editorNode.id] = {
        ...trigger,
        'id': schemaId,
        'plugin': plugin,
        'trigger': triggerId,
        'config': trigger['config'] is Map
            ? Map<String, dynamic>.from(trigger['config'] as Map)
            : <String, dynamic>{},
        'stop': trigger['stop'] == true,
      };
    }
    final entry = nodes[entryNodeId];
    if (entry == null) return;
    for (final trigger in triggerNodes) {
      final schemaId = trigger['id']?.toString() ?? '';
      final triggerNode = nodes[schemaId];
      if (triggerNode == null ||
          target.linksAsList.any(
            (link) =>
                link.endpoints.sourceNodeId == triggerNode.id &&
                link.endpoints.targetNodeId == entry.id,
          )) {
        continue;
      }
      target.addLink(
        triggerNode.id,
        'completed',
        entry.id,
        'exec',
        eventId: '__trigger_entry:$schemaId:$entryNodeId',
      );
    }
  }

  void _loadVariableNodes(
    NodeEditorController target,
    List<JsonMap> variableNodes,
    Map<String, NodeDataModel> nodes,
  ) {
    for (final variable in variableNodes) {
      final id = variable['id']?.toString() ?? '';
      final type = variable['type']?.toString() ?? '';
      if (id.isEmpty || !_variableTypes.contains(type)) continue;
      _ensurePrototype('variable.$type', target: target);
      final offset = Offset(_number(variable['x']), _number(variable['y']));
      final editorNode = target.addNode(
        'variable.$type',
        offset: offset,
        snapToGrid: false,
      );
      nodes[id] = editorNode;
      _variableEditorIds.add(editorNode.id);
      _schemaIdByEditorId[editorNode.id] = id;
      _nodeDataByEditorId[editorNode.id] = {
        ...variable,
        'id': id,
        'name': variable['name']?.toString() ?? '',
        'type': type,
        'value': _normalizeVariableValue(type, variable['value']),
        'x': offset.dx,
        'y': offset.dy,
      };
    }
  }

  void _syncActiveGraph() {
    final subgraphId = activeSubgraphId;
    if (subgraphId == null) return;
    final subgraph = subgraphs.value
        .where((candidate) => candidate.id == subgraphId)
        .firstOrNull;
    if (subgraph != null) {
      _syncControllerToSubgraph(subgraphId, controller, subgraph);
    }
  }

  void _syncControllerToSubgraph(
    String subgraphId,
    NodeEditorController target,
    SubgraphDefinition original,
  ) {
    final serialized = _serializeGraph(
      controller: target,
      graphKey: subgraphId,
      original: AutomationGraph(
        nodes: original.nodes,
        edges: original.edges,
        entryNodeId: original.entryNodeId,
      ),
      dataWires: original.dataWires,
    );
    final index = subgraphs.value.indexWhere(
      (candidate) => candidate.id == subgraphId,
    );
    if (index < 0) return;
    final updated = [...subgraphs.value];
    updated[index] = SubgraphDefinition(
      id: original.id,
      name: original.name,
      parameters: original.parameters,
      outputs: original.outputs,
      nodes: serialized.graph.nodes,
      edges: serialized.graph.edges,
      dataWires: serialized.dataWires,
      entryNodeId: serialized.graph.entryNodeId,
    );
    subgraphs.value = updated;
  }

  ({AutomationGraph graph, List<DataWire> dataWires}) _serializeGraph({
    required NodeEditorController controller,
    required String graphKey,
    required AutomationGraph original,
    required List<DataWire> dataWires,
  }) {
    final nodes = controller.project.projectData.nodes.values
        .where(
          (node) =>
              !_variableEditorIds.contains(node.id) &&
              !_triggerEditorIds.contains(node.id),
        )
        .map(
          (node) => GraphNode(
            id: _schemaIdByEditorId[node.id] ?? node.id,
            type: _nodeDataByEditorId[node.id]?['subgraphId'] is String
                ? 'subgraphCall'
                : _nodeDataByEditorId[node.id]?['plugin'] is String &&
                      _nodeDataByEditorId[node.id]?['action'] is String
                ? 'action'
                : node.prototype.idName,
            x: node.offset.dx,
            y: node.offset.dy,
            data: {
              ...?_nodeDataByEditorId[node.id],
              ..._jsonEntry('title', _nodeTitles[node.id] ?? node.customTitle),
              ..._jsonEntry(
                'editorSize',
                node.customSize == null
                    ? null
                    : [node.customSize!.width, node.customSize!.height],
              ),
            },
          ),
        )
        .toList();
    final edges = <GraphEdge>[];
    final serializedDataWires = <DataWire>[];
    final editorToSchemaId = {
      for (final node in controller.nodes.values)
        node.id: _schemaIdByEditorId[node.id] ?? node.id,
    };
    for (final link in controller.project.projectData.links.values) {
      final sourceNode = controller.nodes[link.endpoints.sourceNodeId];
      final sourcePort = sourceNode?.ports[link.endpoints.sourcePortId];
      final targetNode = controller.nodes[link.endpoints.targetNodeId];
      final from = editorToSchemaId[link.endpoints.sourceNodeId];
      final to = editorToSchemaId[link.endpoints.targetNodeId];
      if (from == null ||
          to == null ||
          sourcePort == null ||
          targetNode == null) {
        continue;
      }
      if (_triggerEditorIds.contains(link.endpoints.sourceNodeId) &&
          sourcePort.prototype.type == PortType.control) {
        continue;
      }
      if (sourcePort.prototype.type == PortType.data) {
        serializedDataWires.add(
          DataWire(
            id:
                _schemaIdByLinkSignature[ShowRunnerGraphEditor._linkSignature(
                  link.endpoints.sourceNodeId,
                  link.endpoints.sourcePortId,
                  link.endpoints.targetNodeId,
                  link.endpoints.targetPortId,
                )] ??
                link.id,
            fromNode: from,
            fromPort: _schemaDataPortName(
              sourceNode,
              link.endpoints.sourcePortId,
            ),
            toNode: to,
            toPort: _schemaDataPortName(
              targetNode,
              link.endpoints.targetPortId,
            ),
          ),
        );
      } else {
        edges.add(
          GraphEdge(
            id:
                _schemaIdByLinkSignature[ShowRunnerGraphEditor._linkSignature(
                  link.endpoints.sourceNodeId,
                  link.endpoints.sourcePortId,
                  link.endpoints.targetNodeId,
                  link.endpoints.targetPortId,
                )] ??
                link.id,
            from: from,
            to: to,
            port: link.endpoints.sourcePortId == 'completed'
                ? null
                : link.endpoints.sourcePortId,
          ),
        );
      }
    }
    // A link rejected by the editor is still valid user data to inspect or
    // repair, so keep it in persistence instead of silently dropping it.
    final retainedFlowEdges = _invalidFlowEdgesByGraph[graphKey] ?? const [];
    edges.addAll(
      retainedFlowEdges.where(
        (edge) => !edges.any((candidate) => candidate.id == edge.id),
      ),
    );
    final retainedDataWires = _invalidDataWiresByGraph[graphKey] ?? const [];
    serializedDataWires.addAll(
      retainedDataWires.where(
        (wire) =>
            !serializedDataWires.any((candidate) => candidate.id == wire.id),
      ),
    );
    final entryNodeId = _entryNodeIdByGraph[graphKey] ?? original.entryNodeId;
    return (
      graph: AutomationGraph(
        nodes: nodes,
        edges: edges,
        entryNodeId:
            entryNodeId.isNotEmpty &&
                nodes.any((node) => node.id == entryNodeId)
            ? entryNodeId
            : nodes.firstOrNull?.id ?? '',
      ),
      dataWires: serializedDataWires,
    );
  }

  List<JsonMap> _serializeVariableNodes(NodeEditorController target) => target
      .nodes
      .values
      .where((node) => _variableEditorIds.contains(node.id))
      .map((node) {
        final data = _nodeDataByEditorId[node.id] ?? const <String, dynamic>{};
        return <String, dynamic>{
          'id':
              _schemaIdByEditorId[node.id] ?? data['id']?.toString() ?? node.id,
          'name': data['name']?.toString() ?? '',
          'type': data['type']?.toString() ?? 'string',
          'value': data['value'],
          'x': node.offset.dx,
          'y': node.offset.dy,
        };
      })
      .toList();

  List<JsonMap> _serializeTriggerNodes(NodeEditorController target) => target
      .nodes
      .values
      .where((node) => _triggerEditorIds.contains(node.id))
      .map((node) {
        final data = _nodeDataByEditorId[node.id] ?? const <String, dynamic>{};
        return <String, dynamic>{
          'id':
              _schemaIdByEditorId[node.id] ?? data['id']?.toString() ?? node.id,
          if (data['plugin'] != null) 'plugin': data['plugin'],
          if (data['trigger'] != null) 'trigger': data['trigger'],
          'config': data['config'] is Map
              ? Map<String, dynamic>.from(data['config'] as Map)
              : <String, dynamic>{},
          'stop': data['stop'] == true,
          'x': node.offset.dx,
          'y': node.offset.dy,
        };
      })
      .toList();
}
