part of '../showrunner_graph_editor.dart';

Map<String, dynamic>? _encodeShowRunnerClipboardPayload(
  ShowRunnerGraphEditor editor,
  Iterable<NodeDataModel> nodes,
) => editor._encodeClipboardPayload(nodes);

/// ShowRunner metadata layered over the generic sai_nodes clipboard.
extension ShowRunnerGraphEditorClipboard on ShowRunnerGraphEditor {
  Future<String> copySelection({BuildContext? context}) async {
    final payload = await controller.clipboard.copySelection(context: context);
    if (payload.isNotEmpty) _clipboardFallbackPayload = payload;
    return payload;
  }

  Future<void> pasteSelection({Offset? position, BuildContext? context}) async {
    final clipboardData = await Clipboard.getData('text/plain');
    final clipboardContent = clipboardData?.text?.isNotEmpty == true
        ? clipboardData!.text
        : _clipboardFallbackPayload;
    if (context != null && !context.mounted) return;
    await controller.clipboard.pasteSelection(
      position: position,
      context: context,
      clipboardContent: clipboardContent,
    );
  }

  Future<void> cutSelection({BuildContext? context}) async {
    final payload = await controller.clipboard.cutSelection(context: context);
    if (payload.isNotEmpty) _clipboardFallbackPayload = payload;
  }

  /// Applies the desktop delete command, including ShowRunner-only frames
  /// and retained invalid-edge diagnostics.
  void deleteSelection() {
    final invalidFlowEdgeId = selectedInvalidFlowEdgeId.value;
    if (invalidFlowEdgeId != null) {
      discardInvalidFlowEdge(invalidFlowEdgeId);
      return;
    }
    final invalidDataWireId = selectedInvalidDataWireId.value;
    if (invalidDataWireId != null) {
      discardInvalidDataWire(invalidDataWireId);
      return;
    }
    if (selectedFrameId.value != null) {
      deleteSelectedFrame();
      controller.clearSelection();
      return;
    }
    controller.deleteSelection();
    nodeRevision.value++;
  }

  ShowRunnerClipboardSnapshot? _clipboardSnapshotForNode(String nodeId) {
    final node = controller.nodes[nodeId];
    if (node == null) return null;
    return ShowRunnerClipboardSnapshot(
      nodeType: node.prototype.idName,
      data: Map<String, dynamic>.from(
        _nodeDataByEditorId[nodeId] ?? const <String, dynamic>{},
      ),
      title: _nodeTitles[nodeId],
      isVariable: _variableEditorIds.contains(nodeId),
      isTrigger: _triggerEditorIds.contains(nodeId),
    );
  }

  Map<String, dynamic>? _encodeClipboardPayload(Iterable<NodeDataModel> nodes) {
    final snapshots = nodes
        .map((node) => _clipboardSnapshotForNode(node.id))
        .whereType<ShowRunnerClipboardSnapshot>()
        .map((snapshot) => snapshot.toJson())
        .toList();
    return snapshots.isEmpty ? null : {'version': 1, 'snapshots': snapshots};
  }

  void _decodeClipboardPayload(
    Map<String, dynamic> payload,
    Iterable<NodeDataModel> pastedNodes,
  ) {
    final rawSnapshots = payload['snapshots'];
    if (rawSnapshots is! List) return;

    final snapshots = rawSnapshots
        .map(ShowRunnerClipboardSnapshot.fromJson)
        .whereType<ShowRunnerClipboardSnapshot>()
        .toList();
    final nodes = pastedNodes.toList();
    var restored = false;
    for (
      var index = 0;
      index < snapshots.length && index < nodes.length;
      index++
    ) {
      final nodeId = nodes[index].id;
      final snapshot = snapshots[index];
      _nodeDataByEditorId[nodeId] = _cloneJsonMap(snapshot.data);
      _schemaIdByEditorId[nodeId] = nodeId;
      if (snapshot.title != null) _nodeTitles[nodeId] = snapshot.title!;
      if (snapshot.isVariable) _variableEditorIds.add(nodeId);
      if (snapshot.isTrigger) {
        _triggerEditorIds.add(nodeId);
        _triggerNodeStateInitialized = true;
      }
      restored = true;
    }
    if (restored) nodeRevision.value++;
  }
}
