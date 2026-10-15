part of '../showrunner_graph_editor.dart';

const _variableTypes = {'string', 'number', 'boolean', 'color'};

const _coreConversionActions = {
  'convertnumbertostring',
  'convertbooleantostring',
  'convertstringtonumber',
  'convertbooleantonumber',
  'convertnumbertoboolean',
  'convertstringtoboolean',
  'convertobjecttojsonstring',
  'convertarraytojsonstring',
  'convertjsonstringtoobject',
  'convertjsonstringtoarray',
};

/// ShowRunner-specific graph orchestration.
///
/// This mixin is the application adapter around sai_nodes. It owns the
/// translation between persisted ShowRunner schema data and the generic
/// editor model, while the facade keeps lifecycle and observable state.
extension ShowRunnerGraphAdapter on ShowRunnerGraphEditor {
  void _syncFrameProjection(NodeEditorController graphController) {
    if (!identical(
      graphController,
      _controllers[ShowRunnerGraphEditor._mainGraphKey],
    )) {
      return;
    }
    frames.value = List.unmodifiable(graphController.frames.values);
  }

  GraphNode? _schemaNodeForEditorNode(
    NodeEditorController graphController,
    String editorNodeId,
  ) {
    final node = graphController.nodes[editorNodeId];
    if (node == null) return null;
    return GraphNode(
      id: _schemaIdByEditorId[editorNodeId] ?? editorNodeId,
      type: node.prototype.idName,
      x: node.offset.dx,
      y: node.offset.dy,
      data: _cloneJsonMap(_nodeDataByEditorId[editorNodeId] ?? const {}),
    );
  }

  void _markDocumentDirtyFromRevision() {
    _markDocumentDirty();
  }

  void _updateAlignmentGuides(
    NodeEditorController graphController,
    Set<String> draggedIds,
  ) {
    final result = graphController.alignmentGuidesFor(draggedIds);
    alignmentGuides.value = result.guides
        .map(
          (guide) => GraphAlignmentGuide(
            axis: guide.axis == AlignmentGuideAxis.vertical
                ? GraphAlignmentAxis.vertical
                : GraphAlignmentAxis.horizontal,
            position: guide.position,
            from: guide.from,
            to: guide.to,
          ),
        )
        .toList();
  }

  void _markDocumentDirty() {
    if (!_suspendDirtyTracking && !documentDirty.value) {
      documentDirty.value = true;
    }
  }

  void _markDocumentDirtyFromEvent(NodeEditorEvent event) {
    if (_suspendDirtyTracking ||
        _ignoreQueuedLoadMutations ||
        !isNodeEditorContentMutation(event)) {
      return;
    }
    _markDocumentDirty();
  }

  /// Marks the current graph as persisted after a successful save.
  void markDocumentClean() => documentDirty.value = false;

  /// Restores the dirty marker for a document session after its graph has
  /// been loaded into the shared canvas.
  void restoreDocumentDirty(bool dirty) => documentDirty.value = dirty;

  void _trackAddedNode(NodeEditorController owner, NodeDataModel node) {
    _schemaIdByEditorId.putIfAbsent(node.id, () => node.id);
    if (_nodeDataByEditorId.containsKey(node.id)) return;
    final parts = node.prototype.idName.split('.');
    if (parts.length == 2 && parts.first != 'trigger') {
      _nodeDataByEditorId[node.id] = {
        'plugin': parts.first,
        'action': parts.last,
      };
    }
  }

  void setActiveNodeIds(Iterable<String> ids) {
    activeNodeIds.value = ids.toSet();
  }

  void setActiveSchemaNodeIds(Iterable<String> ids) {
    final schemaIds = ids.toSet();
    setActiveNodeIds(
      _schemaIdByEditorId.entries
          .where((entry) => schemaIds.contains(entry.value))
          .map((entry) => entry.key),
    );
  }

  String? editorNodeIdForSchema(String schemaId) => _schemaIdByEditorId.entries
      .where((entry) => entry.value == schemaId)
      .map((entry) => entry.key)
      .firstOrNull;

  String? schemaNodeIdForEditor(String editorNodeId) =>
      _schemaIdByEditorId[editorNodeId];

  String? schemaLinkIdForEditorLink(LinkDataModel link) =>
      _schemaIdByLinkSignature[ShowRunnerGraphEditor._linkSignature(
        link.endpoints.sourceNodeId,
        link.endpoints.sourcePortId,
        link.endpoints.targetNodeId,
        link.endpoints.targetPortId,
      )];

  /// Returns the persisted subgraph referenced by an editor node, if any.
  ///
  /// Navigation is intentionally kept in the ShowRunner adapter. The generic
  /// canvas only reports the double-click; it must not know what a subgraph or
  /// a ShowRunner resource is.
  String? subgraphIdForEditor(String editorNodeId) =>
      _nodeDataByEditorId[editorNodeId]?['subgraphId']?.toString();

  List<(String, String)> nodeConfigLines(String editorNodeId) {
    final lines = <(String, String)>[];
    final data = _nodeDataByEditorId[editorNodeId] ?? const <String, dynamic>{};
    if (_variableEditorIds.contains(editorNodeId)) {
      final name = data['name']?.toString().trim();
      if (name != null && name.isNotEmpty) {
        lines.add(('name', name));
      }
      if (data['value'] != null) {
        lines.add(('value', _summarizeGraphValue(data['value'])));
      }
      return lines;
    }
    final config = data['config'];
    if (config is! Map) return lines;
    for (final entry in config.entries) {
      if (lines.length >= 4) break;
      if (entry.value == null) continue;
      lines.add((entry.key.toString(), _summarizeGraphValue(entry.value)));
    }
    if (config.length > lines.length) {
      lines.add(('…', '+${config.length - lines.length} more'));
    }
    return lines;
  }

  void renameNode(String editorNodeId, String title) {
    final normalized = title.trim();
    if (normalized.isEmpty || !controller.nodes.containsKey(editorNodeId)) {
      return;
    }
    _nodeTitles[editorNodeId] = normalized;
    _nodeDataByEditorId.putIfAbsent(editorNodeId, () => {});
    _nodeDataByEditorId[editorNodeId]!['title'] = normalized;
    controller.renameNode(editorNodeId, normalized);
    nodeRevision.value++;
  }

  bool isVariableNode(String editorNodeId) =>
      _variableEditorIds.contains(editorNodeId) &&
      controller.nodes.containsKey(editorNodeId);

  bool isTriggerNode(String editorNodeId) =>
      controller.nodes[editorNodeId]?.prototype.idName.startsWith('trigger.') ??
      false;

  String? replaceTriggerNode(
    String editorNodeId,
    String nodeType, {
    String? title,
  }) {
    final previous = controller.nodes[editorNodeId];
    if (previous == null || !isTriggerNode(editorNodeId)) return null;
    final parts = nodeType.split('.');
    if (parts.length < 3 || parts.first != 'trigger') return null;
    final wasMetadataTrigger = _triggerEditorIds.contains(editorNodeId);
    final schemaId = _schemaIdByEditorId[editorNodeId] ?? editorNodeId;
    final previousData = Map<String, dynamic>.from(
      _nodeDataByEditorId[editorNodeId] ?? const <String, dynamic>{},
    );
    final previousTitle = _nodeTitles[editorNodeId];
    final links = controller.linksAsList
        .where(
          (link) =>
              link.endpoints.sourceNodeId == editorNodeId ||
              link.endpoints.targetNodeId == editorNodeId,
        )
        .toList();
    final linkSchemaIds = {
      for (final link in links)
        ShowRunnerGraphEditor._linkSignature(
          link.endpoints.sourceNodeId,
          link.endpoints.sourcePortId,
          link.endpoints.targetNodeId,
          link.endpoints.targetPortId,
        ): _schemaIdByLinkSignature[ShowRunnerGraphEditor._linkSignature(
          link.endpoints.sourceNodeId,
          link.endpoints.sourcePortId,
          link.endpoints.targetNodeId,
          link.endpoints.targetPortId,
        )],
    };

    controller.removeNodeById(editorNodeId);
    _triggerEditorIds.remove(editorNodeId);
    _schemaIdByEditorId.remove(editorNodeId);
    _nodeDataByEditorId.remove(editorNodeId);
    _nodeTitles.remove(editorNodeId);
    final replacementId = addNodeType(
      nodeType,
      offset: previous.offset,
      title: title ?? previousTitle,
    );
    if (replacementId == null) return null;
    _schemaIdByEditorId[replacementId] = schemaId;
    _nodeDataByEditorId[replacementId] = {
      ...previousData,
      'id': schemaId,
      'plugin': parts[1],
      'trigger': parts.sublist(2).join('.'),
      'config': <String, dynamic>{},
      'stop': previousData['stop'] == true,
    };
    if (title != null && title.trim().isNotEmpty) {
      _nodeTitles[replacementId] = title.trim();
    } else if (previousTitle != null) {
      _nodeTitles[replacementId] = previousTitle;
    }
    if (!wasMetadataTrigger) {
      _triggerEditorIds.remove(replacementId);
      if (_triggerEditorIds.isEmpty) _triggerNodeStateInitialized = false;
    }
    for (final link in links) {
      final sourceNodeId = link.endpoints.sourceNodeId == editorNodeId
          ? replacementId
          : link.endpoints.sourceNodeId;
      final targetNodeId = link.endpoints.targetNodeId == editorNodeId
          ? replacementId
          : link.endpoints.targetNodeId;
      final rewired = link.copyWith(
        endpoints: (
          sourceNodeId: sourceNodeId,
          sourcePortId: link.endpoints.sourcePortId,
          targetNodeId: targetNodeId,
          targetPortId: link.endpoints.targetPortId,
        ),
      );
      controller.addLinkFromExisting(rewired);
      final oldSignature = ShowRunnerGraphEditor._linkSignature(
        link.endpoints.sourceNodeId,
        link.endpoints.sourcePortId,
        link.endpoints.targetNodeId,
        link.endpoints.targetPortId,
      );
      final newSignature = ShowRunnerGraphEditor._linkSignature(
        rewired.endpoints.sourceNodeId,
        rewired.endpoints.sourcePortId,
        rewired.endpoints.targetNodeId,
        rewired.endpoints.targetPortId,
      );
      final schemaLinkId = linkSchemaIds[oldSignature];
      if (schemaLinkId != null) {
        _schemaIdByLinkSignature[newSignature] = schemaLinkId;
      }
    }
    controller.selectNodesById({replacementId});
    nodeRevision.value++;
    return replacementId;
  }

  String? variableNodeType(String editorNodeId) {
    if (!isVariableNode(editorNodeId)) return null;
    final type = _nodeDataByEditorId[editorNodeId]?['type']?.toString();
    return type?.isNotEmpty == true ? type : null;
  }

  void updateVariableNodeName(String editorNodeId, String name) {
    if (!isVariableNode(editorNodeId)) return;
    _nodeDataByEditorId[editorNodeId]!['name'] = name.trim();
    nodeRevision.value++;
  }

  void updateVariableNodeValue(String editorNodeId, dynamic value) {
    if (!isVariableNode(editorNodeId)) return;
    final type = variableNodeType(editorNodeId);
    _nodeDataByEditorId[editorNodeId]!['value'] = _normalizeVariableValue(
      type,
      value,
    );
    nodeRevision.value++;
  }

  String? duplicateSelectedAction() {
    if (controller.selectedNodeIds.length != 1) return null;
    final sourceId = controller.selectedNodeIds.single;
    final source = controller.nodes[sourceId];
    final sourceData = _nodeDataByEditorId[sourceId];
    if (source == null || sourceData == null || isVariableNode(sourceId)) {
      return null;
    }
    final plugin = sourceData['plugin']?.toString();
    final action = sourceData['action']?.toString();
    if (plugin == null || action == null || plugin.isEmpty || action.isEmpty) {
      return null;
    }

    final duplicateId = insertActionAfterNode(
      source.prototype.idName,
      sourceId,
      offset: source.offset + const Offset(280, 0),
    );
    if (duplicateId == null) return null;
    _nodeDataByEditorId[duplicateId] = _cloneJsonMap(sourceData);
    final title = _nodeTitles[sourceId];
    if (title != null) _nodeTitles[duplicateId] = title;
    controller.selectNodesById({duplicateId});
    nodeRevision.value++;
    return duplicateId;
  }

  String? moveSelection(
    LogicalKeyboardKey direction, {
    bool extendSelection = false,
  }) {
    final mappedDirection = switch (direction) {
      LogicalKeyboardKey.arrowRight => NodeNavigationDirection.right,
      LogicalKeyboardKey.arrowLeft => NodeNavigationDirection.left,
      LogicalKeyboardKey.arrowDown => NodeNavigationDirection.down,
      LogicalKeyboardKey.arrowUp => NodeNavigationDirection.up,
      _ => null,
    };
    if (mappedDirection == null) return null;
    return controller.navigateSelection(
      mappedDirection,
      extendSelection: extendSelection,
    );
  }

  String? addVariableNode(
    String type, {
    String? name,
    dynamic value,
    Offset offset = const Offset(80, 80),
  }) {
    if (activeSubgraphId != null || !_variableTypes.contains(type)) return null;
    final variableId = 'variable-${DateTime.now().microsecondsSinceEpoch}';
    final prototypeId = 'variable.$type';
    _ensurePrototype(prototypeId);
    final node = controller.addNode(prototypeId, offset: offset);
    _variableEditorIds.add(node.id);
    _schemaIdByEditorId[node.id] = variableId;
    _nodeDataByEditorId[node.id] = {
      'id': variableId,
      'name': name?.trim() ?? '',
      'type': type,
      'value': _normalizeVariableValue(type, value ?? _variableDefault(type)),
      'x': offset.dx,
      'y': offset.dy,
    };
    nodeRevision.value++;
    return node.id;
  }

  void deleteVariableNode(String editorNodeId) {
    if (!isVariableNode(editorNodeId)) return;
    final schemaId = _schemaIdByEditorId[editorNodeId] ?? editorNodeId;
    _removeEditorNodeFromFrames(editorNodeId);
    controller.removeNodeById(editorNodeId);
    // Links that failed to hydrate are kept for diagnostics. Once their
    // source/target resource is deleted they must be removed as well,
    // otherwise saving resurrects a dangling wire.
    for (final entry in _invalidDataWiresByGraph.entries) {
      entry.value.removeWhere(
        (wire) => wire.fromNode == schemaId || wire.toNode == schemaId,
      );
    }
    _variableEditorIds.remove(editorNodeId);
    _schemaIdByEditorId.remove(editorNodeId);
    _nodeDataByEditorId.remove(editorNodeId);
    _nodeTitles.remove(editorNodeId);
    nodeRevision.value++;
  }

  void setSearchQuery(String query) {
    _searchService.setQuery(query);
  }

  void openCanvasSearch() {
    _searchService.open();
  }

  void closeCanvasSearch() {
    _searchService.close();
  }

  Set<String> searchNodeIds([String? query]) {
    return _searchService.nodeIds(query);
  }

  void focusSearchResults() {
    _searchService.focusResults();
  }

  int searchResultCount() => _searchService.resultCount;

  String? focusSearchResult({bool forward = true}) =>
      _searchService.focusResult(forward: forward);

  void loadSampleGraph() => _loadGraphFixture();

  void _loadGraphFixture() {
    final wasSuspended = _suspendDirtyTracking;
    var completed = false;
    _suspendDirtyTracking = true;
    try {
      controller.clear();
      _frameColors.clear();
      _syncFrameProjection(controller);
      selectedFrameId.value = null;
      clearInvalidSelection();
      subgraphs.value = const [];
      _entryNodeIdByGraph.clear();
      searchMatchIndex.value = 0;
      searchQuery.value = '';
      graphFeedback.value = null;
      _variableEditorIds.clear();
      _triggerEditorIds.clear();
      _triggerNodeStateInitialized = false;
      _nodeDataByEditorId.clear();
      _nodeTitles.clear();
      _schemaIdByEditorId.clear();
      _schemaIdByLinkSignature.clear();
      _invalidFlowEdgesByGraph.clear();
      _invalidDataWiresByGraph.clear();
      final trigger =
          controller.nodes[addNodeType(
            'trigger.twitch.chat',
            offset: const Offset(-420, -80),
          )!]!;
      final queue =
          controller.nodes[addNodeType(
            'ShowRunner.addToQueue',
            offset: const Offset(-80, -80),
          )!]!;
      final overlay =
          controller.nodes[addNodeType(
            'overlays.pushChatMessage',
            offset: const Offset(260, -80),
          )!]!;

      controller.addLink(trigger.id, 'completed', queue.id, 'exec');
      controller.addLink(queue.id, 'completed', overlay.id, 'exec');
      completed = true;
    } finally {
      _suspendDirtyTracking = wasSuspended;
      if (completed) markDocumentClean();
    }
  }

  String? addNodeType(
    String nodeType, {
    String? title,
    Offset offset = const Offset(80, 80),
  }) {
    _ensurePrototype(nodeType, title: title);
    final node = controller.addNode(nodeType, offset: offset);
    _registerNodeMetadata(node, nodeType, title: title);
    if (title != null && title.trim().isNotEmpty) {
      renameNode(node.id, title);
    }
    _markDocumentDirty();
    return node.id;
  }

  NodeDataModel _createDetachedNodeType(
    String nodeType, {
    String? title,
    required Offset offset,
  }) {
    _ensurePrototype(nodeType, title: title);
    final node = controller.createNodeModel(nodeType, offset: offset);
    _registerNodeMetadata(node, nodeType, title: title);
    if (title != null && title.trim().isNotEmpty) {
      node.customTitle = title.trim();
    }
    return node;
  }

  void _registerNodeMetadata(
    NodeDataModel node,
    String nodeType, {
    String? title,
  }) {
    final parts = nodeType.split('.');
    _schemaIdByEditorId[node.id] = node.id;
    if (parts.length >= 3 && parts.first == 'trigger') {
      _triggerEditorIds.add(node.id);
      _triggerNodeStateInitialized = true;
      _nodeDataByEditorId[node.id] = {
        'id': node.id,
        'plugin': parts[1],
        'trigger': parts.sublist(2).join('.'),
        'config': <String, dynamic>{},
        'stop': false,
      };
    } else if (parts.length == 2 && parts.first != 'trigger') {
      final resultMapping = _resultMappingForAction(nodeType);
      _nodeDataByEditorId[node.id] = {
        'plugin': parts.first,
        'action': parts.last,
        if (resultMapping.isNotEmpty) 'resultMapping': resultMapping,
        if (_isCoreConversionAction(parts.first, parts.last)) ...{
          'config': _defaultCoreConversionConfig(parts.last),
          'resultMapping': _defaultCoreConversionResultMapping(parts.last),
        },
      };
    } else if (parts.length >= 3 && parts.first == 'trigger') {
      _nodeDataByEditorId[node.id] = {
        'plugin': parts[1],
        'trigger': parts.sublist(2).join('.'),
      };
    } else {
      final defaults = _defaultControlData(nodeType);
      if (defaults != null) _nodeDataByEditorId[node.id] = defaults;
    }
    final normalizedTitle = title?.trim();
    if (normalizedTitle != null && normalizedTitle.isNotEmpty) {
      _nodeTitles[node.id] = normalizedTitle;
      _nodeDataByEditorId.putIfAbsent(node.id, () => {});
      _nodeDataByEditorId[node.id]!['title'] = normalizedTitle;
    }
  }

  void updateControlNodeData(String editorNodeId, JsonMap data) {
    final node = controller.nodes[editorNodeId];
    if (node == null ||
        !ShowRunnerGraphEditor.isControlFlowType(node.prototype.idName)) {
      return;
    }
    _nodeDataByEditorId[editorNodeId] = {
      ...?_nodeDataByEditorId[editorNodeId],
      ...Map<String, dynamic>.from(data),
    };
    nodeRevision.value++;
  }

  void autoLayout() {
    final nodes = controller.nodes.values.toList();
    final positions = <String, Offset>{};
    for (var index = 0; index < nodes.length; index++) {
      final column = index % 4;
      final row = index ~/ 4;
      final node = nodes[index];
      positions[node.id] = Offset(column * 280.0, row * 180.0);
    }
    controller.applyLayout(positions);
  }

  void fitGraph() {
    controller.focusNodesById(controller.nodes.keys.toSet(), animate: false);
  }
}
