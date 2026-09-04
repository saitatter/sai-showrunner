import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:sai_nodes/sai_nodes.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../components/data_inputs/data_input.dart';
import '../runtime/automation_recovery.dart';
import '../plugins/registry/plugin_bootstrap.dart';
import '../plugins/registry/plugin_registry.dart';
import '../schema/automation.dart';

enum GraphNodeExecutionStatus { running, success, error }

final class GraphNodeExecutionVisual {
  const GraphNodeExecutionVisual({
    required this.status,
    required this.startedAt,
    this.duration,
    this.error,
  });

  final GraphNodeExecutionStatus status;
  final DateTime startedAt;
  final Duration? duration;
  final String? error;
}

final class _ClipboardNodeSnapshot {
  const _ClipboardNodeSnapshot({
    required this.nodeType,
    required this.data,
    this.title,
    this.isVariable = false,
    this.isTrigger = false,
  });

  final String nodeType;
  final JsonMap data;
  final String? title;
  final bool isVariable;
  final bool isTrigger;
}

JsonMap _cloneJsonMap(Map<String, dynamic> source) => {
  for (final entry in source.entries) entry.key: _cloneJsonValue(entry.value),
};

dynamic _cloneJsonValue(dynamic value) {
  if (value is Map) {
    return {
      for (final entry in value.entries)
        entry.key.toString(): _cloneJsonValue(entry.value),
    };
  }
  if (value is List) return value.map(_cloneJsonValue).toList();
  return value;
}

JsonMap _jsonEntry(String key, dynamic value) =>
    value == null ? const <String, dynamic>{} : <String, dynamic>{key: value};

Size? _editorSizeFromJson(dynamic value, NodeEditorConfig config) {
  if (value is! List || value.length < 2) return null;
  final width = value[0];
  final height = value[1];
  if (width is! num || height is! num) return null;
  if (!width.isFinite || !height.isFinite || width <= 0 || height <= 0) {
    return null;
  }
  return Size(
    width.toDouble().clamp(config.minNodeWidth, config.maxNodeWidth).toDouble(),
    height
        .toDouble()
        .clamp(config.minNodeHeight, config.maxNodeHeight)
        .toDouble(),
  );
}

/// Adapter between ShowRunner's graph schema and the `sai_nodes` editor model.
///
/// `sai_nodes` owns generic canvas behavior. This adapter owns the translation
/// to persisted ShowRunner IDs, plugin semantics, and domain-only graph state.
class ShowRunnerGraphEditor {
  ShowRunnerGraphEditor({DartPluginRegistry? registry})
    : _registry = registry ?? createDefaultPluginRegistry() {
    controller = _createController();
    _controllers[_mainGraphKey] = controller;
  }

  static const _mainGraphKey = '';
  static const subgraphParameterTypes = {
    'string',
    'number',
    'boolean',
    'array',
    'object',
    'color',
    'any',
  };

  late NodeEditorController controller;
  final DartPluginRegistry _registry;
  final Map<String, NodeEditorController> _controllers = {};
  // Editor IDs are transient; this map preserves the persisted node payload.
  final Map<String, JsonMap> _nodeDataByEditorId = {};
  final Map<String, String> _schemaIdByEditorId = {};
  final Map<String, String> _schemaIdByLinkSignature = {};
  final Map<String, List<GraphEdge>> _invalidFlowEdgesByGraph = {};
  final Map<String, List<DataWire>> _invalidDataWiresByGraph = {};
  final Map<NodeEditorController, StreamSubscription> _fieldEvents = {};
  final Map<String, String> _entryNodeIdByGraph = {};
  final Set<String> _variableEditorIds = {};
  final ValueNotifier<List<String>> activeGraphPath = ValueNotifier(const []);
  final ValueNotifier<Set<String>> activeNodeIds = ValueNotifier(const {});
  final ValueNotifier<List<GraphFrame>> frames = ValueNotifier(const []);
  final ValueNotifier<String?> selectedFrameId = ValueNotifier(null);
  final ValueNotifier<List<SubgraphDefinition>> subgraphs = ValueNotifier(
    const [],
  );
  final ValueNotifier<Map<String, GraphNodeExecutionVisual>> executionStates =
      ValueNotifier(const {});
  final ValueNotifier<String?> graphFeedback = ValueNotifier(null);
  final ValueNotifier<String> searchQuery = ValueNotifier('');
  final ValueNotifier<int> searchMatchIndex = ValueNotifier(0);
  final ValueNotifier<List<String>> recentNodeTypes = ValueNotifier(const []);
  final ValueNotifier<int> nodeRevision = ValueNotifier(0);
  final Map<String, String> _nodeTitles = {};
  final Map<String, String> _prototypeTitles = {};
  final Map<String, List<_ClipboardNodeSnapshot>> _clipboardMetadata = {};
  // Trigger metadata is separate from executable trigger nodes so persisted
  // trigger subscriptions can be restored without changing node prototypes.
  final Set<String> _triggerEditorIds = {};
  String? _inMemoryClipboardPayload;
  List<String>? _pendingPasteNodeIds;
  List<_ClipboardNodeSnapshot>? _pendingPasteSnapshots;
  bool _triggerNodeStateInitialized = false;

  String? get activeSubgraphId => activeGraphPath.value.lastOrNull;

  List<GraphEdge> get invalidFlowEdges => List.unmodifiable(
    _invalidFlowEdgesByGraph[activeSubgraphId ?? _mainGraphKey] ??
        const <GraphEdge>[],
  );

  List<DataWire> get invalidDataWires => List.unmodifiable(
    _invalidDataWiresByGraph[activeSubgraphId ?? _mainGraphKey] ??
        const <DataWire>[],
  );

  String get activeGraphName {
    final subgraphId = activeSubgraphId;
    if (subgraphId == null) return 'Main graph';
    return subgraphs.value
            .where((subgraph) => subgraph.id == subgraphId)
            .map((subgraph) => subgraph.name)
            .firstOrNull ??
        subgraphId;
  }

  NodeEditorController _createController() {
    final created = NodeEditorController(
      config: const NodeEditorConfig(
        autoBuildGraph: false,
        autoRunGraph: false,
        enableNodeResize: true,
      ),
      onCallback: (type, message) {
        debugPrint('sai_nodes $type: $message');
        if (type == CallbackType.error) graphFeedback.value = message;
      },
    );
    _registerPrototypes(created);
    _fieldEvents[created] = created.eventBus.events.listen((event) {
      if (event is DragSelectionEvent &&
          identical(created, _controllers[_mainGraphKey])) {
        _placeDraggedNodesInFrame(event.nodeIds);
      }
      if (event is RemoveNodeEvent &&
          identical(created, _controllers[_mainGraphKey])) {
        _removeEditorNodeFromFrames(event.node.id);
        _triggerEditorIds.remove(event.node.id);
      }
      if (event is AddNodeEvent) {
        _trackAddedNode(created, event.node);
      }
      if (event is PasteSelectionEvent) {
        _restorePastedMetadata();
      }
      if (event is CopySelectionEvent) {
        _inMemoryClipboardPayload = event.clipboardContent;
        _rememberClipboardMetadata(event.clipboardContent);
      }
      if (event is! NodeFieldEvent ||
          event.eventType == FieldEventType.change) {
        return;
      }
      final data = _nodeDataByEditorId[event.nodeId];
      if (data == null) return;
      final node = created.nodes[event.nodeId];
      final field = node?.fields.values
          .where((field) => field.data == event.value)
          .firstOrNull;
      if (field != null) data[field.prototype.idName] = event.value;
    });
    return created;
  }

  Future<String> copySelection({BuildContext? context}) async {
    final snapshots = controller.selectedNodeIds
        .map(_clipboardSnapshotForNode)
        .whereType<_ClipboardNodeSnapshot>()
        .toList();
    final payload = await controller.clipboard.copySelection(context: context);
    if (payload.isNotEmpty && snapshots.isNotEmpty) {
      _inMemoryClipboardPayload = payload;
      _rememberClipboardMetadata(payload, snapshots: snapshots);
    }
    return payload;
  }

  Future<void> pasteSelection({Offset? position, BuildContext? context}) async {
    final clipboardData = await Clipboard.getData('text/plain');
    final clipboardContent = clipboardData?.text ?? _inMemoryClipboardPayload;
    final existingNodeIds = controller.nodes.keys.toSet();
    _pendingPasteNodeIds = [];
    _pendingPasteSnapshots = clipboardContent == null
        ? null
        : _clipboardMetadata[clipboardContent];
    await controller.clipboard.pasteSelection(
      position: position,
      clipboardContent: clipboardContent,
    );
    if (_pendingPasteSnapshots != null &&
        (_pendingPasteNodeIds?.isEmpty ?? false)) {
      _pendingPasteNodeIds = controller.nodes.keys
          .where((id) => !existingNodeIds.contains(id))
          .toList();
    }
    _restorePastedMetadata();
  }

  Future<void> cutSelection({BuildContext? context}) async {
    final snapshots = controller.selectedNodeIds
        .map(_clipboardSnapshotForNode)
        .whereType<_ClipboardNodeSnapshot>()
        .toList();
    final payload = await controller.clipboard.cutSelection(context: context);
    if (payload.isNotEmpty && snapshots.isNotEmpty) {
      _inMemoryClipboardPayload = payload;
      _rememberClipboardMetadata(payload, snapshots: snapshots);
    }
  }

  void _rememberClipboardMetadata(
    String payload, {
    List<_ClipboardNodeSnapshot>? snapshots,
  }) {
    if (payload.isEmpty) return;
    final value =
        snapshots ??
        controller.selectedNodeIds
            .map(_clipboardSnapshotForNode)
            .whereType<_ClipboardNodeSnapshot>()
            .toList();
    if (value.isEmpty) return;
    _clipboardMetadata[payload] = value;
    while (_clipboardMetadata.length > 8) {
      _clipboardMetadata.remove(_clipboardMetadata.keys.first);
    }
  }

  _ClipboardNodeSnapshot? _clipboardSnapshotForNode(String nodeId) {
    final node = controller.nodes[nodeId];
    if (node == null) return null;
    return _ClipboardNodeSnapshot(
      nodeType: node.prototype.idName,
      data: Map<String, dynamic>.from(
        _nodeDataByEditorId[nodeId] ?? const <String, dynamic>{},
      ),
      title: _nodeTitles[nodeId],
      isVariable: _variableEditorIds.contains(nodeId),
      isTrigger: _triggerEditorIds.contains(nodeId),
    );
  }

  void _trackAddedNode(NodeEditorController owner, NodeDataModel node) {
    _pendingPasteNodeIds?.add(node.id);
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

  void _restorePastedMetadata() {
    final nodeIds = _pendingPasteNodeIds;
    final snapshots = _pendingPasteSnapshots;
    _pendingPasteNodeIds = null;
    _pendingPasteSnapshots = null;
    if (nodeIds == null || snapshots == null) return;
    for (
      var index = 0;
      index < nodeIds.length && index < snapshots.length;
      index++
    ) {
      final nodeId = nodeIds[index];
      final snapshot = snapshots[index];
      _nodeDataByEditorId[nodeId] = Map<String, dynamic>.from(snapshot.data);
      _schemaIdByEditorId[nodeId] = nodeId;
      if (snapshot.title != null) _nodeTitles[nodeId] = snapshot.title!;
      if (snapshot.isVariable) _variableEditorIds.add(nodeId);
      if (snapshot.isTrigger) {
        _triggerEditorIds.add(nodeId);
        _triggerNodeStateInitialized = true;
      }
    }
    nodeRevision.value++;
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

  String nodeTitle(String editorNodeId) =>
      (_variableEditorIds.contains(editorNodeId) &&
          _nodeDataByEditorId[editorNodeId]?['name'] is String &&
          (_nodeDataByEditorId[editorNodeId]!['name'] as String)
              .trim()
              .isNotEmpty)
      ? (_nodeDataByEditorId[editorNodeId]!['name'] as String).trim()
      : _nodeTitles[editorNodeId] ??
            controller.nodes[editorNodeId]?.customTitle ??
            _prototypeTitles[controller
                .nodes[editorNodeId]
                ?.prototype
                .idName] ??
            controller.nodes[editorNodeId]?.prototype.idName ??
            '';

  String? customNodeTitle(String editorNodeId) =>
      _nodeTitles[editorNodeId] ?? controller.nodes[editorNodeId]?.customTitle;

  JsonMap nodeData(String editorNodeId) => Map.unmodifiable(
    _nodeDataByEditorId[editorNodeId] ?? const <String, dynamic>{},
  );

  JsonMap variableNodeData(String editorNodeId) => isVariableNode(editorNodeId)
      ? nodeData(editorNodeId)
      : const <String, dynamic>{};

  JsonMap nodeConfig(String editorNodeId) {
    final config = nodeData(editorNodeId)['config'];
    return config is Map
        ? Map<String, dynamic>.from(config)
        : <String, dynamic>{};
  }

  JsonMap nodeResultMapping(String editorNodeId) {
    final mapping = nodeData(editorNodeId)['resultMapping'];
    return mapping is Map
        ? Map<String, dynamic>.from(mapping)
        : <String, dynamic>{};
  }

  void updateNodeConfig(String editorNodeId, JsonMap config) {
    if (!controller.nodes.containsKey(editorNodeId)) return;
    _nodeDataByEditorId.putIfAbsent(editorNodeId, () => {});
    _nodeDataByEditorId[editorNodeId]!['config'] = Map<String, dynamic>.from(
      config,
    );
    nodeRevision.value++;
  }

  void updateNodeResultMapping(String editorNodeId, JsonMap mapping) {
    if (!controller.nodes.containsKey(editorNodeId)) return;
    _nodeDataByEditorId.putIfAbsent(editorNodeId, () => {});
    _nodeDataByEditorId[editorNodeId]!['resultMapping'] =
        Map<String, dynamic>.from(mapping);
    nodeRevision.value++;
  }

  void updateTriggerNodeData(
    String editorNodeId, {
    required JsonMap config,
    required bool stop,
  }) {
    if (!isTriggerNode(editorNodeId)) return;
    _nodeDataByEditorId.putIfAbsent(editorNodeId, () => {});
    _nodeDataByEditorId[editorNodeId]!
      ..['config'] = Map<String, dynamic>.from(config)
      ..['stop'] = stop;
    nodeRevision.value++;
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
        _linkSignature(
          link.endpoints.sourceNodeId,
          link.endpoints.sourcePortId,
          link.endpoints.targetNodeId,
          link.endpoints.targetPortId,
        ): _schemaIdByLinkSignature[_linkSignature(
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
      final oldSignature = _linkSignature(
        link.endpoints.sourceNodeId,
        link.endpoints.sourcePortId,
        link.endpoints.targetNodeId,
        link.endpoints.targetPortId,
      );
      final newSignature = _linkSignature(
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
    if (controller.selectedNodeIds.isEmpty) return null;
    final currentId = controller.selectedNodeIds.last;
    final current = controller.nodes[currentId];
    if (current == null) return null;
    final candidates = controller.nodes.values.where(
      (node) => node.id != current.id,
    );
    NodeDataModel? best;
    var bestScore = double.infinity;
    for (final candidate in candidates) {
      final delta = candidate.offset - current.offset;
      final inDirection = switch (direction) {
        LogicalKeyboardKey.arrowRight => delta.dx > 20,
        LogicalKeyboardKey.arrowLeft => delta.dx < -20,
        LogicalKeyboardKey.arrowDown => delta.dy > 20,
        LogicalKeyboardKey.arrowUp => delta.dy < -20,
        _ => false,
      };
      if (!inDirection) continue;
      final primaryDistance = switch (direction) {
        LogicalKeyboardKey.arrowRight => delta.dx,
        LogicalKeyboardKey.arrowLeft => -delta.dx,
        LogicalKeyboardKey.arrowDown => delta.dy,
        LogicalKeyboardKey.arrowUp => -delta.dy,
        _ => double.infinity,
      };
      final crossDistance =
          direction == LogicalKeyboardKey.arrowLeft ||
              direction == LogicalKeyboardKey.arrowRight
          ? delta.dy.abs()
          : delta.dx.abs();
      final score = primaryDistance + crossDistance * 2;
      if (score < bestScore) {
        bestScore = score;
        best = candidate;
      }
    }
    if (best == null) return null;
    controller.selectNodesById({best.id}, holdSelection: extendSelection);
    return best.id;
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
    _removeEditorNodeFromFrames(editorNodeId);
    controller.removeNodeById(editorNodeId);
    _variableEditorIds.remove(editorNodeId);
    _schemaIdByEditorId.remove(editorNodeId);
    _nodeDataByEditorId.remove(editorNodeId);
    _nodeTitles.remove(editorNodeId);
    nodeRevision.value++;
  }

  void setSearchQuery(String query) {
    searchQuery.value = query.trim();
    searchMatchIndex.value = 0;
  }

  Set<String> searchNodeIds([String? query]) {
    final normalized = (query ?? searchQuery.value).toLowerCase();
    if (normalized.isEmpty) return controller.nodes.keys.toSet();
    return controller.nodes.values
        .where((node) {
          final haystack = [
            nodeTitle(node.id),
            node.prototype.idName,
            _nodeDataByEditorId[node.id]?.toString() ?? '',
          ].join(' ').toLowerCase();
          return haystack.contains(normalized);
        })
        .map((node) => node.id)
        .toSet();
  }

  void focusSearchResults() {
    final matches = searchNodeIds();
    if (matches.isNotEmpty) controller.focusNodesById(matches);
  }

  int searchResultCount() => searchNodeIds().length;

  String? focusSearchResult({bool forward = true}) {
    final matches = searchNodeIds().toList();
    if (matches.isEmpty) {
      searchMatchIndex.value = 0;
      return null;
    }
    final nextIndex = forward
        ? (searchMatchIndex.value + 1) % matches.length
        : (searchMatchIndex.value - 1 + matches.length) % matches.length;
    searchMatchIndex.value = nextIndex;
    final nodeId = matches[nextIndex];
    controller.focusNodesById({nodeId});
    return nodeId;
  }

  void markSchemaNodeRunning(String schemaId) {
    final editorId = editorNodeIdForSchema(schemaId);
    setActiveSchemaNodeIds([schemaId]);
    if (editorId == null) return;
    executionStates.value = {
      ...executionStates.value,
      editorId: GraphNodeExecutionVisual(
        status: GraphNodeExecutionStatus.running,
        startedAt: DateTime.now(),
      ),
    };
  }

  void markSchemaNodeCompleted(String schemaId) {
    final editorId = editorNodeIdForSchema(schemaId);
    if (editorId == null) return;
    final previous = executionStates.value[editorId];
    executionStates.value = {
      ...executionStates.value,
      editorId: GraphNodeExecutionVisual(
        status: GraphNodeExecutionStatus.success,
        startedAt: previous?.startedAt ?? DateTime.now(),
        duration: previous == null
            ? null
            : DateTime.now().difference(previous.startedAt),
      ),
    };
    setActiveSchemaNodeIds(const []);
  }

  void markActiveSchemaNodeFailed(Object error) {
    final editorId = activeNodeIds.value.firstOrNull;
    if (editorId == null) return;
    final previous = executionStates.value[editorId];
    executionStates.value = {
      ...executionStates.value,
      editorId: GraphNodeExecutionVisual(
        status: GraphNodeExecutionStatus.error,
        startedAt: previous?.startedAt ?? DateTime.now(),
        duration: previous == null
            ? null
            : DateTime.now().difference(previous.startedAt),
        error: error.toString(),
      ),
    };
    activeNodeIds.value = const {};
  }

  void clearExecutionStates() {
    executionStates.value = const {};
    activeNodeIds.value = const {};
  }

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
            selected.map((node) => node.offset.dx).reduce(math.min) - 24,
            selected.map((node) => node.offset.dy).reduce(math.min) - 44,
            selected.map((node) => node.offset.dx + 180).reduce(math.max) + 24,
            selected.map((node) => node.offset.dy + 90).reduce(math.max) + 24,
          );
    final framePrefix = 'frame-${DateTime.now().microsecondsSinceEpoch}';
    var frameId = framePrefix;
    var frameSuffix = 1;
    while (frames.value.any((frame) => frame.id == frameId)) {
      frameId = '$framePrefix-$frameSuffix';
      frameSuffix++;
    }
    frames.value = [
      ...frames.value,
      GraphFrame(id: frameId, title: title, bounds: bounds, nodeIds: const []),
    ];
    if (selectedSchemaIds.isNotEmpty) {
      _placeSchemaNodesInFrame(frameId, selectedSchemaIds);
    }
  }

  void selectFrame(String? frameId) {
    selectedFrameId.value =
        frameId != null && frames.value.any((frame) => frame.id == frameId)
        ? frameId
        : null;
  }

  void renameFrame(String frameId, String title) {
    final index = frames.value.indexWhere((frame) => frame.id == frameId);
    if (index < 0) return;
    final normalized = title.trim().isEmpty ? 'Frame' : title.trim();
    final updated = [...frames.value];
    updated[index] = updated[index].copyWith(title: normalized);
    frames.value = updated;
  }

  void updateFrameColor(String frameId, String color) {
    final index = frames.value.indexWhere((frame) => frame.id == frameId);
    if (index < 0) return;
    final normalized = color.trim().isEmpty ? '#64b5f6' : color.trim();
    final updated = [...frames.value];
    updated[index] = updated[index].copyWith(color: normalized);
    frames.value = updated;
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
    final index = frames.value.indexWhere((frame) => frame.id == frameId);
    if (index < 0) return;
    final existingNodeIds = frames.value[index].nodeIds.toSet();
    existingNodeIds.addAll(nodeIds);
    final updated = [...frames.value];
    updated[index] = updated[index].copyWith(nodeIds: existingNodeIds.toList());
    frames.value = updated;
  }

  bool placeDraggedNodesInFrame(String? frameId, Iterable<String> nodeIds) =>
      _placeSchemaNodesInFrame(frameId, nodeIds);

  String? frameForNodes(Iterable<String> nodeIds) {
    final memberBounds = _schemaNodeBounds(nodeIds);
    if (memberBounds == null) return null;
    final center = memberBounds.center;
    return frames.value
        .where((frame) => frame.bounds.contains(center))
        .map((frame) => frame.id)
        .firstOrNull;
  }

  List<String> frameIdsForNodes(Iterable<String> nodeIds) {
    final ids = nodeIds.toSet();
    if (ids.isEmpty) return const [];
    return frames.value
        .where((frame) => frame.nodeIds.any(ids.contains))
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
    final index = frames.value.indexWhere((frame) => frame.id == frameId);
    if (index < 0) return;
    final updated = [...frames.value];
    updated[index] = updated[index].copyWith(
      nodeIds: frames.value[index].nodeIds
          .where((id) => !selectedSchemaIds.contains(id))
          .toList(),
    );
    frames.value = updated;
  }

  void clearSelectedFrameNodes() {
    final frameId = selectedFrameId.value;
    if (frameId == null) return;
    final index = frames.value.indexWhere((frame) => frame.id == frameId);
    if (index < 0) return;
    final updated = [...frames.value];
    updated[index] = updated[index].copyWith(nodeIds: const []);
    frames.value = updated;
  }

  void moveFrame(String frameId, Offset worldDelta) {
    final index = frames.value.indexWhere((frame) => frame.id == frameId);
    if (index < 0) return;
    final frame = frames.value[index];
    final updated = [...frames.value];
    updated[index] = frame.copyWith(bounds: frame.bounds.shift(worldDelta));
    frames.value = updated;

    final memberEditorIds = frame.nodeIds
        .map(editorNodeIdForSchema)
        .whereType<String>()
        .where(controller.nodes.containsKey)
        .toSet();
    if (memberEditorIds.isEmpty) return;
    final previousSelection = controller.selectedNodeIds.toSet();
    controller.selectNodesById(memberEditorIds);
    controller.dragSelection(worldDelta, isWorldDelta: true);
    controller.clearSelection();
    if (previousSelection.isNotEmpty) {
      controller.selectNodesById(previousSelection);
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
    final ids = nodeIds.toSet();
    if (ids.isEmpty) return false;
    final targetExists =
        frameId != null && frames.value.any((frame) => frame.id == frameId);
    var changed = false;
    final updated = [
      for (final frame in frames.value)
        frame.copyWith(
          nodeIds: frame.nodeIds.where((id) {
            final keep = !ids.contains(id) || frame.id == frameId;
            if (!keep) changed = true;
            return keep;
          }).toList(),
        ),
    ];
    if (targetExists) {
      final index = updated.indexWhere((frame) => frame.id == frameId);
      final target = updated[index];
      final members = target.nodeIds.toSet()..addAll(ids);
      if (members.length != target.nodeIds.length) changed = true;
      updated[index] = target.copyWith(nodeIds: members.toList());
    }
    if (changed) frames.value = updated;
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
    final bounds = [
      for (final node in nodes)
        Rect.fromLTWH(node.offset.dx, node.offset.dy, 180, 90),
    ];
    if (bounds.isEmpty) return null;
    return bounds.reduce((a, b) => a.expandToInclude(b));
  }

  void resizeFrame(String frameId, Offset worldDelta) {
    final index = frames.value.indexWhere((frame) => frame.id == frameId);
    if (index < 0) return;
    final frame = frames.value[index];
    final memberBounds = _frameMemberBounds(frame);
    final minimumWidth = math.max(
      200,
      (memberBounds?.right ?? frame.bounds.left) - frame.bounds.left + 40,
    );
    final minimumHeight = math.max(
      120,
      (memberBounds?.bottom ?? frame.bounds.top) - frame.bounds.top + 40,
    );
    final updated = [...frames.value];
    updated[index] = frame.copyWith(
      bounds: Rect.fromLTWH(
        frame.bounds.left,
        frame.bounds.top,
        math.max(minimumWidth, frame.bounds.width + worldDelta.dx).toDouble(),
        math.max(minimumHeight, frame.bounds.height + worldDelta.dy).toDouble(),
      ),
    );
    frames.value = updated;
  }

  Rect? _frameMemberBounds(GraphFrame frame) {
    final members = frame.nodeIds
        .map(editorNodeIdForSchema)
        .whereType<String>()
        .map((id) => controller.nodes[id])
        .whereType<NodeDataModel>()
        .map((node) => Rect.fromLTWH(node.offset.dx, node.offset.dy, 180, 90));
    if (members.isEmpty) return null;
    return members.reduce((a, b) => a.expandToInclude(b));
  }

  void deleteSelectedFrame() {
    final frameId = selectedFrameId.value;
    if (frameId == null) return;
    frames.value = frames.value.where((frame) => frame.id != frameId).toList();
    selectedFrameId.value = null;
  }

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
      item['type'] = subgraphParameterTypes.contains(type) ? type : 'any';
      if (!output) {
        item['default'] = _coerceSubgraphDefault(item['type'], item['default']);
      }
    } else if (field == 'default' && !output) {
      item['default'] = _coerceSubgraphDefault(
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
    final prototypeId = _subgraphCallPrototypeId(subgraphId);
    for (final target in _controllers.values) {
      _ensureSubgraphCallPrototype(subgraph, target: target);
      for (final node in target.nodes.values.where(
        (node) => _nodeDataByEditorId[node.id]?['subgraphId'] == subgraphId,
      )) {
        final desired = {
          'exec',
          'completed',
          ...subgraph.parameters.map((item) => item['name'].toString()),
          ...subgraph.outputs.map((item) => item['name'].toString()),
        };
        for (final portId in node.ports.keys.toList()) {
          if (node.ports[portId]!.prototype.idName == 'exec' ||
              node.ports[portId]!.prototype.idName == 'completed' ||
              desired.contains(portId)) {
            continue;
          }
          for (final link in node.ports[portId]!.links.toList()) {
            target.removeLinkById(link.id);
          }
          node.ports.remove(portId);
        }
        final prototype = target.nodePrototypes[prototypeId];
        if (prototype == null) continue;
        for (final port in prototype.ports) {
          node.ports.putIfAbsent(
            port.idName,
            () => PortDataModel(prototype: port, state: PortState()),
          );
        }
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
    }
    controller = target;
    activeGraphPath.value = [...activeGraphPath.value, subgraphId];
    return true;
  }

  bool goBackToParentGraph() {
    if (activeGraphPath.value.isEmpty) return false;
    _syncActiveGraph();
    final path = [...activeGraphPath.value]..removeLast();
    controller = _controllers[path.lastOrNull ?? _mainGraphKey]!;
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
      controller = _controllers[_mainGraphKey]!;
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
      _subgraphCallPrototypeId(subgraphId),
      offset: offset,
    );
    _nodeDataByEditorId[node.id] = {
      'subgraphId': subgraphId,
      'inputs': <String, dynamic>{},
      if (nodeTitle.isNotEmpty) 'title': nodeTitle,
    };
    if (nodeTitle.isNotEmpty) _nodeTitles[node.id] = nodeTitle;
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
  }

  void _registerPrototypes(NodeEditorController target) {
    target.registerNodePrototype(
      _prototype(
        idName: 'trigger.chatMessage',
        title: 'Chat message',
        color: const Color(0xff2563eb),
        input: false,
        output: true,
        hasPayloadOutput: true,
      ),
    );
    target.registerNodePrototype(
      _prototype(
        idName: 'queue.addItem',
        title: 'Add to queue',
        color: const Color(0xffd97706),
        input: true,
        output: true,
        hasPayloadInput: true,
        fields: [_textField('queueName', 'Queue', 'default')],
      ),
    );
    target.registerNodePrototype(
      _prototype(
        idName: 'overlay.pushChat',
        title: 'Push chat overlay',
        color: const Color(0xff059669),
        input: true,
        output: false,
        hasPayloadInput: true,
        fields: [_textField('message', 'Message', 'Chat message')],
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

  static String _subgraphCallPrototypeId(String subgraphId) =>
      'subgraphCall:$subgraphId';

  void _ensureSubgraphCallPrototype(
    SubgraphDefinition subgraph, {
    NodeEditorController? target,
  }) {
    final editor = target ?? controller;
    final prototypeId = _subgraphCallPrototypeId(subgraph.id);
    if (editor.nodePrototypes.containsKey(prototypeId)) {
      editor.unregisterNodePrototype(prototypeId);
    }
    _prototypeTitles[prototypeId] = subgraph.name;
    editor.registerNodePrototype(
      NodePrototype(
        idName: prototypeId,
        displayName: (_) => subgraph.name,
        description: (_) => 'ShowRunner subgraph call: ${subgraph.name}',
        styleBuilder: (_) => NodeStyle(
          decoration: BoxDecoration(
            color: const Color(0xff0891b2).withValues(alpha: 0.16),
            border: Border.all(color: const Color(0xff0891b2)),
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        ports: [
          ControlInputPortPrototype(
            idName: 'exec',
            displayName: (_) => 'Execute',
            styleBuilder: defaultPortStyleBuilder,
          ),
          for (final parameter in subgraph.parameters)
            DataInputPortPrototype<dynamic>(
              idName: parameter['name']?.toString() ?? '',
              displayName: (_) => parameter['name']?.toString() ?? '',
              styleBuilder: defaultPortStyleBuilder,
            ),
          ControlOutputPortPrototype(
            idName: 'completed',
            displayName: (_) => 'Completed',
            styleBuilder: defaultPortStyleBuilder,
          ),
          for (final output in subgraph.outputs)
            DataOutputPortPrototype<dynamic>(
              idName: output['name']?.toString() ?? '',
              displayName: (_) => output['name']?.toString() ?? '',
              styleBuilder: defaultPortStyleBuilder,
            ),
        ],
        onExecute: (ports, fields, state, forward, put) async {
          await forward({'completed'});
        },
      ),
    );
  }

  // Variable nodes expose a typed value output and an optional typed input for
  // updates; their values are persisted separately from executable actions.
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
      styleBuilder: (_) => NodeStyle(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.16),
          border: Border.all(color: color),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      ports: [
        DataInputPortPrototype<dynamic>(
          idName: 'value',
          displayName: (_) => 'Set',
          styleBuilder: defaultPortStyleBuilder,
        ),
        DataOutputPortPrototype<dynamic>(
          idName: 'value',
          displayName: (_) => 'Value',
          styleBuilder: defaultPortStyleBuilder,
        ),
      ],
      onExecute: (ports, fields, state, forward, put) async {},
    );
  }

  NodePrototype _prototype({
    required String idName,
    required String title,
    required Color color,
    required bool input,
    required bool output,
    bool hasPayloadInput = false,
    bool hasPayloadOutput = false,
    List<String>? flowOutputs,
    List<DartDataInputSchema> dataOutputs = const [],
    List<FieldPrototype> fields = const [],
  }) {
    _prototypeTitles[idName] = title;
    return NodePrototype(
      idName: idName,
      displayName: (_) => title,
      description: (_) => 'ShowRunner graph node: $title',
      styleBuilder: (_) => NodeStyle(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.16),
          border: Border.all(color: color),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      ports: [
        if (input)
          ControlInputPortPrototype(
            idName: 'exec',
            displayName: (_) => 'Execute',
            styleBuilder: defaultPortStyleBuilder,
          ),
        if (hasPayloadInput)
          DataInputPortPrototype<dynamic>(
            idName: 'payload',
            displayName: (_) => 'Payload',
            styleBuilder: defaultPortStyleBuilder,
          ),
        if (output || flowOutputs != null)
          ...((flowOutputs ?? const ['completed']).map(
            (port) => ControlOutputPortPrototype(
              idName: port,
              displayName: (_) => _flowPortLabel(port),
              styleBuilder: defaultPortStyleBuilder,
            ),
          )),
        if (hasPayloadOutput)
          DataOutputPortPrototype<dynamic>(
            idName: 'payload',
            displayName: (_) => 'Payload',
            styleBuilder: defaultPortStyleBuilder,
          ),
        for (final dataOutput in dataOutputs)
          DataOutputPortPrototype<dynamic>(
            idName: dataOutput.key ?? dataOutput.label,
            displayName: (_) => dataOutput.label,
            styleBuilder: defaultPortStyleBuilder,
          ),
      ],
      fields: fields,
      onExecute: (ports, fields, state, forward, put) async {
        if (output) await forward({'completed'});
      },
    );
  }

  void loadSampleGraph() {
    controller.clear();
    frames.value = const [];
    selectedFrameId.value = null;
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
    final trigger = controller.addNode(
      'trigger.chatMessage',
      offset: const Offset(-420, -80),
    );
    final queue = controller.addNode(
      'queue.addItem',
      offset: const Offset(-80, -80),
    );
    final overlay = controller.addNode(
      'overlay.pushChat',
      offset: const Offset(260, -80),
    );

    controller.addLink(trigger.id, 'completed', queue.id, 'exec');
    controller.addLink(queue.id, 'completed', overlay.id, 'exec');
  }

  String? addNodeType(
    String nodeType, {
    String? title,
    Offset offset = const Offset(80, 80),
  }) {
    _ensurePrototype(nodeType, title: title);
    final node = controller.addNode(nodeType, offset: offset);
    recentNodeTypes.value = [
      nodeType,
      ...recentNodeTypes.value.where((type) => type != nodeType),
    ].take(8).toList();
    if (title != null && title.trim().isNotEmpty) {
      renameNode(node.id, title);
    }
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
    return node.id;
  }

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
    final zoom = controller.viewportZoom;
    final viewport = Offset(
      -renderObject.size.width / 2 / zoom - controller.viewportOffset.dx,
      -renderObject.size.height / 2 / zoom - controller.viewportOffset.dy,
    );
    return viewport + Offset(local.dx / zoom, local.dy / zoom);
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
    if (conversion) {
      final dataPort = _firstDataOutputPort(anchor);
      if (dataPort != null) {
        controller.addLink(
          anchorEditorId,
          dataPort,
          insertedId,
          _conversionInputPort('value'),
        );
      }
      return insertedId;
    }

    final inputPort = _firstControlInputPort(controller.nodes[insertedId]);
    final outputPort = _preferredFlowOutputPort(controller.nodes[insertedId]);
    if (sourcePort == null || inputPort == null || outputPort == null) {
      return insertedId;
    }
    if (downstream != null) {
      controller.removeLinkById(downstream.id);
    }
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

    final insertedId = addNodeType(
      nodeType,
      offset: offset ?? source.offset + const Offset(280, 0),
    );
    if (insertedId == null) return null;
    final inputPort = _firstControlInputPort(controller.nodes[insertedId]);
    final outputPort = _preferredFlowOutputPort(controller.nodes[insertedId]);
    if (inputPort == null || outputPort == null) return insertedId;
    controller.removeLinkById(link.id);
    controller.addLink(
      link.endpoints.sourceNodeId,
      link.endpoints.sourcePortId,
      insertedId,
      inputPort,
    );
    controller.addLink(
      insertedId,
      outputPort,
      link.endpoints.targetNodeId,
      link.endpoints.targetPortId,
    );
    return insertedId;
  }

  void updateControlNodeData(String editorNodeId, JsonMap data) {
    final node = controller.nodes[editorNodeId];
    if (node == null || !isControlFlowType(node.prototype.idName)) return;
    _nodeDataByEditorId[editorNodeId] = {
      ...?_nodeDataByEditorId[editorNodeId],
      ...Map<String, dynamic>.from(data),
    };
    nodeRevision.value++;
  }

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
    final graphKey = activeSubgraphId ?? _mainGraphKey;
    final invalid = _invalidFlowEdgesByGraph[graphKey];
    if (invalid == null) return;
    final remaining = invalid.where((edge) => edge.id != edgeId).toList();
    if (remaining.length == invalid.length) return;
    _invalidFlowEdgesByGraph[graphKey] = remaining;
    nodeRevision.value++;
  }

  void discardInvalidDataWire(String wireId) {
    final graphKey = activeSubgraphId ?? _mainGraphKey;
    final invalid = _invalidDataWiresByGraph[graphKey];
    if (invalid == null) return;
    final remaining = invalid.where((wire) => wire.id != wireId).toList();
    if (remaining.length == invalid.length) return;
    _invalidDataWiresByGraph[graphKey] = remaining;
    nodeRevision.value++;
  }

  void repairCurrentGraph() {
    loadAutomation(repairAutomation(toAutomation(const AutomationData())));
  }

  void autoLayout() {
    final nodes = controller.nodes.values.toList();
    for (var index = 0; index < nodes.length; index++) {
      final column = index % 4;
      final row = index ~/ 4;
      final node = nodes[index];
      final target = Offset(column * 280.0, row * 180.0);
      controller.selectNodesById({node.id});
      controller.dragSelection(target - node.offset, isWorldDelta: true);
    }
    controller.clearSelection();
  }

  void loadAutomation(AutomationData automation) {
    for (final entry in _controllers.entries.where(
      (entry) => entry.key != _mainGraphKey,
    )) {
      _fieldEvents.remove(entry.value)?.cancel();
      entry.value.dispose();
    }
    _controllers.removeWhere((key, _) => key != _mainGraphKey);
    controller = _controllers[_mainGraphKey]!;
    controller.clear();
    frames.value = _framesFromExtra(automation.extra);
    selectedFrameId.value = null;
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
      graphKey: _mainGraphKey,
      dataWires: automation.dataWires,
      variableNodes: automation.variableNodes,
      triggerNodes: automation.triggerNodes,
    );
  }

  AutomationData toAutomation(AutomationData original) {
    _syncActiveGraph();
    for (final entry in _controllers.entries) {
      if (entry.key == _mainGraphKey || entry.key == activeSubgraphId) {
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
      controller: _controllers[_mainGraphKey]!,
      graphKey: _mainGraphKey,
      original: original.graph,
      dataWires: original.dataWires,
    );
    final savedSubgraphs = subgraphs.value;
    return AutomationData(
      schemaVersion: original.schemaVersion,
      graph: main.graph,
      subgraphs: savedSubgraphs,
      dataWires: main.dataWires,
      variableNodes: _serializeVariableNodes(_controllers[_mainGraphKey]!),
      triggerNodes: _triggerNodeStateInitialized
          ? _serializeTriggerNodes(_controllers[_mainGraphKey]!)
          : original.triggerNodes,
      extra: {
        ...original.extra,
        'editorFrames': frames.value.map((frame) => frame.toJson()).toList(),
      },
    );
  }

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
      final editorNodeType = node.type == 'subgraphCall' && subgraph != null
          ? _subgraphCallPrototypeId(subgraph.id)
          : node.type;
      if (subgraph != null) {
        _ensureSubgraphCallPrototype(subgraph, target: target);
      } else {
        _ensurePrototype(editorNodeType, target: target);
      }
      final editorNode = target.addNode(
        editorNodeType,
        offset: Offset(node.x, node.y),
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
    if (graphKey == _mainGraphKey) {
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
        eventId: edge.id,
      );
      if (link == null) {
        invalidFlowEdges.add(edge);
        continue;
      }
      _schemaIdByLinkSignature[_linkSignature(
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
      _schemaIdByLinkSignature[_linkSignature(
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
      final editorNode = target.addNode(type, offset: offset);
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
      final editorNode = target.addNode('variable.$type', offset: offset);
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
                _schemaIdByLinkSignature[_linkSignature(
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
                _schemaIdByLinkSignature[_linkSignature(
                  link.endpoints.sourceNodeId,
                  link.endpoints.sourcePortId,
                  link.endpoints.targetNodeId,
                  link.endpoints.targetPortId,
                )] ??
                link.id,
            from: from,
            to: to,
            port: link.endpoints.sourcePortId,
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

  List<GraphFrame> _framesFromExtra(JsonMap extra) {
    final rawFrames = extra['editorFrames'];
    if (rawFrames is! List) return const [];
    return [
      for (var index = 0; index < rawFrames.length; index++)
        if (rawFrames[index] is Map)
          GraphFrame.fromJson(
            rawFrames[index] as Map,
            fallbackId: 'frame-$index',
          ),
    ];
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
    editor.registerNodePrototype(
      _prototype(
        idName: nodeType,
        title: title ?? nodeType,
        color: const Color(0xff64748b),
        input: !isTrigger,
        output: true,
        hasPayloadOutput: isTrigger,
        dataOutputs: _resultFieldsForAction(nodeType),
      ),
    );
  }

  List<DartDataInputSchema> _resultFieldsForAction(String nodeType) {
    final parts = nodeType.split('.');
    if (parts.length != 2) return const [];
    final schema = _registry.findAction(parts.first, parts.last)?.resultSchema;
    if (schema?.kind != DartDataInputKind.object) return const [];
    return schema!.fields
        .where((field) => (field.key ?? field.label).trim().isNotEmpty)
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
        styleBuilder: (_) => NodeStyle(
          decoration: BoxDecoration(
            color: const Color(0xff65a30d).withValues(alpha: 0.16),
            border: Border.all(color: const Color(0xff65a30d)),
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        ports: [
          DataInputPortPrototype<dynamic>(
            idName: _conversionInputPort('value'),
            displayName: (_) => 'Value',
            styleBuilder: defaultPortStyleBuilder,
          ),
          if (hasFallback)
            DataInputPortPrototype<dynamic>(
              idName: _conversionInputPort('fallback'),
              displayName: (_) => 'Fallback',
              styleBuilder: defaultPortStyleBuilder,
            ),
          DataOutputPortPrototype<dynamic>(
            idName: 'value',
            displayName: (_) => 'Value',
            styleBuilder: defaultPortStyleBuilder,
          ),
          if (hasConverted)
            DataOutputPortPrototype<dynamic>(
              idName: 'converted',
              displayName: (_) => 'Converted',
              styleBuilder: defaultPortStyleBuilder,
            ),
        ],
        onExecute: (ports, fields, state, forward, put) async {},
      ),
    );
  }

  static String _conversionInputPort(String name) => 'input:$name';

  static String _editorDataInputPortId(NodeDataModel node, String schemaPort) {
    if (_isCoreConversionNodeType(node.prototype.idName)) {
      final inputPort = _conversionInputPort(schemaPort);
      if (node.ports.containsKey(inputPort)) return inputPort;
    }
    return schemaPort;
  }

  static String _editorDataOutputPortId(
    NodeDataModel node,
    String schemaPort,
  ) => schemaPort;

  static String _schemaDataPortName(NodeDataModel? node, String editorPort) {
    if (node != null && _isCoreConversionNodeType(node.prototype.idName)) {
      const prefix = 'input:';
      if (editorPort.startsWith(prefix)) {
        return editorPort.substring(prefix.length);
      }
    }
    return editorPort;
  }

  static bool _isCoreConversionNodeType(String nodeType) {
    final separator = nodeType.indexOf('.');
    return separator > 0 &&
        _isCoreConversionAction(
          nodeType.substring(0, separator),
          nodeType.substring(separator + 1),
        );
  }

  static String? _firstFlowOutputPort(NodeDataModel node) =>
      _preferredFlowOutputPort(node);

  static String? _preferredFlowOutputPort(NodeDataModel? node) {
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

  static String? _firstControlInputPort(NodeDataModel? node) {
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

  static String? _firstDataOutputPort(NodeDataModel node) => node.ports.values
      .where(
        (port) =>
            port.prototype.type == PortType.data &&
            port.prototype.direction == PortDirection.output,
      )
      .map((port) => port.prototype.idName)
      .firstOrNull;

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

  static bool isControlFlowType(String type) => const {
    'if',
    'switch',
    'for',
    'forEach',
    'while',
    'break',
    'continue',
    'return',
  }.contains(type);

  static JsonMap? _defaultControlData(String type) => switch (type) {
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

  static dynamic _coerceSubgraphDefault(String type, dynamic value) {
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

  static const _variableTypes = {'string', 'number', 'boolean', 'color'};

  static const _coreConversionActions = {
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

  static bool _isCoreConversionAction(String pluginId, String actionId) =>
      pluginId.toLowerCase() == 'showrunner' &&
      _coreConversionActions.contains(_normalizeActionId(actionId));

  static JsonMap _defaultCoreConversionConfig(String actionId) {
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

  static JsonMap _defaultCoreConversionResultMapping(String actionId) => {
    'value': 'value',
    if ({
      'convertstringtonumber',
      'convertstringtoboolean',
      'convertjsonstringtoobject',
      'convertjsonstringtoarray',
    }.contains(_normalizeActionId(actionId)))
      'converted': 'converted',
  };

  static String _normalizeActionId(String actionId) =>
      actionId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();

  static dynamic _variableDefault(String type) => switch (type) {
    'number' => 0,
    'boolean' => true,
    'color' => '#ffffff',
    _ => '',
  };

  static dynamic _normalizeVariableValue(String? type, dynamic value) {
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
    controller.focusNodesById(controller.nodes.keys.toSet());
  }

  void dispose() {
    for (final subscription in _fieldEvents.values) {
      subscription.cancel();
    }
    activeNodeIds.dispose();
    frames.dispose();
    subgraphs.dispose();
    activeGraphPath.dispose();
    executionStates.dispose();
    graphFeedback.dispose();
    selectedFrameId.dispose();
    searchQuery.dispose();
    searchMatchIndex.dispose();
    recentNodeTypes.dispose();
    nodeRevision.dispose();
    for (final graphController in _controllers.values) {
      graphController.dispose();
    }
  }

  static String _linkSignature(
    String fromNode,
    String fromPort,
    String toNode,
    String toPort,
  ) => '$fromNode:$fromPort->$toNode:$toPort';

  static FieldPrototype _textField(
    String idName,
    String label,
    String defaultData,
  ) {
    Widget buildEditor(
      BuildContext context,
      Function() removeOverlay,
      dynamic data,
      Function(dynamic data, {required FieldEventType eventType}) setData,
    ) {
      var currentValue = data?.toString() ?? defaultData;
      return Padding(
        padding: const EdgeInsets.all(8),
        child: SizedBox(
          width: 220,
          child: TextFormField(
            autofocus: true,
            initialValue: currentValue,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              labelText: label,
              isDense: true,
              suffixIcon: IconButton(
                tooltip: 'Save',
                icon: const Icon(Icons.check),
                onPressed: () {
                  setData(currentValue, eventType: FieldEventType.submit);
                  removeOverlay();
                },
              ),
            ),
            onChanged: (value) => currentValue = value,
            onFieldSubmitted: (value) {
              setData(value, eventType: FieldEventType.submit);
              removeOverlay();
            },
          ),
        ),
      );
    }

    return FieldPrototype(
      idName: idName,
      displayName: (_) => label,
      dataType: String,
      defaultData: defaultData,
      visualizerBuilder: (data) => Text(
        data?.toString() ?? defaultData,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Color(0xffd5e3e1), fontSize: 11),
      ),
      editorBuilder: buildEditor,
    );
  }
}

class GraphFrame {
  const GraphFrame({
    this.id = '',
    required this.title,
    required this.bounds,
    this.color = '#64b5f6',
    this.nodeIds = const [],
  });

  final String id;
  final String title;
  final Rect bounds;
  final String color;
  final List<String> nodeIds;

  GraphFrame copyWith({
    String? id,
    String? title,
    Rect? bounds,
    String? color,
    List<String>? nodeIds,
  }) => GraphFrame(
    id: id ?? this.id,
    title: title ?? this.title,
    bounds: bounds ?? this.bounds,
    color: color ?? this.color,
    nodeIds: nodeIds ?? this.nodeIds,
  );

  JsonMap toJson() => {
    'id': id,
    'title': title,
    'label': title,
    'color': color,
    'nodeIds': nodeIds,
    'left': bounds.left,
    'top': bounds.top,
    'right': bounds.right,
    'bottom': bounds.bottom,
    'x': bounds.left,
    'y': bounds.top,
    'width': bounds.width,
    'height': bounds.height,
  };

  factory GraphFrame.fromJson(Map value, {String? fallbackId}) {
    final left = _number(value['left'] ?? value['x']);
    final top = _number(value['top'] ?? value['y']);
    final right = value['right'] is num
        ? _number(value['right'])
        : left + _number(value['width']);
    final bottom = value['bottom'] is num
        ? _number(value['bottom'])
        : top + _number(value['height']);
    return GraphFrame(
      id: value['id']?.toString() ?? fallbackId ?? '',
      title:
          value['title']?.toString() ?? value['label']?.toString() ?? 'Frame',
      color: value['color']?.toString() ?? '#64b5f6',
      nodeIds: value['nodeIds'] is List
          ? (value['nodeIds'] as List).map((id) => id.toString()).toList()
          : const [],
      bounds: Rect.fromLTRB(left, top, right, bottom),
    );
  }
}

double _number(Object? value) => value is num ? value.toDouble() : 0;

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

String _flowPortLabel(String port) => switch (port) {
  'then' => 'Then',
  'else' => 'Else',
  'body' => 'Body',
  'next' => 'Done',
  'default' => 'Default',
  'completed' => 'Completed',
  _ when port.startsWith('case:') => 'Case ${port.substring(5)}',
  _ => port,
};

SubgraphDefinition _removeSubgraphCalls(
  SubgraphDefinition subgraph,
  String deletedSubgraphId,
) {
  final removedNodeIds = subgraph.nodes
      .where(
        (node) =>
            node.type == 'subgraphCall' &&
            node.data['subgraphId']?.toString() == deletedSubgraphId,
      )
      .map((node) => node.id)
      .toSet();
  if (removedNodeIds.isEmpty) return subgraph;
  final nodes = subgraph.nodes
      .where((node) => !removedNodeIds.contains(node.id))
      .toList();
  final nodeIds = nodes.map((node) => node.id).toSet();
  return SubgraphDefinition(
    id: subgraph.id,
    name: subgraph.name,
    parameters: subgraph.parameters,
    outputs: subgraph.outputs,
    nodes: nodes,
    edges: subgraph.edges
        .where(
          (edge) => nodeIds.contains(edge.from) && nodeIds.contains(edge.to),
        )
        .toList(),
    dataWires: subgraph.dataWires
        .where(
          (wire) =>
              !removedNodeIds.contains(wire.fromNode) &&
              !removedNodeIds.contains(wire.toNode),
        )
        .toList(),
    entryNodeId: nodeIds.contains(subgraph.entryNodeId)
        ? subgraph.entryNodeId
        : nodes.firstOrNull?.id ?? '',
  );
}
