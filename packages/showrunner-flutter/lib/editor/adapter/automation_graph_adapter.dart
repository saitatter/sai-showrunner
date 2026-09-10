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
    if (_suspendDirtyTracking || !isNodeEditorContentMutation(event)) {
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
      lines.add(('â€¦', '+${config.length - lines.length} more'));
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

  void _registerPrototypes(NodeEditorController target) {
    target.registerNodePrototype(
      _prototype(
        idName: 'trigger.twitch.chat',
        title: 'Chat Message',
        color: const Color(0xff2563eb),
        input: false,
        output: true,
        dataOutputs: _eventFieldsForTrigger('trigger.twitch.chat'),
      ),
    );
    target.registerNodePrototype(
      _prototype(
        idName: 'if',
        title: 'If',
        color: const Color(0xff7c3aed),
        input: true,
        output: false,
        flowOutputs: const ['then', 'else'],
      ),
    );
    target.registerNodePrototype(
      _prototype(
        idName: 'switch',
        title: 'Switch',
        color: const Color(0xff9333ea),
        input: true,
        output: false,
        flowOutputs: const ['case:0', 'default'],
      ),
    );
    for (final definition in const [
      (type: 'for', title: 'For', color: Color(0xff0891b2)),
      (type: 'forEach', title: 'For each', color: Color(0xff0e7490)),
      (type: 'while', title: 'While', color: Color(0xff155e75)),
    ]) {
      target.registerNodePrototype(
        _prototype(
          idName: definition.type,
          title: definition.title,
          color: definition.color,
          input: true,
          output: false,
          flowOutputs: const ['body', 'next'],
        ),
      );
    }
    for (final definition in const [
      (type: 'break', title: 'Break', color: Color(0xffbe123c)),
      (type: 'continue', title: 'Continue', color: Color(0xffbe123c)),
      (type: 'return', title: 'Return', color: Color(0xffbe123c)),
    ]) {
      target.registerNodePrototype(
        _prototype(
          idName: definition.type,
          title: definition.title,
          color: definition.color,
          input: true,
          output: false,
        ),
      );
    }
    for (final definition in const [
      (type: 'string', title: 'String variable', color: Color(0xff81c784)),
      (type: 'number', title: 'Number variable', color: Color(0xff4fc3f7)),
      (type: 'boolean', title: 'Boolean variable', color: Color(0xffffb74d)),
      (type: 'color', title: 'Color variable', color: Color(0xfff06292)),
    ]) {
      target.registerNodePrototype(
        _variablePrototype(
          type: definition.type,
          title: definition.title,
          color: definition.color,
        ),
      );
    }
  }

  NodePrototype _variablePrototype({
    required String type,
    required String title,
    required Color color,
  }) {
    _prototypeTitles['variable.$type'] = title;
    return NodePrototype(
      idName: 'variable.$type',
      displayName: (_) => title,
      description: (_) => 'ShowRunner variable node: $title',
      styleBuilder: (state) => graphNodeStyle(state, color),
      ports: [
        _typedPort(
          idName: 'value',
          label: 'Set',
          kind: _kindForVariableType(type),
          input: true,
        ),
        _typedPort(
          idName: 'value',
          label: 'Value',
          kind: _kindForVariableType(type),
          input: false,
        ),
      ],
      onExecute: (ports, fields, state, forward, put) async {},
    );
  }

  PortPrototype _subgraphPort(JsonMap port, {required bool input}) {
    final id = port['name']?.toString().trim() ?? '';
    final label = port['label']?.toString().trim();
    return _typedPort(
      idName: id,
      label: label == null || label.isEmpty ? id : label,
      kind: _kindForTypeName(port['type']?.toString()),
      input: input,
    );
  }

  PortPrototype _dataPort(DartDataInputSchema schema, {required bool input}) =>
      _typedPort(
        idName: schema.key ?? schema.label,
        label: schema.label,
        kind: schema.kind,
        input: input,
      );

  /// Creates the concrete generic port instance required by sai_nodes. Using
  /// a real generic type here is important: sai_nodes uses it to reject an
  /// invalid data connection before it reaches the persisted graph.
  PortPrototype _typedPort({
    required String idName,
    required String label,
    required DartDataInputKind kind,
    required bool input,
  }) {
    final normalizedId = idName.trim().isEmpty ? label : idName.trim();
    final normalizedLabel = label.trim().isEmpty ? normalizedId : label;
    if (input) {
      return switch (kind) {
        DartDataInputKind.text ||
        DartDataInputKind.multilineText ||
        DartDataInputKind.enumeration ||
        DartDataInputKind.color ||
        DartDataInputKind.lightColor ||
        DartDataInputKind.filePath ||
        DartDataInputKind.resource ||
        DartDataInputKind.keyboardKey => DataInputPortPrototype<String>(
          idName: normalizedId,
          displayName: (_) => normalizedLabel,
          styleBuilder: _dataPortStyleBuilder(kind),
        ),
        DartDataInputKind.number ||
        DartDataInputKind.duration => DataInputPortPrototype<num>(
          idName: normalizedId,
          displayName: (_) => normalizedLabel,
          styleBuilder: _dataPortStyleBuilder(kind),
        ),
        DartDataInputKind.boolean => DataInputPortPrototype<bool>(
          idName: normalizedId,
          displayName: (_) => normalizedLabel,
          styleBuilder: _dataPortStyleBuilder(kind),
        ),
        DartDataInputKind.array ||
        DartDataInputKind.keyCombo => DataInputPortPrototype<List<dynamic>>(
          idName: normalizedId,
          displayName: (_) => normalizedLabel,
          styleBuilder: _dataPortStyleBuilder(kind),
        ),
        DartDataInputKind.object || DartDataInputKind.obsTransform =>
          DataInputPortPrototype<Map<String, dynamic>>(
            idName: normalizedId,
            displayName: (_) => normalizedLabel,
            styleBuilder: _dataPortStyleBuilder(kind),
          ),
      };
    }
    return switch (kind) {
      DartDataInputKind.text ||
      DartDataInputKind.multilineText ||
      DartDataInputKind.enumeration ||
      DartDataInputKind.color ||
      DartDataInputKind.lightColor ||
      DartDataInputKind.filePath ||
      DartDataInputKind.resource ||
      DartDataInputKind.keyboardKey => DataOutputPortPrototype<String>(
        idName: normalizedId,
        displayName: (_) => normalizedLabel,
        styleBuilder: _dataPortStyleBuilder(kind),
      ),
      DartDataInputKind.number ||
      DartDataInputKind.duration => DataOutputPortPrototype<num>(
        idName: normalizedId,
        displayName: (_) => normalizedLabel,
        styleBuilder: _dataPortStyleBuilder(kind),
      ),
      DartDataInputKind.boolean => DataOutputPortPrototype<bool>(
        idName: normalizedId,
        displayName: (_) => normalizedLabel,
        styleBuilder: _dataPortStyleBuilder(kind),
      ),
      DartDataInputKind.array ||
      DartDataInputKind.keyCombo => DataOutputPortPrototype<List<dynamic>>(
        idName: normalizedId,
        displayName: (_) => normalizedLabel,
        styleBuilder: _dataPortStyleBuilder(kind),
      ),
      DartDataInputKind.object || DartDataInputKind.obsTransform =>
        DataOutputPortPrototype<Map<String, dynamic>>(
          idName: normalizedId,
          displayName: (_) => normalizedLabel,
          styleBuilder: _dataPortStyleBuilder(kind),
        ),
    };
  }

  DartDataInputKind _kindForVariableType(String type) => _kindForTypeName(type);

  DartDataInputKind _kindForTypeName(String? type) =>
      switch (type?.trim().toLowerCase()) {
        'string' || 'text' => DartDataInputKind.text,
        'number' || 'num' || 'double' || 'int' => DartDataInputKind.number,
        'boolean' || 'bool' => DartDataInputKind.boolean,
        'array' || 'list' => DartDataInputKind.array,
        'object' || 'map' || 'json' => DartDataInputKind.object,
        'color' => DartDataInputKind.color,
        _ => DartDataInputKind.object,
      };

  PortStyle _flowPortStyleBuilder(PortState state) =>
      _portStyle(const Color(0xffe9aaff), state);

  PortStyle Function(PortState) _dataPortStyleBuilder(DartDataInputKind kind) =>
      (state) => _portStyle(_dataPortColor(kind), state);

  PortStyle _portStyle(Color color, PortState state) => PortStyle(
    shape: PortShape.circle,
    color: color,
    radius: state.isHovered ? 7 : 5,
    linkStyleBuilder: (link) => LinkStyle(
      color: link.isSelected ? const Color(0xffffcc00) : color,
      lineWidth: link.isSelected ? 3.5 : 2.5,
      drawMode: LineDrawMode.solid,
      curveType: LinkCurveType.bezier,
    ),
  );

  Color _dataPortColor(DartDataInputKind kind) => switch (kind) {
    DartDataInputKind.text ||
    DartDataInputKind.multilineText ||
    DartDataInputKind.enumeration ||
    DartDataInputKind.filePath ||
    DartDataInputKind.resource ||
    DartDataInputKind.keyboardKey => const Color(0xff81c784),
    DartDataInputKind.number ||
    DartDataInputKind.duration => const Color(0xff4fc3f7),
    DartDataInputKind.boolean => const Color(0xffffb74d),
    DartDataInputKind.object ||
    DartDataInputKind.obsTransform => const Color(0xffce93d8),
    DartDataInputKind.array ||
    DartDataInputKind.keyCombo => const Color(0xffa1887f),
    DartDataInputKind.color ||
    DartDataInputKind.lightColor => const Color(0xfff06292),
  };

  NodePrototype _prototype({
    required String idName,
    required String title,
    required Color color,
    required bool input,
    required bool output,
    bool hasPayloadInput = false,
    bool hasPayloadOutput = false,
    List<String>? flowOutputs,
    List<DartDataInputSchema> dataInputs = const [],
    List<DartDataInputSchema> dataOutputs = const [],
    List<FieldPrototype> fields = const [],
  }) {
    _prototypeTitles[idName] = title;
    return NodePrototype(
      idName: idName,
      displayName: (_) => title,
      description: (_) => 'ShowRunner graph node: $title',
      styleBuilder: (state) => graphNodeStyle(
        state,
        idName.startsWith('trigger.') ? const Color(0xffe9aaff) : color,
        trigger: idName.startsWith('trigger.'),
      ),
      ports: [
        if (input)
          ControlInputPortPrototype(
            idName: 'exec',
            displayName: (_) => 'Execute',
            styleBuilder: _flowPortStyleBuilder,
          ),
        for (final dataInput in dataInputs) _dataPort(dataInput, input: true),
        if (hasPayloadInput)
          _typedPort(
            idName: 'payload',
            label: 'Payload',
            kind: DartDataInputKind.object,
            input: true,
          ),
        if (output || flowOutputs != null)
          ...((flowOutputs ?? const ['completed']).map(
            (port) => ControlOutputPortPrototype(
              idName: port,
              displayName: (_) => _flowPortLabel(port),
              styleBuilder: _flowPortStyleBuilder,
            ),
          )),
        if (hasPayloadOutput)
          _typedPort(
            idName: 'payload',
            label: 'Payload',
            kind: DartDataInputKind.object,
            input: false,
          ),
        for (final dataOutput in dataOutputs)
          _dataPort(dataOutput, input: false),
      ],
      fields: fields,
      onExecute: (ports, fields, state, forward, put) async {
        if (output) await forward({'completed'});
      },
    );
  }

  /// Loads the canonical graph fixture used by the desktop shell.
  ///
  /// It uses real trigger/action contracts so the initial workspace is a
  /// valid product graph, rather than an editor-only demonstration.
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
    recentNodeTypes.value = [
      nodeType,
      ...recentNodeTypes.value.where((type) => type != nodeType),
    ].take(8).toList();
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

  void _ensurePrototype(
    String nodeType, {
    String? title,
    NodeEditorController? target,
  }) {
    final editor = target ?? controller;
    if (editor.nodePrototypes.containsKey(nodeType)) return;
    if (_isCoreConversionNodeType(nodeType)) {
      _registerCoreConversionPrototype(nodeType, target: editor);
      return;
    }
    final isTrigger = nodeType.startsWith('trigger.');
    final triggerFields = _eventFieldsForTrigger(nodeType);
    final prototypeTitle = _manifestDisplayName(nodeType) ?? title ?? nodeType;
    editor.registerNodePrototype(
      _prototype(
        idName: nodeType,
        title: prototypeTitle,
        color: _prototypeColor(nodeType),
        input: !isTrigger,
        output: true,
        dataInputs: _configFieldsForAction(nodeType),
        hasPayloadOutput: isTrigger && triggerFields.isEmpty,
        dataOutputs: isTrigger
            ? triggerFields
            : _resultFieldsForAction(nodeType),
      ),
    );
  }

  Color _prototypeColor(String nodeType) {
    final normalized = nodeType.toLowerCase();
    if (normalized.startsWith('trigger.')) return const Color(0xff60a5fa);
    if (_isCoreConversionNodeType(nodeType)) {
      return const Color(0xff4dd0e1);
    }
    if (normalized.startsWith('variable.')) return const Color(0xff90a4ae);
    if (normalized.startsWith('showrunner.') &&
        (normalized.contains('queue') || normalized.endsWith('.skip'))) {
      return const Color(0xffffcf5a);
    }
    if (normalized == 'overlays.pushchatmessage') {
      return const Color(0xff34d399);
    }
    return const Color(0xff7d32d4);
  }

  String? _manifestDisplayName(String nodeType) {
    final parts = nodeType.split('.');
    if (parts.length == 2) {
      return _registry.findAction(parts.first, parts.last)?.displayName;
    }
    if (parts.length >= 3 && parts.first == 'trigger') {
      return _registry
          .findTrigger(parts[1], parts.sublist(2).join('.'))
          ?.displayName;
    }
    return null;
  }

  List<DartDataInputSchema> _resultFieldsForAction(String nodeType) {
    final parts = nodeType.split('.');
    if (parts.length != 2) return const [];
    final schema = _registry.findAction(parts.first, parts.last)?.resultSchema;
    return _objectSchemaFields(schema);
  }

  List<DartDataInputSchema> _configFieldsForAction(String nodeType) {
    final parts = nodeType.split('.');
    if (parts.length != 2) return const [];
    final schema = _registry.findAction(parts.first, parts.last)?.configSchema;
    return _objectSchemaFields(schema);
  }

  List<DartDataInputSchema> _eventFieldsForTrigger(String nodeType) {
    final parts = nodeType.split('.');
    if (parts.length < 3 || parts.first != 'trigger') return const [];
    final schema = _registry
        .findTrigger(parts[1], parts.sublist(2).join('.'))
        ?.eventSchema;
    return _objectSchemaFields(schema);
  }

  List<DartDataInputSchema> _objectSchemaFields(DartDataInputSchema? schema) {
    if (schema?.kind != DartDataInputKind.object) return const [];
    // The reference editor limits the visible port list so a node remains
    // readable. The complete schema is still available in the configuration
    // editor and runtime.
    return schema!.fields
        .where((field) => (field.key ?? field.label).trim().isNotEmpty)
        .take(8)
        .toList(growable: false);
  }

  JsonMap _resultMappingForAction(String nodeType) {
    final fields = _resultFieldsForAction(nodeType);
    return {
      for (final field in fields)
        field.key ?? field.label: field.key ?? field.label,
    };
  }

  void _registerCoreConversionPrototype(
    String nodeType, {
    required NodeEditorController target,
  }) {
    final actionId = nodeType.substring(nodeType.indexOf('.') + 1);
    final normalized = _normalizeActionId(actionId);
    final hasFallback =
        normalized == 'convertstringtonumber' ||
        normalized == 'convertstringtoboolean';
    final hasConverted =
        hasFallback ||
        normalized == 'convertjsonstringtoobject' ||
        normalized == 'convertjsonstringtoarray';
    final title = actionId
        .replaceAllMapped(
          RegExp(r'([a-z])([A-Z])'),
          (match) => '${match[1]} ${match[2]}',
        )
        .replaceFirstMapped(RegExp(r'^convert'), (match) => 'Convert ');
    _prototypeTitles[nodeType] = title;
    target.registerNodePrototype(
      NodePrototype(
        idName: nodeType,
        displayName: (_) => title,
        description: (_) => 'ShowRunner data conversion: $title',
        styleBuilder: (state) => graphNodeStyle(state, const Color(0xff4dd0e1)),
        ports: [
          _typedPort(
            idName: _conversionInputPort('value'),
            label: 'Value',
            kind: _conversionValueKind(normalized),
            input: true,
          ),
          if (hasFallback)
            _typedPort(
              idName: _conversionInputPort('fallback'),
              label: 'Fallback',
              kind: normalized == 'convertstringtoboolean'
                  ? DartDataInputKind.boolean
                  : DartDataInputKind.number,
              input: true,
            ),
          _typedPort(
            idName: 'value',
            label: 'Value',
            kind: _conversionResultKind(normalized),
            input: false,
          ),
          if (hasConverted)
            _typedPort(
              idName: 'converted',
              label: 'Converted',
              kind: DartDataInputKind.boolean,
              input: false,
            ),
        ],
        onExecute: (ports, fields, state, forward, put) async {},
      ),
    );
  }

  DartDataInputKind _conversionValueKind(String normalized) =>
      switch (normalized) {
        'convertnumbertostring' ||
        'convertnumbertoboolean' => DartDataInputKind.number,
        'convertbooleantostring' ||
        'convertbooleantonumber' => DartDataInputKind.boolean,
        'convertstringtonumber' ||
        'convertstringtoboolean' => DartDataInputKind.text,
        'convertobjecttojsonstring' => DartDataInputKind.object,
        'convertarraytojsonstring' => DartDataInputKind.array,
        'convertjsonstringtoobject' ||
        'convertjsonstringtoarray' => DartDataInputKind.multilineText,
        _ => DartDataInputKind.object,
      };

  DartDataInputKind _conversionResultKind(String normalized) =>
      switch (normalized) {
        'convertnumbertostring' ||
        'convertbooleantostring' ||
        'convertobjecttojsonstring' ||
        'convertarraytojsonstring' => DartDataInputKind.text,
        'convertstringtonumber' ||
        'convertbooleantonumber' => DartDataInputKind.number,
        'convertstringtoboolean' ||
        'convertnumbertoboolean' => DartDataInputKind.boolean,
        'convertjsonstringtoobject' => DartDataInputKind.object,
        'convertjsonstringtoarray' => DartDataInputKind.array,
        _ => DartDataInputKind.object,
      };

  String _conversionInputPort(String name) => 'input:$name';

  String _editorDataInputPortId(NodeDataModel node, String schemaPort) {
    if (_isCoreConversionNodeType(node.prototype.idName)) {
      final inputPort = _conversionInputPort(schemaPort);
      if (node.ports.containsKey(inputPort)) return inputPort;
    }
    return schemaPort;
  }

  String _editorDataOutputPortId(NodeDataModel node, String schemaPort) =>
      schemaPort;

  String _schemaDataPortName(NodeDataModel? node, String editorPort) {
    if (node != null && _isCoreConversionNodeType(node.prototype.idName)) {
      const prefix = 'input:';
      if (editorPort.startsWith(prefix)) {
        return editorPort.substring(prefix.length);
      }
    }
    return editorPort;
  }

  bool _isCoreConversionNodeType(String nodeType) {
    final separator = nodeType.indexOf('.');
    return separator > 0 &&
        _isCoreConversionAction(
          nodeType.substring(0, separator),
          nodeType.substring(separator + 1),
        );
  }

  String? _firstFlowOutputPort(NodeDataModel node) =>
      _preferredFlowOutputPort(node);

  String? _preferredFlowOutputPort(NodeDataModel? node) {
    if (node == null) return null;
    final preferred = ['completed', 'out'];
    for (final port in preferred) {
      final data = node.ports[port];
      if (data?.prototype.type == PortType.control &&
          data?.prototype.direction == PortDirection.output) {
        return port;
      }
    }
    return node.ports.values
        .where(
          (port) =>
              port.prototype.type == PortType.control &&
              port.prototype.direction == PortDirection.output,
        )
        .map((port) => port.prototype.idName)
        .firstOrNull;
  }

  String? _firstControlInputPort(NodeDataModel? node) {
    if (node == null) return null;
    return node.ports.values
        .where(
          (port) =>
              port.prototype.type == PortType.control &&
              port.prototype.direction == PortDirection.input,
        )
        .map((port) => port.prototype.idName)
        .firstOrNull;
  }

  void _registerSwitchPrototype(
    Iterable<String> ports, {
    NodeEditorController? target,
  }) {
    final editor = target ?? controller;
    if (editor.nodePrototypes.containsKey('switch')) {
      editor.unregisterNodePrototype('switch');
    }
    editor.registerNodePrototype(
      _prototype(
        idName: 'switch',
        title: 'Switch',
        color: const Color(0xff9333ea),
        input: true,
        output: false,
        flowOutputs: ports.toSet().toList(),
      ),
    );
  }

  JsonMap? _defaultControlData(String type) => switch (type) {
    'if' => {
      'condition': {'type': 'literal', 'value': true},
    },
    'switch' => {
      'expression': {'type': 'literal', 'value': ''},
      'cases': [
        {'value': 'case1', 'port': 'case:0'},
      ],
    },
    'for' => {
      'variable': 'i',
      'start': {'type': 'literal', 'value': 0},
      'end': {'type': 'literal', 'value': 10},
      'step': {'type': 'literal', 'value': 1},
    },
    'forEach' => {
      'variable': 'item',
      'collection': {'type': 'literal', 'value': []},
    },
    'while' => {
      'condition': {'type': 'literal', 'value': true},
      'maxIterations': 1000,
    },
    _ => null,
  };

  dynamic _coerceSubgraphDefault(String type, dynamic value) {
    switch (type) {
      case 'number':
        return value is num ? value : num.tryParse('$value') ?? 0;
      case 'boolean':
        return value is bool ? value : value.toString().toLowerCase() == 'true';
      case 'array':
        if (value is List) return value;
        try {
          final decoded = jsonDecode(value.toString());
          return decoded is List ? decoded : const <dynamic>[];
        } on FormatException {
          return const <dynamic>[];
        }
      case 'object':
        if (value is Map) return Map<String, dynamic>.from(value);
        try {
          final decoded = jsonDecode(value.toString());
          return decoded is Map
              ? Map<String, dynamic>.from(decoded)
              : <String, dynamic>{};
        } on FormatException {
          return <String, dynamic>{};
        }
      case 'color':
      case 'string':
      case 'any':
      default:
        return value?.toString() ?? '';
    }
  }

  bool _isCoreConversionAction(String pluginId, String actionId) =>
      pluginId.toLowerCase() == 'showrunner' &&
      _coreConversionActions.contains(_normalizeActionId(actionId));

  JsonMap _defaultCoreConversionConfig(String actionId) {
    return switch (_normalizeActionId(actionId)) {
      'convertnumbertostring' || 'convertnumbertoboolean' => {'value': 0},
      'convertbooleantostring' || 'convertbooleantonumber' => {'value': false},
      'convertstringtonumber' => {'value': '', 'fallback': 0},
      'convertstringtoboolean' => {'value': '', 'fallback': false},
      'convertobjecttojsonstring' => {'value': <String, dynamic>{}},
      'convertarraytojsonstring' => {'value': <dynamic>[]},
      'convertjsonstringtoobject' => {'value': '{}'},
      'convertjsonstringtoarray' => {'value': '[]'},
      _ => <String, dynamic>{},
    };
  }

  JsonMap _defaultCoreConversionResultMapping(String actionId) => {
    'value': 'value',
    if ({
      'convertstringtonumber',
      'convertstringtoboolean',
      'convertjsonstringtoobject',
      'convertjsonstringtoarray',
    }.contains(_normalizeActionId(actionId)))
      'converted': 'converted',
  };

  String _normalizeActionId(String actionId) =>
      actionId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();

  dynamic _variableDefault(String type) => switch (type) {
    'number' => 0,
    'boolean' => true,
    'color' => '#ffffff',
    _ => '',
  };

  dynamic _normalizeVariableValue(String? type, dynamic value) {
    if (value == null) return _variableDefault(type ?? 'string');
    return switch (type) {
      'number' => value is num ? value : num.tryParse(value.toString()) ?? 0,
      'boolean' =>
        value is bool
            ? value
            : value.toString().toLowerCase() == 'true' ||
                  value.toString() == '1',
      'color' => value.toString(),
      _ => value.toString(),
    };
  }

  void fitGraph() {
    controller.focusNodesById(controller.nodes.keys.toSet(), animate: false);
  }
}
