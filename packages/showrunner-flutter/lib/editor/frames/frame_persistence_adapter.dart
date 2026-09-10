part of '../showrunner_graph_editor.dart';

/// ShowRunner's product-specific frame adapter.
///
/// Geometry, membership, movement, resize history, and frame events are owned
/// by sai_nodes. This layer maps persisted ShowRunner node IDs and keeps
/// ShowRunner-only frame colors and selection state.
extension ShowRunnerFramePersistenceAdapter on ShowRunnerGraphEditor {
  String frameColor(String frameId) => _frameColors[frameId] ?? '#64b5f6';

  void frameSelection({String title = 'Frame'}) {
    final selected = controller.selectedNodeIds
        .map((id) => controller.nodes[id])
        .whereType<NodeDataModel>()
        .toList();
    final selectedSchemaIds = selected
        .map((node) => _schemaIdByEditorId[node.id])
        .whereType<String>()
        .toList();
    final bounds = selected.isEmpty
        ? Rect.fromLTWH(
            controller.viewportOffset.dx + 96,
            controller.viewportOffset.dy + 96,
            360,
            200,
          )
        : Rect.fromLTRB(
            selected
                    .map((node) => _nodeWorldBounds(node).left)
                    .reduce(math.min) -
                24,
            selected
                    .map((node) => _nodeWorldBounds(node).top)
                    .reduce(math.min) -
                44,
            selected
                    .map((node) => _nodeWorldBounds(node).right)
                    .reduce(math.max) +
                24,
            selected
                    .map((node) => _nodeWorldBounds(node).bottom)
                    .reduce(math.max) +
                24,
          );
    final framePrefix = 'frame-${DateTime.now().microsecondsSinceEpoch}';
    var frameId = framePrefix;
    var frameSuffix = 1;
    while (controller.frames.containsKey(frameId)) {
      frameId = '$framePrefix-$frameSuffix';
      frameSuffix++;
    }
    _frameColors[frameId] = '#64b5f6';
    controller.createFrame(
      id: frameId,
      title: title,
      bounds: bounds,
      members: selected.map((node) => node.id),
    );
    _syncFrameProjection(controller);
    if (selectedSchemaIds.isNotEmpty) {
      _placeSchemaNodesInFrame(frameId, selectedSchemaIds);
    }
  }

  void selectFrame(String? frameId) {
    clearInvalidSelection();
    selectedFrameId.value =
        frameId != null && controller.frames.containsKey(frameId)
        ? frameId
        : null;
  }

  void renameFrame(String frameId, String title) {
    if (controller.renameFrame(frameId, title) != null) {
      _syncFrameProjection(controller);
    }
  }

  void updateFrameColor(String frameId, String color) {
    if (!controller.frames.containsKey(frameId)) return;
    final normalized = color.trim().isEmpty ? '#64b5f6' : color.trim();
    if (_frameColors[frameId] == normalized) return;
    _frameColors[frameId] = normalized;
    _syncFrameProjection(controller);
    _markDocumentDirty();
  }

  void addSelectionToSelectedFrame() {
    final frameId = selectedFrameId.value;
    if (frameId == null) return;
    final selectedSchemaIds = controller.selectedNodeIds
        .map((id) => _schemaIdByEditorId[id])
        .whereType<String>();
    addNodesToFrame(frameId, selectedSchemaIds);
  }

  void addNodesToFrame(String frameId, Iterable<String> nodeIds) {
    final editorIds = nodeIds
        .map(editorNodeIdForSchema)
        .whereType<String>()
        .where(controller.nodes.containsKey);
    if (controller.addNodesToFrame(frameId, editorIds) != null) {
      _syncFrameProjection(controller);
    }
  }

  bool placeDraggedNodesInFrame(String? frameId, Iterable<String> nodeIds) =>
      _placeSchemaNodesInFrame(frameId, nodeIds);

  String? frameForNodes(Iterable<String> nodeIds) {
    final memberBounds = _schemaNodeBounds(nodeIds);
    if (memberBounds == null) return null;
    final center = memberBounds.center;
    return controller.frames.values
        .where((frame) => frame.bounds.contains(center))
        .map((frame) => frame.id)
        .firstOrNull;
  }

  List<String> frameIdsForNodes(Iterable<String> nodeIds) {
    final ids = nodeIds.map(editorNodeIdForSchema).whereType<String>().toSet();
    if (ids.isEmpty) return const [];
    return controller.frames.values
        .where((frame) => frame.members.any(ids.contains))
        .map((frame) => frame.id)
        .toList();
  }

  void removeSelectionFromSelectedFrame() {
    final frameId = selectedFrameId.value;
    if (frameId == null) return;
    final selectedSchemaIds = controller.selectedNodeIds
        .map((id) => _schemaIdByEditorId[id])
        .whereType<String>()
        .toSet();
    final editorIds = selectedSchemaIds
        .map(editorNodeIdForSchema)
        .whereType<String>();
    if (controller.removeNodesFromFrame(frameId, editorIds) != null) {
      _syncFrameProjection(controller);
    }
  }

  void clearSelectedFrameNodes() {
    final frameId = selectedFrameId.value;
    if (frameId == null) return;
    final members = controller.frames[frameId]?.members;
    if (members == null || members.isEmpty) return;
    if (controller.removeNodesFromFrame(frameId, members) != null) {
      _syncFrameProjection(controller);
    }
  }

  void moveFrame(String frameId, Offset worldDelta) {
    if (controller.moveFrameWithMembers(frameId, worldDelta) != null) {
      _syncFrameProjection(controller);
    }
  }

  bool _placeDraggedNodesInFrame(Set<String> editorNodeIds) {
    final schemaIds = editorNodeIds
        .map((id) => _schemaIdByEditorId[id])
        .whereType<String>()
        .toSet();
    if (schemaIds.isEmpty) return false;
    return _placeSchemaNodesInFrame(frameForNodes(schemaIds), schemaIds);
  }

  bool _placeSchemaNodesInFrame(String? frameId, Iterable<String> nodeIds) {
    final editorIds = nodeIds
        .map(editorNodeIdForSchema)
        .whereType<String>()
        .where(controller.nodes.containsKey)
        .toSet();
    if (editorIds.isEmpty) return false;
    final targetExists =
        frameId != null && controller.frames.containsKey(frameId);
    var changed = false;
    for (final frame in [...controller.frames.values]) {
      if (frame.id == frameId) continue;
      final remove = editorIds.where(frame.members.contains).toList();
      if (remove.isNotEmpty) {
        controller.removeNodesFromFrame(frame.id, remove);
        changed = true;
      }
    }
    if (targetExists) {
      final target = controller.frames[frameId]!;
      final add = editorIds.where((id) => !target.members.contains(id));
      if (add.isNotEmpty) {
        controller.addNodesToFrame(frameId, add);
        changed = true;
      }
    }
    if (changed) _syncFrameProjection(controller);
    return changed;
  }

  void _removeEditorNodeFromFrames(String editorNodeId) {
    final schemaId = _schemaIdByEditorId[editorNodeId];
    if (schemaId == null) return;
    _placeSchemaNodesInFrame(null, [schemaId]);
  }

  Rect? _schemaNodeBounds(Iterable<String> schemaIds) {
    final nodes = schemaIds
        .map(editorNodeIdForSchema)
        .whereType<String>()
        .map((id) => controller.nodes[id])
        .whereType<NodeDataModel>();
    final bounds = [for (final node in nodes) _nodeWorldBounds(node)];
    if (bounds.isEmpty) return null;
    return bounds.reduce((a, b) => a.expandToInclude(b));
  }

  void resizeFrame(String frameId, Offset worldDelta) {
    final frame = controller.frames[frameId];
    if (frame == null) return;
    final memberBounds = _frameMemberBounds(frame);
    final minimumWidth = math
        .max(
          200.0,
          (memberBounds?.right ?? frame.bounds.left) - frame.bounds.left + 40,
        )
        .toDouble();
    final minimumHeight = math
        .max(
          120.0,
          (memberBounds?.bottom ?? frame.bounds.top) - frame.bounds.top + 40,
        )
        .toDouble();
    if (controller.resizeFrame(
          frameId,
          worldDelta,
          minimumSize: Size(minimumWidth, minimumHeight),
        ) !=
        null) {
      _syncFrameProjection(controller);
    }
  }

  Rect? _frameMemberBounds(NodeFrame frame) {
    final members = frame.members
        .map((id) => controller.nodes[id])
        .whereType<NodeDataModel>()
        .map(_nodeWorldBounds);
    if (members.isEmpty) return null;
    return members.reduce((a, b) => a.expandToInclude(b));
  }

  Rect _nodeWorldBounds(NodeDataModel node) {
    final renderObject = node.key.currentContext?.findRenderObject();
    final size = renderObject is RenderBox && renderObject.hasSize
        ? renderObject.size
        : node.customSize ?? _fallbackGraphNodeSize;
    return node.offset & size;
  }

  void deleteSelectedFrame() {
    final frameId = selectedFrameId.value;
    if (frameId == null) return;
    if (controller.removeFrame(frameId)) {
      _syncFrameProjection(controller);
    }
    selectedFrameId.value = null;
  }
}

/// Persistence-only frame projection. Frame geometry and membership remain in
/// sai_nodes; this extension only converts them to and from ShowRunner JSON.
extension ShowRunnerFrameSerializer on ShowRunnerGraphEditor {
  JsonMap _serializeFrame(NodeFrame frame) {
    final schemaMembers = frame.members
        .map((id) => _schemaIdByEditorId[id])
        .whereType<String>()
        .toList();
    return {
      'id': frame.id,
      'title': frame.title,
      'label': frame.title,
      'color': _frameColors[frame.id] ?? '#64b5f6',
      'nodeIds': schemaMembers,
      'left': frame.bounds.left,
      'top': frame.bounds.top,
      'right': frame.bounds.right,
      'bottom': frame.bounds.bottom,
      'x': frame.bounds.left,
      'y': frame.bounds.top,
      'width': frame.bounds.width,
      'height': frame.bounds.height,
    };
  }

  List<NodeFrame> _framesFromExtra(JsonMap extra) {
    final rawFrames = extra['editorFrames'];
    _frameColors.clear();
    if (rawFrames is! List) return const [];
    final restored = <NodeFrame>[];
    for (var index = 0; index < rawFrames.length; index++) {
      final raw = rawFrames[index];
      if (raw is! Map) continue;
      final value = Map<String, dynamic>.from(raw);
      var frame = NodeFrame.fromJson(value);
      if (frame.id.isEmpty) {
        frame = frame.copyWith(id: 'frame-$index');
      }
      _frameColors[frame.id] = value['color']?.toString() ?? '#64b5f6';
      restored.add(frame);
    }
    return restored;
  }
}
