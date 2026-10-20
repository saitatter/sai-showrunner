import 'dart:async';
import 'package:sai_nodes_core/sai_nodes_core.dart';

import '../../plugins/registry/plugin_registry.dart';
import '../definitions/showrunner_graph_types.dart';
import '../definitions/showrunner_node_definition_provider.dart';
import '../domain/automation_document.dart';

/// Host operations share the canvas controller's document and history. This
/// class stores no second node collection, selection, or persistence model.
final class AutomationEditorController {
  AutomationEditorController({
    required AutomationDocument document,
    DartPluginRegistry? registry,
  }) {
    final currentRegistry = registry ?? DartPluginRegistry();
    _ownedRegistry = registry == null ? currentRegistry : null;
    definitions = ShowrunnerNodeDefinitionProvider(currentRegistry);
    graph = GraphController(
      document: document.graph,
      activeSpaceId: mainAutomationSpace,
      resolver: GraphResolver(
        definitions: definitions.definitions,
        types: createShowrunnerGraphTypes(),
      ),
      documentPolicy: _reconcileEntries,
    );
  }
  late final ShowrunnerNodeDefinitionProvider definitions;
  late final GraphController graph;
  DartPluginRegistry? _ownedRegistry;
  void bindRegistry(DartPluginRegistry registry) {
    definitions.bindRegistry(registry);
    final previous = _ownedRegistry;
    _ownedRegistry = null;
    if (previous != null) _releaseOwnedRegistry(previous);
  }

  AutomationDocument get document =>
      AutomationDocument.fromGraph(graph.document);
  AutomationSubgraph? get activeSubgraph => document.subgraphs.values
      .where((subgraph) => subgraph.spaceId == graph.activeSpaceId)
      .firstOrNull;
  bool get isDirty => graph.isDirty;
  void addListener(void Function() listener) => graph.addListener(listener);
  void removeListener(void Function() listener) =>
      graph.removeListener(listener);

  String addNode(String type, GraphPoint position) {
    final id = newGraphId();
    graph.execute(
      AddNodeCommand(
        graph.activeSpaceId!,
        GraphNode(id: id, type: type, data: definitions.defaultData(type)),
        presentation: NodePresentation(nodeId: id, position: position),
      ),
      label: 'Add node',
    );
    graph.select(GraphSelection(nodes: {id}));
    return id;
  }

  void setEntry(String id) {
    final space = graph.activeSpace!;
    final node = space.nodes[id];
    if (node == null || !_executable(node)) {
      throw ArgumentError('Entry must be an executable node.');
    }
    final subgraph = activeSubgraph;
    final next = subgraph == null
        ? document.withSettings({...document.settings, 'entryNodeId': id})
        : document.withSubgraphs({
            ...document.subgraphs,
            subgraph.id: subgraph.copyWith(entryNodeId: id),
          });
    _metadata(next, 'Set entry node');
  }

  void updateSettings(GraphJson settings) =>
      _metadata(document.withSettings(settings), 'Edit automation settings');
  void updateMetadata(GraphJson metadata) =>
      _metadata(document.withMetadata(metadata), 'Edit automation details');

  void updateField(String nodeId, ResolvedField field, Object? value) {
    final sid = graph.activeSpaceId!;
    final node = graph.activeSpace!.nodes[nodeId]!;
    GraphJson replace(GraphJson source, int depth) {
      final key = field.dataPath[depth];
      if (depth == field.dataPath.length - 1) return {...source, key: value};
      final child = source[key];
      return {
        ...source,
        key: replace(
          child is Map ? Map<String, Object?>.from(child) : {},
          depth + 1,
        ),
      };
    }

    graph.execute(
      UpdateNodeDataCommand(sid, nodeId, replace(node.data, 0)),
      label: 'Edit ${field.label}',
      coalesceKey: (sid, nodeId, field.id),
    );
  }

  String createSubgraph({String name = 'Subgraph'}) {
    final id = newGraphId();
    final entryId = newGraphId();
    final signature = AutomationSubgraph(
      id: id,
      name: name,
      entryNodeId: entryId,
    );
    final next = document.withSubgraphs({...document.subgraphs, id: signature});
    graph.transaction((tx) {
      tx.execute(UpdateDocumentMetadataCommand(next.graph.metadata));
      tx.execute(
        AddSpaceCommand(
          GraphSpace(
            id: signature.spaceId,
            nodes: {entryId: GraphNode(id: entryId, type: 'showrunner.return')},
            nodePresentations: {
              entryId: NodePresentation(
                nodeId: entryId,
                position: const GraphPoint(300, 200),
              ),
            },
          ),
        ),
      );
    }, label: 'Create subgraph');
    graph.setActiveSpace(signature.spaceId);
    return id;
  }

  void updateSubgraph(AutomationSubgraph signature) {
    if (!document.subgraphs.containsKey(signature.id)) {
      throw ArgumentError('Unknown subgraph.');
    }
    _metadata(
      document.withSubgraphs({...document.subgraphs, signature.id: signature}),
      'Edit subgraph signature',
    );
  }

  /// Call sites remain visible and unresolved until repaired; deleting a
  /// declaration must never silently delete user connections in another space.
  void deleteSubgraph(String id) {
    final signature = document.subgraphs[id];
    if (signature == null) return;
    final next = document.withSubgraphs({...document.subgraphs}..remove(id));
    graph.transaction((tx) {
      tx.execute(UpdateDocumentMetadataCommand(next.graph.metadata));
      tx.execute(RemoveSpaceCommand(signature.spaceId));
    }, label: 'Delete subgraph');
  }

  void load(AutomationDocument document) =>
      graph.replaceDocument(document.graph);
  void markSaved() => graph.markSaved();
  void _metadata(AutomationDocument next, String label) => graph.execute(
    UpdateDocumentMetadataCommand(next.graph.metadata),
    label: label,
  );
  Future<void> _teardown = Future.value();
  bool _disposed = false;
  Future<void> get teardownComplete => _teardown;
  void _releaseOwnedRegistry(DartPluginRegistry registry) {
    _teardown = Future.wait([_teardown, registry.close()]).then<void>((_) {});
    // A synchronous widget dispose cannot await; the session owner awaits this
    // retained future and reports any failure during application teardown.
    _teardown.ignore();
  }

  Future<void> close() {
    dispose();
    return _teardown;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    graph.dispose();
    definitions.dispose();
    final registry = _ownedRegistry;
    _ownedRegistry = null;
    if (registry != null) _releaseOwnedRegistry(registry);
  }
}

bool _executable(GraphNode node) => !{
  'variable',
  'parameter',
  'unresolved',
}.contains(automationNodeKind(node.type));

GraphDocument _reconcileEntries(GraphDocument before, GraphDocument candidate) {
  final previous = AutomationDocument.fromGraph(before);
  var next = AutomationDocument.fromGraph(candidate);
  String reconcile(String spaceId, String entry, String oldEntry) {
    final space = candidate.spaces[spaceId];
    if (space == null) return entry;
    if (entry.isNotEmpty && space.nodes.containsKey(entry)) return entry;
    // Preserve invalid imported references for diagnostics. Repair only an
    // empty entry or a node removed by the current authoring transaction.
    if (entry.isNotEmpty &&
        !(entry == oldEntry &&
            (before.spaces[spaceId]?.nodes.containsKey(entry) ?? false))) {
      return entry;
    }
    final executable = space.nodes.values.where(_executable).toList();
    final incoming = space.connections.values
        .where((edge) => edge.kind == GraphConnectionKind.control)
        .map((edge) => edge.to.nodeId)
        .toSet();
    return executable
            .where((node) => automationNodeKind(node.type) == 'trigger')
            .firstOrNull
            ?.id ??
        executable
            .where((node) => !incoming.contains(node.id))
            .firstOrNull
            ?.id ??
        executable.firstOrNull?.id ??
        '';
  }

  final entry = reconcile(
    mainAutomationSpace,
    next.entryNodeId,
    previous.entryNodeId,
  );
  if (entry != next.entryNodeId) {
    next = next.withSettings({...next.settings, 'entryNodeId': entry});
  }
  final signatures = {...next.subgraphs};
  var changed = false;
  for (final subgraph in signatures.values.toList()) {
    final id = reconcile(
      subgraph.spaceId,
      subgraph.entryNodeId,
      previous.subgraphs[subgraph.id]?.entryNodeId ?? '',
    );
    if (id != subgraph.entryNodeId) {
      signatures[subgraph.id] = subgraph.copyWith(entryNodeId: id);
      changed = true;
    }
  }
  return changed ? next.withSubgraphs(signatures).graph : next.graph;
}
