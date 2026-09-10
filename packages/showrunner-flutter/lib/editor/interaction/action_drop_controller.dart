part of '../showrunner_graph_editor.dart';

/// ShowRunner-specific pointer hit-testing and insertion workflows.
///
/// Coordinate conversion is intentionally shared by insertion and hit-tests.
/// Generic canvas gestures and viewport transforms remain in sai_nodes.
extension ShowRunnerActionDropController on ShowRunnerGraphEditor {
  String? addNodeTypeAtScreenPosition(
    String nodeType,
    Offset screenPosition, {
    String? title,
  }) {
    final worldPosition = _worldPositionForScreenPosition(screenPosition);
    if (worldPosition == null) {
      return addNodeType(nodeType, title: title);
    }
    return addNodeType(nodeType, title: title, offset: worldPosition);
  }

  String? addVariableNodeAtScreenPosition(
    String type,
    Offset screenPosition, {
    String? name,
    dynamic value,
  }) {
    final worldPosition = _worldPositionForScreenPosition(screenPosition);
    return addVariableNode(
      type,
      name: name,
      value: value,
      offset: worldPosition ?? const Offset(80, 80),
    );
  }

  String? addSubgraphCallAtScreenPosition(
    String subgraphId,
    Offset screenPosition, {
    String? title,
  }) {
    final worldPosition = _worldPositionForScreenPosition(screenPosition);
    return addSubgraphCall(
      subgraphId,
      title: title,
      offset: worldPosition ?? const Offset(80, 80),
    );
  }

  Offset? _worldPositionForScreenPosition(Offset screenPosition) {
    final renderObject = controller.editorKey.currentContext
        ?.findRenderObject();
    if (renderObject is! RenderBox || renderObject.size.isEmpty) return null;
    final local = renderObject.globalToLocal(screenPosition);
    return controller.screenToWorld(local, renderObject.size);
  }

  /// Finds the topmost graph node under a global pointer position.
  String? nodeIdAtScreenPosition(Offset screenPosition) {
    final world = _worldPositionForScreenPosition(screenPosition);
    return world == null ? null : controller.hitTestNode(world)?.nodeId;
  }

  /// Updates the visual drop target used when an action is dragged from the
  /// palette over the graph.
  void updateActionDropTarget(Offset screenPosition) {
    final linkId = flowLinkIdAtScreenPosition(screenPosition);
    dropTargetLinkId.value = linkId;
    dropTargetNodeId.value = linkId == null
        ? nodeIdAtScreenPosition(screenPosition)
        : null;
  }

  void clearActionDropTarget() {
    dropTargetNodeId.value = null;
    dropTargetLinkId.value = null;
  }

  /// Finds a control-flow link under a global pointer position.
  String? flowLinkIdAtScreenPosition(Offset screenPosition) {
    final world = _worldPositionForScreenPosition(screenPosition);
    if (world == null) return null;

    final tolerance = 12 / controller.viewportZoom;
    return controller
        .hitTestLink(
          world,
          tolerance: tolerance,
          where: (link) {
            final source = controller.nodes[link.endpoints.sourceNodeId];
            final sourcePort = source?.ports[link.endpoints.sourcePortId];
            return sourcePort?.prototype.type == PortType.control;
          },
        )
        ?.linkId;
  }

  String? insertActionAfterNode(
    String nodeType,
    String anchorEditorId, {
    String? fromPort,
    Offset? offset,
  }) {
    final anchor = controller.nodes[anchorEditorId];
    if (anchor == null) return null;
    final conversion = _isCoreConversionNodeType(nodeType);
    final sourcePort = conversion
        ? null
        : fromPort ?? _firstFlowOutputPort(anchor);
    final downstream = sourcePort == null
        ? null
        : controller.linksAsList
              .where(
                (link) =>
                    link.endpoints.sourceNodeId == anchorEditorId &&
                    link.endpoints.sourcePortId == sourcePort,
              )
              .firstOrNull;
    final insertedId = addNodeType(
      nodeType,
      offset: offset ?? anchor.offset + const Offset(280, 0),
    );
    if (insertedId == null) return null;
    if (conversion) return insertedId;

    final inputPort = _firstControlInputPort(controller.nodes[insertedId]);
    final outputPort = _preferredFlowOutputPort(controller.nodes[insertedId]);
    if (sourcePort == null || inputPort == null || outputPort == null) {
      return insertedId;
    }
    if (downstream != null) controller.removeLinkById(downstream.id);
    controller.addLink(anchorEditorId, sourcePort, insertedId, inputPort);
    if (downstream != null) {
      controller.addLink(
        insertedId,
        outputPort,
        downstream.endpoints.targetNodeId,
        downstream.endpoints.targetPortId,
      );
    }
    return insertedId;
  }

  String? insertControlFlowAfterNode(
    String nodeType,
    String anchorEditorId, {
    String? fromPort,
    Offset? offset,
  }) {
    if (!const {'break', 'continue', 'return'}.contains(nodeType)) {
      return null;
    }
    final anchor = controller.nodes[anchorEditorId];
    if (anchor == null) return null;
    final sourcePort = fromPort ?? _firstFlowOutputPort(anchor);
    if (sourcePort == null) return null;
    final source = anchor.ports[sourcePort];
    if (source?.prototype.type != PortType.control ||
        source?.prototype.direction != PortDirection.output) {
      return null;
    }
    final downstream = controller.linksAsList
        .where(
          (link) =>
              link.endpoints.sourceNodeId == anchorEditorId &&
              link.endpoints.sourcePortId == sourcePort,
        )
        .firstOrNull;
    final insertedId = addNodeType(
      nodeType,
      offset: offset ?? anchor.offset + const Offset(280, 0),
    );
    if (insertedId == null) return null;
    final inputPort = _firstControlInputPort(controller.nodes[insertedId]);
    if (inputPort == null) return insertedId;
    if (downstream != null) controller.removeLinkById(downstream.id);
    controller.addLink(anchorEditorId, sourcePort, insertedId, inputPort);
    return insertedId;
  }

  String? insertActionOnFlowEdge(
    String nodeType,
    String linkId, {
    Offset? offset,
  }) {
    final link = controller.linksAsList
        .where((candidate) => candidate.id == linkId)
        .firstOrNull;
    if (link == null) return null;
    final source = controller.nodes[link.endpoints.sourceNodeId];
    if (source == null ||
        source.ports[link.endpoints.sourcePortId]?.prototype.type !=
            PortType.control) {
      return null;
    }
    if (_isCoreConversionNodeType(nodeType)) {
      return addNodeType(
        nodeType,
        offset: offset ?? source.offset + const Offset(280, 0),
      );
    }

    final insertedOffset = offset ?? source.offset + const Offset(280, 0);
    final detached = _createDetachedNodeType(nodeType, offset: insertedOffset);
    final inputPort = _firstControlInputPort(detached);
    final outputPort = _preferredFlowOutputPort(detached);
    if (inputPort == null || outputPort == null) {
      controller.addNodeFromExisting(detached);
      _markDocumentDirty();
      return detached.id;
    }
    final schemaLinkId =
        _schemaIdByLinkSignature[ShowRunnerGraphEditor._linkSignature(
          link.endpoints.sourceNodeId,
          link.endpoints.sourcePortId,
          link.endpoints.targetNodeId,
          link.endpoints.targetPortId,
        )];
    final inserted = controller.spliceNodeIntoLink(
      link.id,
      detached,
      inputPortId: inputPort,
      outputPortId: outputPort,
    );
    if (inserted == null) {
      controller.addNodeFromExisting(detached);
      _markDocumentDirty();
      return detached.id;
    }
    final incoming = controller.linksAsList.firstWhere(
      (candidate) =>
          candidate.endpoints.targetNodeId == inserted.id &&
          candidate.endpoints.sourceNodeId == link.endpoints.sourceNodeId,
    );
    if (schemaLinkId != null) {
      _schemaIdByLinkSignature[ShowRunnerGraphEditor._linkSignature(
            incoming.endpoints.sourceNodeId,
            incoming.endpoints.sourcePortId,
            incoming.endpoints.targetNodeId,
            incoming.endpoints.targetPortId,
          )] =
          schemaLinkId;
    }
    return inserted.id;
  }
}
