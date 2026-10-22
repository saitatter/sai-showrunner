import 'automation_graph_toolbar.dart';
import 'automation_graph_inspector.dart';
import 'automation_node_picker.dart';
import 'automation_execution_bar.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sai_nodes/sai_nodes.dart'
    show
        NodeEditor,
        GraphNodePickerRequest,
        ConnectionRouting,
        GraphSceneBuilder;
import 'package:sai_nodes_core/sai_nodes_core.dart';

import '../../components/data_inputs/resource_schema.dart';
import '../controller/automation_editor_controller.dart';
import '../controller/automation_clipboard.dart';
import '../domain/automation_document.dart';
import '../execution/showrunner_execution_visual_adapter.dart';
import 'showrunner_node_widgets.dart';

/// Product palette, inspector and run controls around the generic canvas.
class AutomationGraphWorkspace extends StatefulWidget {
  const AutomationGraphWorkspace({
    super.key,
    required this.editor,
    this.onRun,
    this.execution,
    this.resourceOptionsLoader,
    this.onRunNode,
  });
  final AutomationEditorController editor;
  final Future<void> Function(AutomationDocument document)? onRun;
  final ShowrunnerExecutionVisualAdapter? execution;
  final ResourceOptionsLoader? resourceOptionsLoader;
  final Future<void> Function(String nodeId)? onRunNode;
  @override
  State<AutomationGraphWorkspace> createState() =>
      AutomationGraphWorkspaceState();
}

class AutomationGraphWorkspaceState extends State<AutomationGraphWorkspace> {
  AutomationEditorController get editor => widget.editor;
  bool inspector = true, snapping = false, running = false;
  Object? _runOwner;
  BuildContext? _inspectorSheetContext;
  ConnectionRouting routing = ConnectionRouting.bezier;
  GraphSize viewport = const GraphSize(800, 600);
  @override
  void initState() {
    super.initState();
    editor.addListener(_changed);
  }

  @override
  void didUpdateWidget(AutomationGraphWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.editor != editor) {
      oldWidget.editor.removeListener(_changed);
      editor.addListener(_changed);
      _runOwner = null;
      running = false;
      final sheet = _inspectorSheetContext;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (sheet != null && sheet.mounted) {
          final route = ModalRoute.of(sheet);
          if (route != null && route.isActive) {
            Navigator.of(sheet).removeRoute(route);
          }
        }
      });
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    editor.removeListener(_changed);
    super.dispose();
  }

  void _error(Object error) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Graph action could not be completed. Check the configuration and retry.',
          ),
        ),
      );
    }
  }

  void fitGraph() => _fit();
  Future<void> _findNode() async {
    final owner = editor;
    var query = '';
    final selected = await showDialog<(String, String)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, refresh) {
          final matches = [
            for (final space in owner.document.graph.spaces.values)
              for (final node in space.nodes.values)
                if ('${space.nodePresentations[node.id]?.title ?? ''} ${node.id} ${node.type} ${node.data}'
                    .toLowerCase()
                    .contains(query.toLowerCase()))
                  (space, node),
          ];
          return AlertDialog(
            title: const Text('Find in graph'),
            content: SizedBox(
              width: 520,
              height: 420,
              child: Column(
                children: [
                  TextField(
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Search graph nodes',
                    ),
                    onChanged: (value) => refresh(() => query = value),
                  ),
                  Expanded(
                    child: ListView(
                      children: [
                        for (final (space, node) in matches)
                          ListTile(
                            title: Text(
                              space.nodePresentations[node.id]?.title ??
                                  node.type,
                            ),
                            subtitle: Text('${space.id} · ${node.id}'),
                            onTap: () =>
                                Navigator.pop(context, (space.id, node.id)),
                          ),
                        if (matches.isEmpty)
                          const ListTile(title: Text('No matching nodes')),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          );
        },
      ),
    );
    if (!mounted || selected == null || !identical(owner, editor)) return;
    if (owner.graph.document.spaces[selected.$1]?.nodes.containsKey(
          selected.$2,
        ) !=
        true) {
      return;
    }
    editor.graph.setActiveSpace(selected.$1);
    editor.graph.select(GraphSelection(nodes: {selected.$2}));
    final scene = GraphSceneBuilder().build(editor.graph);
    editor.graph.focusNodes(
      {selected.$2},
      {
        for (final node in scene.nodes.values)
          node.node.id: node.geometry.bounds,
      },
      viewport,
    );
  }

  Future<void> _toggleInspector() async {
    final width = (context.findRenderObject() as RenderBox?)?.size.width ?? 800;
    if (width >= 660) {
      setState(() => inspector = !inspector);
      return;
    }
    final changes = ValueNotifier(0);
    void changed() => changes.value++;
    final currentEditor = editor;
    currentEditor.addListener(changed);
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (context) {
          _inspectorSheetContext = context;
          return SizedBox(
            height: MediaQuery.sizeOf(context).height * .8,
            child: ListenableBuilder(
              listenable: changes,
              builder: (context, _) => AutomationGraphInspector(
                editor: currentEditor,
                onRunNode: widget.onRunNode == null ? null : _runFromNode,
                onError: _error,
                resourceOptionsLoader: widget.resourceOptionsLoader,
              ),
            ),
          );
        },
      );
    } finally {
      _inspectorSheetContext = null;
      currentEditor.removeListener(changed);
      changes.dispose();
    }
  }

  void _fit() {
    final scene = GraphSceneBuilder().build(editor.graph);
    editor.graph.fitSpace({
      for (final node in scene.nodes.values) node.node.id: node.geometry.bounds,
    }, viewport);
  }

  Future<GraphNode?> _pick(GraphNodePickerRequest request) async {
    final owner = editor;
    final space = owner.graph.activeSpaceId;
    final node = await showDialog<GraphNode>(
      context: context,
      builder: (context) => AutomationNodePicker(editor: owner),
    );
    if (!mounted ||
        !identical(owner, editor) ||
        owner.graph.activeSpaceId != space) {
      return null;
    }
    return node;
  }

  Future<void> _add() async {
    final position = editor.graph.camera.viewportToWorld(
      GraphPoint(viewport.width / 2 - 130, viewport.height / 2 - 80),
    );
    final node = await _pick(GraphNodePickerRequest(position: position));
    if (node == null || !mounted) return;
    editor.graph.execute(
      AddNodeCommand(
        editor.graph.activeSpaceId!,
        node,
        presentation: NodePresentation(nodeId: node.id, position: position),
      ),
      label: 'Add node',
    );
    editor.graph.select(GraphSelection(nodes: {node.id}));
  }

  Future<void> _run() async {
    if (running || widget.onRun == null) return;
    final owner = editor;
    final lease = Object();
    _runOwner = lease;
    setState(() => running = true);
    try {
      await widget.onRun!(owner.document);
    } catch (error) {
      if (mounted && identical(owner, editor) && identical(lease, _runOwner)) {
        _error(error);
      }
    } finally {
      if (mounted && identical(lease, _runOwner)) {
        _runOwner = null;
        setState(() => running = false);
      }
    }
  }

  Future<void> _runFromNode(String nodeId) async {
    if (running || widget.onRunNode == null) return;
    final owner = editor;
    final lease = Object();
    _runOwner = lease;
    setState(() => running = true);
    try {
      await widget.onRunNode!(nodeId);
    } catch (error) {
      if (mounted && identical(owner, editor) && identical(lease, _runOwner)) {
        _error(error);
      }
    } finally {
      if (mounted && identical(lease, _runOwner)) {
        _runOwner = null;
        setState(() => running = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final graph = editor.graph;
    return Column(
      children: [
        AutomationGraphToolbar(
          editor: editor,
          snapping: snapping,
          routing: routing,
          inspector: inspector,
          running: running,
          onAdd: _add,
          onFit: _fit,
          onFind: _findNode,
          onToggleSnapping: () => setState(() => snapping = !snapping),
          onRoutingChanged: (value) => setState(() => routing = value),
          onToggleInspector: _toggleInspector,
          onRun: widget.onRun == null ? null : _run,
        ),
        if (graph.resolution.diagnostics.isNotEmpty)
          Material(
            color: Theme.of(context).colorScheme.errorContainer,
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.warning_amber),
              title: Text(
                '${graph.resolution.diagnostics.length} graph issue(s)',
              ),
              subtitle: Text(
                graph.resolution.diagnostics.first.message,
                maxLines: 2,
              ),
              onTap: _showDiagnostics,
            ),
          ),
        if (widget.execution case final execution?)
          AutomationExecutionBar(execution: execution),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final showInspector = inspector && constraints.maxWidth >= 660;
              viewport = GraphSize(
                constraints.maxWidth - (showInspector ? 320 : 0),
                constraints.maxHeight,
              );
              return Row(
                children: [
                  Expanded(
                    child: NodeEditor(
                      controller: graph,
                      captureFragment: editor.captureFragment,
                      pasteFragment: editor.pasteFragment,
                      onFind: () => unawaited(_findNode()),
                      headerBuilder: showrunnerNodeHeader,
                      portLabelBuilder: showrunnerPortLabel,
                      executionSource: widget.execution,
                      onCreateNode: _pick,
                      onError: _error,
                      routing: routing,
                      snapToGrid: snapping,
                    ),
                  ),
                  if (showInspector)
                    SizedBox(
                      width: 320,
                      child: AutomationGraphInspector(
                        onRunNode: widget.onRunNode == null
                            ? null
                            : _runFromNode,
                        editor: editor,
                        onError: _error,
                        resourceOptionsLoader: widget.resourceOptionsLoader,
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  void _showDiagnostics() {
    final owner = editor;
    final issues = List.of(owner.graph.resolution.diagnostics);
    unawaited(
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Graph issues'),
          content: SizedBox(
            width: 600,
            height: 400,
            child: ListView(
              children: [
                for (final issue in issues)
                  ListTile(
                    title: Text(issue.message),
                    subtitle: Text(
                      '${issue.spaceId ?? ''} · ${issue.entityId}',
                    ),
                    onTap: () {
                      final sid = issue.spaceId;
                      if (mounted &&
                          identical(owner, editor) &&
                          sid != null &&
                          owner.graph.document.spaces.containsKey(sid)) {
                        owner.graph.setActiveSpace(sid);
                        owner.graph.select(
                          GraphSelection(nodes: {issue.entityId}),
                        );
                        _fit();
                      }
                      Navigator.of(context).pop();
                    },
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}
