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
import 'sai_nodes/showrunner_clipboard_payload.dart';
import 'graph_node_style.dart';
import 'models/graph_editor_models.dart';
import 'search/graph_search_service.dart';

part 'persistence/graph_editor_persistence.dart';
part 'nodes/showrunner_node_presentation.dart';
part 'subgraphs/showrunner_graph_subgraphs.dart';

typedef GraphResourceOptionsLoader =
    Future<List<String>> Function(String resourceType);

const _fallbackGraphNodeSize = Size(220, 90);

double _number(Object? value) => value is num ? value.toDouble() : 0;

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

String _summarizeGraphValue(dynamic value) {
  if (value == null) return '—';
  if (value is String) {
    if (value.isEmpty) return '—';
    return value.length > 28 ? '${value.substring(0, 25)}…' : value;
  }
  if (value is num || value is bool) return value.toString();
  if (value is List) {
    return '[${value.length} item${value.length == 1 ? '' : 's'}]';
  }
  if (value is Map) {
    if (value.isEmpty) return '{}';
    final keys = value.keys.take(2).map((key) => key.toString()).join(', ');
    return '{$keys${value.length > 2 ? '…' : ''}}';
  }
  return value.toString();
}

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

Size _showRunnerMinimumNodeSize({
  required int inputPortCount,
  required int outputPortCount,
  required int fieldCount,
}) {
  // The outer sequence handles are not part of the visible port columns. The
  // remaining rows need enough vertical room for both labels and type hints.
  final visiblePortRows = math.max(
    0,
    math.max(inputPortCount - 1, outputPortCount - 1),
  );
  return Size(
    220,
    math.max(104, 104 + visiblePortRows * 24 + fieldCount * 28).toDouble(),
  );
}

/// Adapter between ShowRunner's graph schema and the `sai_nodes` editor model.
///
/// `sai_nodes` owns generic canvas behavior. This adapter owns the translation
/// to persisted ShowRunner IDs, plugin semantics, and domain-only graph state.
class ShowRunnerGraphEditor {
  ShowRunnerGraphEditor({
    DartPluginRegistry? registry,
    this.resourceOptionsLoader,
  }) : _registry = registry ?? createDefaultPluginRegistry() {
    nodeRevision.addListener(_markDocumentDirtyFromRevision);
    controller = _createController();
    _controllers[_mainGraphKey] = controller;
    _syncFrameProjection(controller);
    _searchService = GraphSearchService(
      controllerProvider: () => controller,
      titleForNode: (id) => _nodePresentationTitle(this, id),
      dataForNode: (id) => _nodePresentationData(this, id),
    );
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
  final GraphResourceOptionsLoader? resourceOptionsLoader;
  final Map<String, NodeEditorController> _controllers = {};
  late final GraphSearchService _searchService;
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

  /// A read-only projection of the main graph's generic frames.
  ///
  /// Frame geometry, membership, and history belong to `sai_nodes`. This
  /// notifier exists only so ShowRunner widgets can rebuild without knowing
  /// about the controller's internal map.
  final ValueNotifier<List<NodeFrame>> frames = ValueNotifier(const []);
  final Map<String, String> _frameColors = {};
  final ValueNotifier<String?> selectedFrameId = ValueNotifier(null);
  final ValueNotifier<List<SubgraphDefinition>> subgraphs = ValueNotifier(
    const [],
  );
  final ValueNotifier<Map<String, GraphNodeExecutionVisual>> executionStates =
      ValueNotifier(const {});
  final ValueNotifier<List<GraphAlignmentGuide>> alignmentGuides =
      ValueNotifier(const []);
  final ValueNotifier<String?> dropTargetNodeId = ValueNotifier(null);
  final ValueNotifier<String?> dropTargetLinkId = ValueNotifier(null);
  final ValueNotifier<String?> selectedInvalidFlowEdgeId = ValueNotifier(null);
  final ValueNotifier<String?> selectedInvalidDataWireId = ValueNotifier(null);

  /// State for the editor-only preview playhead. This never starts runtime
  /// plugins or executes actions; it only previews graph order and timing.
  final ValueNotifier<String?> previewNodeId = ValueNotifier(null);
  final ValueNotifier<bool> previewPlaying = ValueNotifier(false);
  final ValueNotifier<Duration> previewElapsed = ValueNotifier(Duration.zero);
  final ValueNotifier<String?> graphFeedback = ValueNotifier(null);
  ValueNotifier<String> get searchQuery => _searchService.query;
  ValueNotifier<int> get searchMatchIndex => _searchService.matchIndex;
  ValueNotifier<bool> get canvasSearchOpen => _searchService.isOpen;
  final ValueNotifier<List<String>> recentNodeTypes = ValueNotifier(const []);
  final ValueNotifier<int> nodeRevision = ValueNotifier(0);
  final ValueNotifier<bool> documentDirty = ValueNotifier(false);
  final Map<String, String> _nodeTitles = {};
  final Map<String, String> _prototypeTitles = {};
  String? _clipboardFallbackPayload;
  // Trigger metadata is separate from executable trigger nodes so persisted
  // trigger subscriptions can be restored without changing node prototypes.
  final Set<String> _triggerEditorIds = {};
  bool _triggerNodeStateInitialized = false;
  bool _suspendDirtyTracking = false;
  Timer? _previewTimer;
  DateTime? _previewStartedAt;

  String? get activeSubgraphId => activeGraphPath.value.lastOrNull;

  String frameColor(String frameId) => _frameColors[frameId] ?? '#64b5f6';

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
    late final NodeEditorController created;
    created = NodeEditorController(
      config: const NodeEditorConfig(
        autoBuildGraph: false,
        autoRunGraph: false,
        enableNodeResize: true,
        minZoom: 0.35,
        maxZoom: 1.5,
        snapToGridSize: 42,
        defaultNodeWidth: 220,
        edgeInputPortId: 'exec',
        edgeOutputPortId: 'completed',
        minimumNodeSizeBuilder: _showRunnerMinimumNodeSize,
      ),
      style: const NodeEditorStyle(
        decoration: BoxDecoration(color: Color(0xff202020)),
        gridStyle: GridStyle(
          gridSpacingX: 42,
          gridSpacingY: 42,
          lineWidth: 1,
          lineColor: Color(0xff353535),
          intersectionColor: Color(0xff353535),
          intersectionRadius: 0,
          showGrid: true,
        ),
        highlightAreaStyle: HighlightAreaStyle(
          color: Color.fromARGB(38, 185, 117, 255),
          borderWidth: 1.5,
          borderColor: Color.fromARGB(190, 212, 137, 255),
          borderDrawMode: LineDrawMode.solid,
        ),
        linkLabelStyle: LinkLabelStyle(
          textStyle: TextStyle(
            color: Color(0xfff7e7ff),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
          backgroundColor: Color(0xeb121216),
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          borderRadius: BorderRadius.all(Radius.circular(11)),
          maxWidth: 150,
          minWidth: 60,
        ),
      ),
      clipboardPayloadEncoder: _encodeClipboardPayload,
      clipboardPayloadDecoder: _decodeClipboardPayload,
      onCallback: (type, message) {
        debugPrint('sai_nodes $type: $message');
        if (type == CallbackType.error) graphFeedback.value = message;
      },
    );
    _registerPrototypes(created);
    _fieldEvents[created] = created.eventBus.events.listen((event) {
      _markDocumentDirtyFromEvent(event);
      if (event is NodeFrameChangeEvent &&
          identical(created, _controllers[_mainGraphKey])) {
        if (event.nextFrame == null) _frameColors.remove(event.frameId);
        _syncFrameProjection(created);
      }
      if ((event is NodeSelectionEvent && event.nodeIds.isNotEmpty) ||
          (event is LinkSelectionEvent && event.linkIds.isNotEmpty)) {
        clearInvalidSelection();
      }
      if (event is DragSelectionStartEvent) {
        alignmentGuides.value = const [];
      }
      if (event is DragSelectionEvent &&
          identical(created, _controllers[_mainGraphKey])) {
        _placeDraggedNodesInFrame(event.nodeIds);
      }
      if (event is DragSelectionEvent) {
        _updateAlignmentGuides(created, event.nodeIds);
      }
      if (event is DragSelectionEndEvent) {
        alignmentGuides.value = const [];
      }
      if (event is RemoveNodeEvent &&
          identical(created, _controllers[_mainGraphKey])) {
        _removeEditorNodeFromFrames(event.node.id);
        _triggerEditorIds.remove(event.node.id);
        _nodeDataByEditorId.remove(event.node.id);
        _nodeTitles.remove(event.node.id);
        _schemaIdByEditorId.remove(event.node.id);
      }
      if (event is AddNodeEvent) {
        _trackAddedNode(created, event.node);
      }
      if (event is AddLinkEvent &&
          event.link.endpoints.sourceNodeId.isNotEmpty) {
        final source = created.nodes[event.link.endpoints.sourceNodeId];
        final sourcePort = source?.ports[event.link.endpoints.sourcePortId];
        if (sourcePort?.prototype.type == PortType.control) {
          created.setLinkLabel(
            event.link.id,
            _flowLinkLabel(
              event.link.endpoints.sourcePortId,
              source: _schemaNodeForEditorNode(
                created,
                event.link.endpoints.sourceNodeId,
              ),
            ),
          );
        }
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

  void _syncFrameProjection(NodeEditorController graphController) {
    if (!identical(graphController, _controllers[_mainGraphKey])) return;
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
    if (draggedIds.isEmpty) {
      alignmentGuides.value = const [];
      return;
    }

    final dragged = graphController.nodes[draggedIds.first];
    if (dragged == null) {
      alignmentGuides.value = const [];
      return;
    }

    final draggedBounds = _nodeWorldBounds(dragged);
    final references = graphController.nodes.values.where(
      (node) => !draggedIds.contains(node.id),
    );
    const threshold = 6.0;
    var bestX = threshold + 1;
    var bestY = threshold + 1;
    final xMatches = <(double, double)>[];
    final yMatches = <(double, double)>[];

    for (final reference in references) {
      final bounds = _nodeWorldBounds(reference);
      final xPairs = <(double, double)>[
        (draggedBounds.left, bounds.left),
        (draggedBounds.left, bounds.right),
        (draggedBounds.right, bounds.left),
        (draggedBounds.right, bounds.right),
        (draggedBounds.center.dx, bounds.center.dx),
      ];
      for (final pair in xPairs) {
        final distance = (pair.$1 - pair.$2).abs();
        if (distance < bestX) {
          bestX = distance;
          xMatches
            ..clear()
            ..add(pair);
        } else if (distance == bestX) {
          xMatches.add(pair);
        }
      }

      final yPairs = <(double, double)>[
        (draggedBounds.top, bounds.top),
        (draggedBounds.top, bounds.bottom),
        (draggedBounds.bottom, bounds.top),
        (draggedBounds.bottom, bounds.bottom),
        (draggedBounds.center.dy, bounds.center.dy),
      ];
      for (final pair in yPairs) {
        final distance = (pair.$1 - pair.$2).abs();
        if (distance < bestY) {
          bestY = distance;
          yMatches
            ..clear()
            ..add(pair);
        } else if (distance == bestY) {
          yMatches.add(pair);
        }
      }
    }

    if (bestX > threshold && bestY > threshold) {
      alignmentGuides.value = const [];
      return;
    }

    final guides = <GraphAlignmentGuide>[];
    if (bestX <= threshold) {
      for (final match in xMatches) {
        guides.add(
          GraphAlignmentGuide(
            axis: GraphAlignmentAxis.vertical,
            position: match.$2,
            from: draggedBounds.top,
            to: draggedBounds.bottom,
          ),
        );
      }
    }
    if (bestY <= threshold) {
      for (final match in yMatches) {
        guides.add(
          GraphAlignmentGuide(
            axis: GraphAlignmentAxis.horizontal,
            position: match.$2,
            from: draggedBounds.left,
            to: draggedBounds.right,
          ),
        );
      }
    }
    final seen = <String>{};
    alignmentGuides.value = guides.where((guide) {
      final key = '${guide.axis}:${guide.position}:${guide.from}:${guide.to}';
      return seen.add(key);
    }).toList();
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

  /// Applies the desktop editor's delete command to the active selection.
  ///
  /// Annotation frames are editor resources rather than sai_nodes graph
  /// nodes, so they must be deleted here before delegating node/link deletion
  /// to the generic controller.
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
        styleBuilder: (state) => graphNodeStyle(state, const Color(0xff4dd0e1)),
        ports: [
          ControlInputPortPrototype(
            idName: 'exec',
            displayName: (_) => 'Execute',
            styleBuilder: _flowPortStyleBuilder,
          ),
          for (final parameter in subgraph.parameters)
            _subgraphPort(parameter, input: true),
          ControlOutputPortPrototype(
            idName: 'completed',
            displayName: (_) => 'Completed',
            styleBuilder: _flowPortStyleBuilder,
          ),
          for (final output in subgraph.outputs)
            _subgraphPort(output, input: false),
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

  static PortPrototype _subgraphPort(JsonMap port, {required bool input}) {
    final id = port['name']?.toString().trim() ?? '';
    final label = port['label']?.toString().trim();
    return _typedPort(
      idName: id,
      label: label == null || label.isEmpty ? id : label,
      kind: _kindForTypeName(port['type']?.toString()),
      input: input,
    );
  }

  static PortPrototype _dataPort(
    DartDataInputSchema schema, {
    required bool input,
  }) => _typedPort(
    idName: schema.key ?? schema.label,
    label: schema.label,
    kind: schema.kind,
    input: input,
  );

  /// Creates the concrete generic port instance required by sai_nodes. Using
  /// a real generic type here is important: sai_nodes uses it to reject an
  /// invalid data connection before it reaches the persisted graph.
  static PortPrototype _typedPort({
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

  static DartDataInputKind _kindForVariableType(String type) =>
      _kindForTypeName(type);

  static DartDataInputKind _kindForTypeName(String? type) =>
      switch (type?.trim().toLowerCase()) {
        'string' || 'text' => DartDataInputKind.text,
        'number' || 'num' || 'double' || 'int' => DartDataInputKind.number,
        'boolean' || 'bool' => DartDataInputKind.boolean,
        'array' || 'list' => DartDataInputKind.array,
        'object' || 'map' || 'json' => DartDataInputKind.object,
        'color' => DartDataInputKind.color,
        _ => DartDataInputKind.object,
      };

  static PortStyle _flowPortStyleBuilder(PortState state) =>
      _portStyle(const Color(0xffe9aaff), state);

  static PortStyle Function(PortState) _dataPortStyleBuilder(
    DartDataInputKind kind,
  ) =>
      (state) => _portStyle(_dataPortColor(kind), state);

  static PortStyle _portStyle(Color color, PortState state) => PortStyle(
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

  static Color _dataPortColor(DartDataInputKind kind) => switch (kind) {
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
  ///
  /// This is intentionally resolved through the same RenderBox-local
  /// conversion used by insertion. Keeping both operations on one coordinate
  /// path prevents drag-and-drop from reintroducing the selection offset bug.
  String? nodeIdAtScreenPosition(Offset screenPosition) {
    final renderObject = controller.editorKey.currentContext
        ?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return null;
    final local = renderObject.globalToLocal(screenPosition);
    final world = controller.screenToWorld(local, renderObject.size);
    final candidates = controller.nodesSpatialHashGrid.queryCoords(world);
    for (final id in candidates.toList().reversed) {
      final node = controller.nodes[id];
      if (node != null && _nodeWorldBounds(node).contains(world)) return id;
    }
    return null;
  }

  /// Updates the visual drop target used when an action is dragged from the
  /// palette over the graph. A flow edge takes precedence over a node so the
  /// drop can insert into an existing sequence instead of appending after a
  /// node that happens to overlap the edge hit area.
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
  ///
  /// `sai_nodes` owns the actual pointer hit-test. This read-only projection
  /// is for ShowRunner's product-specific workflow where dragging an action
  /// from the palette onto an existing sequence edge inserts it between the
  /// two connected nodes, matching `main`.
  String? flowLinkIdAtScreenPosition(Offset screenPosition) {
    final renderObject = controller.editorKey.currentContext
        ?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return null;
    final local = renderObject.globalToLocal(screenPosition);
    final world = controller.screenToWorld(local, renderObject.size);

    final tolerance = 12 / controller.viewportZoom;
    for (final link in controller.linksAsList) {
      final source = controller.nodes[link.endpoints.sourceNodeId];
      final target = controller.nodes[link.endpoints.targetNodeId];
      final sourcePort = source?.ports[link.endpoints.sourcePortId];
      final targetPort = target?.ports[link.endpoints.targetPortId];
      if (source == null ||
          target == null ||
          sourcePort == null ||
          targetPort == null ||
          sourcePort.prototype.type != PortType.control) {
        continue;
      }

      final start = source.offset + sourcePort.offset;
      final end = target.offset + targetPort.offset;
      final control = math.min((end.dx - start.dx).abs() / 2, 400).toDouble();
      final firstControl = Offset(start.dx + control, start.dy);
      final secondControl = Offset(end.dx - control, end.dy);
      var previous = start;
      for (var index = 1; index <= 32; index++) {
        final t = index / 32;
        final inverse = 1 - t;
        final point =
            start * (inverse * inverse * inverse) +
            firstControl * (3 * inverse * inverse * t) +
            secondControl * (3 * inverse * t * t) +
            end * (t * t * t);
        if (_distanceToSegment(world, previous, point) <= tolerance) {
          return link.id;
        }
        previous = point;
      }
    }
    return null;
  }

  static double _distanceToSegment(Offset point, Offset start, Offset end) {
    final delta = end - start;
    final lengthSquared = delta.dx * delta.dx + delta.dy * delta.dy;
    if (lengthSquared == 0) return (point - start).distance;
    final projection =
        ((point.dx - start.dx) * delta.dx + (point.dy - start.dy) * delta.dy) /
        lengthSquared;
    final t = projection.clamp(0.0, 1.0).toDouble();
    final closest = Offset(start.dx + delta.dx * t, start.dy + delta.dy * t);
    return (point - closest).distance;
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
      // Conversion actions are data-only in the reference editor. They are
      // inserted without sequence flow or an implicit data wire; the user
      // explicitly connects a compatible value port afterwards.
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
        _schemaIdByLinkSignature[_linkSignature(
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
      _schemaIdByLinkSignature[_linkSignature(
            incoming.endpoints.sourceNodeId,
            incoming.endpoints.sourcePortId,
            incoming.endpoints.targetNodeId,
            incoming.endpoints.targetPortId,
          )] =
          schemaLinkId;
    }
    return inserted.id;
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
    if (selectedInvalidFlowEdgeId.value == edgeId) {
      selectedInvalidFlowEdgeId.value = null;
    }
    nodeRevision.value++;
  }

  void discardInvalidDataWire(String wireId) {
    final graphKey = activeSubgraphId ?? _mainGraphKey;
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

  JsonMap _serializeFrame(NodeFrame frame) {
    final schemaMembers = frame.members
        .map((id) => _schemaIdByEditorId[id])
        .whereType<String>()
        .toList();
    return {
      'id': frame.id,
      'title': frame.title,
      'label': frame.title,
      'color': frameColor(frame.id),
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

  static List<DartDataInputSchema> _objectSchemaFields(
    DartDataInputSchema? schema,
  ) {
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

  static DartDataInputKind _conversionValueKind(String normalized) =>
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

  static DartDataInputKind _conversionResultKind(String normalized) =>
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
    controller.focusNodesById(controller.nodes.keys.toSet(), animate: false);
  }

  List<NodeDataModel> get _previewNodes =>
      controller.nodes.values.where((node) => !isTriggerNode(node.id)).toList()
        ..sort((a, b) {
          final x = a.offset.dx.compareTo(b.offset.dx);
          return x != 0 ? x : a.offset.dy.compareTo(b.offset.dy);
        });

  Duration previewDurationFor(String nodeId) {
    final data = _nodeDataByEditorId[nodeId];
    final config = data?['config'];
    if (config is Map) {
      for (final key in const [
        'duration',
        'durationSeconds',
        'delay',
        'seconds',
      ]) {
        final value = config[key];
        final seconds = value is num
            ? value.toDouble()
            : double.tryParse('$value');
        if (seconds != null && seconds.isFinite && seconds > 0) {
          return Duration(milliseconds: (seconds * 1000).round());
        }
      }
    }
    return const Duration(milliseconds: 900);
  }

  Duration get previewTotal => _previewNodes.fold(
    Duration.zero,
    (total, node) => total + previewDurationFor(node.id),
  );

  double get previewProgress {
    final total = previewTotal.inMicroseconds;
    if (total <= 0) return 0;
    return (previewElapsed.value.inMicroseconds / total).clamp(0, 1).toDouble();
  }

  String? get previewRouteLabel {
    final node = controller.nodes[previewNodeId.value];
    return node?.prototype.idName;
  }

  void togglePreview() {
    if (previewPlaying.value) {
      _stopPreview();
      return;
    }
    final total = previewTotal;
    if (total <= Duration.zero) return;
    if (previewElapsed.value >= total) previewElapsed.value = Duration.zero;
    previewPlaying.value = true;
    _previewStartedAt = DateTime.now().subtract(previewElapsed.value);
    _updatePreview();
    _previewTimer ??= Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => _updatePreview(),
    );
  }

  void _updatePreview() {
    if (!previewPlaying.value) return;
    final total = previewTotal;
    final startedAt = _previewStartedAt;
    if (startedAt == null || total <= Duration.zero) {
      resetPreview();
      return;
    }
    final elapsed = DateTime.now().difference(startedAt);
    previewElapsed.value = elapsed >= total ? total : elapsed;
    var remaining = previewElapsed.value;
    String? current;
    for (final node in _previewNodes) {
      final duration = previewDurationFor(node.id);
      if (remaining < duration) {
        current = node.id;
        break;
      }
      remaining -= duration;
    }
    previewNodeId.value = current ?? _previewNodes.lastOrNull?.id;
    if (elapsed >= total) _stopPreview();
  }

  void _stopPreview() {
    previewPlaying.value = false;
    _previewTimer?.cancel();
    _previewTimer = null;
  }

  void resetPreview() {
    _stopPreview();
    previewElapsed.value = Duration.zero;
    previewNodeId.value = null;
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
    alignmentGuides.dispose();
    dropTargetNodeId.dispose();
    dropTargetLinkId.dispose();
    selectedInvalidFlowEdgeId.dispose();
    selectedInvalidDataWireId.dispose();
    _previewTimer?.cancel();
    previewNodeId.dispose();
    previewPlaying.dispose();
    previewElapsed.dispose();
    graphFeedback.dispose();
    selectedFrameId.dispose();
    _searchService.dispose();
    recentNodeTypes.dispose();
    nodeRevision.removeListener(_markDocumentDirtyFromRevision);
    nodeRevision.dispose();
    documentDirty.dispose();
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
}

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

String? _flowLinkLabel(String? port, {GraphNode? source}) {
  if (port == null || port == 'completed') return null;
  return switch (port) {
    'then' => 'then',
    'else' => 'else',
    'default' => 'default',
    'body' => 'loop body',
    'next' => 'done',
    _ when port.startsWith('case:') => _switchCaseLabel(port, source),
    _ => port,
  };
}

String _switchCaseLabel(String port, GraphNode? source) {
  final cases = source?.data['cases'];
  if (cases is List) {
    for (final item in cases.whereType<Map>()) {
      if (item['port']?.toString() == port) {
        return 'case: ${item['value'] ?? port.substring(5)}';
      }
    }
  }
  return 'case ${port.substring(5)}';
}

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
