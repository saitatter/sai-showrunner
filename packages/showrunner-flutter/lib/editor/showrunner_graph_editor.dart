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
import 'search/graph_search_controller.dart';

part 'persistence/automation_graph_serializer.dart';
part 'adapter/automation_graph_adapter.dart';
part 'nodes/showrunner_node_presentation.dart';
part 'subgraphs/subgraph_editor_coordinator.dart';
part 'clipboard/showrunner_graph_clipboard.dart';
part 'validation/graph_diagnostics.dart';
part 'execution/graph_execution_visuals.dart';
part 'interaction/action_drop_controller.dart';
part 'frames/frame_persistence_adapter.dart';

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
    _searchService = GraphSearchController(
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

  late NodeEditorController controller;
  final DartPluginRegistry _registry;
  final GraphResourceOptionsLoader? resourceOptionsLoader;
  final Map<String, NodeEditorController> _controllers = {};
  late final GraphSearchController _searchService;
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
      clipboardPayloadEncoder: (nodes) =>
          _encodeShowRunnerClipboardPayload(this, nodes),
      clipboardPayloadDecoder: (payload, nodes) =>
          _decodeClipboardPayload(payload, nodes),
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
