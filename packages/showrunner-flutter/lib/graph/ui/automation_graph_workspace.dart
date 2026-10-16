import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sai_nodes/sai_nodes.dart'
    show
        NodeEditor,
        GraphNodePickerRequest,
        ConnectionRouting,
        GraphSceneBuilder;
import 'package:sai_nodes_core/sai_nodes_core.dart';

import '../../components/data_inputs/data_input.dart';
import '../../components/data_inputs/resource_schema.dart';
import '../controller/automation_editor_controller.dart';
import '../controller/automation_clipboard.dart';
import '../domain/automation_document.dart';
import '../definitions/showrunner_graph_types.dart';
import '../execution/showrunner_execution_visual_adapter.dart';
import 'graph_value_input.dart';
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
  ConnectionRouting routing = ConnectionRouting.bezier;
  GraphSize viewport = const GraphSize(800, 600);
  @override
  void initState() {
    super.initState();
    editor.addListener(_changed);
    widget.execution?.addListener(_changed);
  }

  @override
  void didUpdateWidget(AutomationGraphWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.editor != editor) {
      oldWidget.editor.removeListener(_changed);
      editor.addListener(_changed);
    }
    if (oldWidget.execution != widget.execution) {
      oldWidget.execution?.removeListener(_changed);
      widget.execution?.addListener(_changed);
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    editor.removeListener(_changed);
    widget.execution?.removeListener(_changed);
    super.dispose();
  }

  void _error(Object error) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  void fitGraph() => _fit();
  Future<void> _findNode() async {
    var query = '';
    final selected = await showDialog<(String, String)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, refresh) {
          final matches = [
            for (final space in editor.document.graph.spaces.values)
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
    if (!mounted || selected == null) return;
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
        builder: (context) => SizedBox(
          height: MediaQuery.sizeOf(context).height * .8,
          child: ListenableBuilder(
            listenable: changes,
            builder: (context, _) => _Inspector(
              editor: editor,
              onRunNode: widget.onRunNode == null ? null : _runFromNode,
              onError: _error,
              resourceOptionsLoader: widget.resourceOptionsLoader,
            ),
          ),
        ),
      );
    } finally {
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

  Future<GraphNode?> _pick(GraphNodePickerRequest request) =>
      showDialog<GraphNode>(
        context: context,
        builder: (context) => _NodePicker(editor: editor),
      );
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
    setState(() => running = true);
    try {
      await widget.onRun!(editor.document);
    } catch (error) {
      _error(error);
    } finally {
      if (mounted) setState(() => running = false);
    }
  }

  Future<void> _runFromNode(String nodeId) async {
    if (running || widget.onRunNode == null) return;
    setState(() => running = true);
    try {
      await widget.onRunNode!(nodeId);
    } catch (error) {
      _error(error);
    } finally {
      if (mounted) setState(() => running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final graph = editor.graph;
    return Column(
      children: [
        Material(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 4,
            children: [
              TextButton.icon(
                key: const ValueKey('graph-add-node'),
                onPressed: _add,
                icon: const Icon(Icons.add),
                label: const Text('Add node'),
              ),
              IconButton(
                tooltip: 'Undo',
                onPressed: graph.canUndo ? graph.undo : null,
                icon: const Icon(Icons.undo),
              ),
              IconButton(
                tooltip: 'Redo',
                onPressed: graph.canRedo ? graph.redo : null,
                icon: const Icon(Icons.redo),
              ),
              IconButton(
                tooltip: 'Fit graph',
                onPressed: _fit,
                icon: const Icon(Icons.fit_screen),
              ),
              IconButton(
                tooltip: 'Find in graph',
                onPressed: _findNode,
                icon: const Icon(Icons.search),
              ),
              IconButton(
                tooltip: 'Snap to grid',
                isSelected: snapping,
                onPressed: () => setState(() => snapping = !snapping),
                icon: const Icon(Icons.grid_4x4),
              ),
              DropdownButton<ConnectionRouting>(
                value: routing,
                underline: const SizedBox.shrink(),
                items: [
                  for (final value in ConnectionRouting.values)
                    DropdownMenuItem(value: value, child: Text(value.name)),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => routing = value);
                },
              ),
              DropdownButton<String>(
                key: const ValueKey('graph-space'),
                value: graph.activeSpaceId,
                underline: const SizedBox.shrink(),
                items: [
                  const DropdownMenuItem(
                    value: mainAutomationSpace,
                    child: Text('Main graph'),
                  ),
                  for (final signature in editor.document.subgraphs.values)
                    DropdownMenuItem(
                      value: signature.spaceId,
                      child: Text(signature.name),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) graph.setActiveSpace(value);
                },
              ),
              IconButton(
                tooltip: 'New subgraph',
                onPressed: () => editor.createSubgraph(),
                icon: const Icon(Icons.account_tree_outlined),
              ),
              IconButton(
                tooltip: 'Inspector',
                isSelected: inspector,
                onPressed: _toggleInspector,
                icon: const Icon(Icons.tune),
              ),
              TextButton.icon(
                onPressed:
                    widget.onRun != null &&
                        !running &&
                        graph.resolution.diagnostics.isEmpty
                    ? _run
                    : null,
                icon: Icon(running ? Icons.hourglass_empty : Icons.play_arrow),
                label: const Text('Run'),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(editor.isDirty ? 'Unsaved changes' : 'Saved'),
              ),
              if (graph.resolution.diagnostics.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text(
                    'Graph healthy',
                    style: TextStyle(color: Color(0xff69c8a3)),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  '${graph.activeSpace?.nodes.length ?? 0} nodes · ${graph.activeSpace?.connections.length ?? 0} connections',
                ),
              ),
            ],
          ),
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
        if (widget.execution != null && widget.execution!.runs.isNotEmpty)
          _executionBar(),
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
                      child: _Inspector(
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

  Widget _executionBar() {
    final execution = widget.execution!;
    final runs = execution.runs;
    final pinned = execution.pinnedExecutionId;
    return Row(
      children: [
        const SizedBox(width: 8),
        const Text('Execution: '),
        Expanded(
          child: DropdownButton<String>(
            isExpanded: true,
            value:
                pinned != null &&
                    runs.any((run) => run.info.executionId == pinned)
                ? pinned
                : '',
            items: [
              const DropdownMenuItem(
                value: '',
                child: Text('Live aggregate / latest run'),
              ),
              for (final run in runs)
                DropdownMenuItem(
                  value: run.info.executionId,
                  child: Text(
                    '${run.info.mode.name} · ${run.info.status.name} · ${run.info.startedAt.toLocal()}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (value) => execution.pin(value == '' ? null : value),
          ),
        ),
      ],
    );
  }

  void _showDiagnostics() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Graph issues'),
      content: SizedBox(
        width: 600,
        height: 400,
        child: ListView(
          children: [
            for (final issue in editor.graph.resolution.diagnostics)
              ListTile(
                title: Text(issue.message),
                subtitle: Text('${issue.spaceId ?? ''} · ${issue.entityId}'),
                onTap: () {
                  final sid = issue.spaceId;
                  if (sid != null &&
                      editor.graph.document.spaces.containsKey(sid)) {
                    editor.graph.setActiveSpace(sid);
                    editor.graph.select(
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
  );
}

class _NodePicker extends StatefulWidget {
  const _NodePicker({required this.editor});
  final AutomationEditorController editor;
  @override
  State<_NodePicker> createState() => _NodePickerState();
}

class _NodePickerState extends State<_NodePicker> {
  String search = '';
  @override
  Widget build(BuildContext context) {
    final editor = widget.editor;
    final choices =
        <({String type, String label, String category, GraphJson data})>[
              for (final definition
                  in editor.definitions.definitions.definitions.values)
                if (!{
                  'showrunner.parameter',
                  'showrunner.subgraphCall',
                }.contains(definition.type))
                  (
                    type: definition.type,
                    label: _definitionLabel(editor, definition),
                    category:
                        definition
                            .style(
                              NodeVisualContext(
                                document: editor.graph.document,
                                space: editor.graph.activeSpace!,
                                node: GraphNode(
                                  id: 'palette',
                                  type: definition.type,
                                  data: editor.definitions.defaultData(
                                    definition.type,
                                  ),
                                ),
                              ),
                            )
                            .category ??
                        '',
                    data: editor.definitions.defaultData(definition.type),
                  ),
              for (final signature in editor.document.subgraphs.values)
                (
                  type: 'showrunner.subgraphCall',
                  label: 'Call ${signature.name}',
                  category: 'Subgraphs',
                  data: {'subgraphId': signature.id, 'arguments': {}},
                ),
              for (final parameter
                  in editor.activeSubgraph?.parameters ??
                      <AutomationParameter>[])
                (
                  type: 'showrunner.parameter',
                  label: 'Parameter: ${parameter.name}',
                  category: 'Parameters',
                  data: {'parameterId': parameter.id},
                ),
            ]
            .where(
              (choice) => '${choice.label} ${choice.category} ${choice.type}'
                  .toLowerCase()
                  .contains(search.toLowerCase()),
            )
            .toList();
    return AlertDialog(
      title: const Text('Add node'),
      content: SizedBox(
        width: 520,
        height: 440,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Search nodes'),
              onChanged: (value) => setState(() => search = value),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: choices.length,
                itemBuilder: (context, index) {
                  final choice = choices[index];
                  return ListTile(
                    title: Text(choice.label),
                    subtitle: Text(choice.category),
                    onTap: () => Navigator.of(context).pop(
                      GraphNode(
                        id: newGraphId(),
                        type: choice.type,
                        data: choice.data,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _Inspector extends StatelessWidget {
  const _Inspector({
    required this.editor,
    required this.onError,
    this.resourceOptionsLoader,
    this.onRunNode,
  });
  final AutomationEditorController editor;
  final ValueChanged<Object> onError;
  final ResourceOptionsLoader? resourceOptionsLoader;
  final Future<void> Function(String nodeId)? onRunNode;
  @override
  Widget build(BuildContext context) {
    final graph = editor.graph;
    final nodeId = graph.selection.nodes.firstOrNull;
    final node = graph.activeSpace?.nodes[nodeId];
    final structure = graph.resolution.structures[graph.activeSpaceId]?[nodeId];
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (node == null) ...[
            const Text('Select a node to edit its fields.'),
            if (editor.activeSubgraph == null) ...[
              const SizedBox(height: 16),
              GraphValueInput(
                field: ResolvedField(
                  id: 'name',
                  label: 'Automation name',
                  kind: GraphFieldKind.string,
                ),
                value: editor.document.metadata['name'],
                onChanged: (value) => editor.updateMetadata({
                  ...editor.document.metadata,
                  'name': value,
                }),
              ),
              const SizedBox(height: 12),
              GraphValueInput(
                field: ResolvedField(
                  id: 'queue',
                  label: 'Queue ID (optional)',
                  kind: GraphFieldKind.string,
                ),
                value: editor.document.settings['queue'],
                onChanged: (value) => editor.updateSettings({
                  ...editor.document.settings,
                  'queue': value,
                }),
              ),
            ],
            if (editor.activeSubgraph case final signature?) ...[
              const SizedBox(height: 16),
              GraphValueInput(
                key: ValueKey('${signature.id}/name'),
                field: ResolvedField(
                  id: 'name',
                  label: 'Subgraph name',
                  kind: GraphFieldKind.string,
                ),
                value: signature.name,
                onChanged: (value) => editor.updateSubgraph(
                  signature.copyWith(name: value as String),
                ),
              ),
              const SizedBox(height: 12),
              for (final output in [false, true]) ...[
                Text(output ? 'Outputs' : 'Parameters'),
                for (final parameter
                    in output ? signature.outputs : signature.parameters)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    onTap: () => _addParameter(
                      context,
                      signature,
                      output,
                      original: parameter,
                    ),
                    title: Text(parameter.name),
                    subtitle: Text(parameter.type),
                    trailing: IconButton(
                      tooltip: 'Remove ${parameter.name}',
                      icon: const Icon(Icons.close),
                      onPressed: () =>
                          _removeParameter(signature, parameter.id, output),
                    ),
                  ),
                TextButton.icon(
                  onPressed: () => _addParameter(context, signature, output),
                  icon: const Icon(Icons.add),
                  label: Text(output ? 'Add output' : 'Add parameter'),
                ),
              ],
              TextButton.icon(
                onPressed: () => editor.deleteSubgraph(signature.id),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete subgraph'),
              ),
            ],
          ] else ...[
            Text(
              editor.definitions.definitions[node.type]?.label(
                    NodeDefinitionContext(
                      document: graph.document,
                      space: graph.activeSpace!,
                      node: node,
                    ),
                  ) ??
                  node.type,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            SelectableText(
              node.id,
              style: Theme.of(context).textTheme.labelSmall,
            ),
            const SizedBox(height: 12),
            GraphValueInput(
              key: ValueKey('${node.id}/title'),
              field: ResolvedField(
                id: 'title',
                label: 'Title',
                kind: GraphFieldKind.string,
              ),
              value: graph.activeSpace!.nodePresentations[node.id]?.title,
              onChanged: (value) => graph.execute(
                SetNodeTitleCommand(
                  graph.activeSpaceId!,
                  node.id,
                  value as String,
                ),
                label: 'Rename node',
                coalesceKey: (node.id, 'title'),
              ),
            ),
            TextButton(
              onPressed: () {
                try {
                  editor.setEntry(node.id);
                } catch (error) {
                  onError(error);
                }
              },
              child: const Text('Set as entry node'),
            ),
            if (onRunNode != null)
              TextButton.icon(
                onPressed: () => onRunNode!(node.id),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Run from this node'),
              ),
            for (final field in structure?.fields ?? <ResolvedField>[])
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: _field(node, field),
              ),
            if (structure == null)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'Definition unavailable. Node data and connections are preserved.',
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _field(GraphNode node, ResolvedField field) {
    Object? value = node.data;
    for (final key in field.dataPath) {
      value = value is Map ? value[key] : null;
    }
    final schema = editor.definitions.schemaForField(node.type, field);
    void changed(Object? value) => editor.updateField(node.id, field, value);
    return schema != null
        ? _SchemaInput(
            key: ValueKey('${node.id}/${field.id}'),
            schema: schema,
            value: value,
            onChanged: changed,
            loader: resourceOptionsLoader,
          )
        : GraphValueInput(
            key: ValueKey('${node.id}/${field.id}'),
            field: field,
            value: value,
            onChanged: changed,
          );
  }

  void _removeParameter(AutomationSubgraph signature, String id, bool output) =>
      editor.updateSubgraph(
        signature.copyWith(
          parameters: output
              ? signature.parameters
              : signature.parameters.where((parameter) => parameter.id != id),
          outputs: output
              ? signature.outputs.where((parameter) => parameter.id != id)
              : signature.outputs,
        ),
      );
  Future<void> _addParameter(
    BuildContext context,
    AutomationSubgraph signature,
    bool output, {
    AutomationParameter? original,
  }) async {
    final parameter = await showDialog<AutomationParameter>(
      context: context,
      builder: (context) => _ParameterDialog(
        original: original,
        existingNames: {
          for (final port in output ? signature.outputs : signature.parameters)
            if (port.id != original?.id) port.name,
        },
      ),
    );
    if (parameter == null) return;
    try {
      editor.updateSubgraph(
        signature.copyWith(
          parameters: output
              ? signature.parameters
              : [
                  ...signature.parameters.where(
                    (port) => port.id != parameter.id,
                  ),
                  parameter,
                ],
          outputs: output
              ? [
                  ...signature.outputs.where((port) => port.id != parameter.id),
                  parameter,
                ]
              : signature.outputs,
        ),
      );
    } catch (error) {
      onError(error);
    }
  }
}

class _SchemaInput extends StatefulWidget {
  const _SchemaInput({
    super.key,
    required this.schema,
    required this.value,
    required this.onChanged,
    this.loader,
  });
  final DartDataInputSchema schema;
  final Object? value;
  final ValueChanged<Object?> onChanged;
  final ResourceOptionsLoader? loader;
  @override
  State<_SchemaInput> createState() => _SchemaInputState();
}

class _SchemaInputState extends State<_SchemaInput> {
  late Future<DartDataInputSchema> schema = _load();
  Future<DartDataInputSchema> _load() => widget.loader == null
      ? Future.value(widget.schema)
      : hydrateResourceSchema(widget.schema, widget.loader!);
  @override
  void didUpdateWidget(_SchemaInput old) {
    super.didUpdateWidget(old);
    if (old.schema != widget.schema || old.loader != widget.loader) {
      schema = _load();
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<DartDataInputSchema>(
    future: schema,
    builder: (context, snapshot) => snapshot.hasError
        ? Text('Unable to load ${widget.schema.label}: ${snapshot.error}')
        : snapshot.hasData
        ? DartDataInput(
            schema: snapshot.data!,
            value: widget.value,
            onChanged: widget.onChanged,
          )
        : const LinearProgressIndicator(),
  );
}

class _ParameterDialog extends StatefulWidget {
  const _ParameterDialog({this.original, required this.existingNames});
  final AutomationParameter? original;
  final Set<String> existingNames;
  @override
  State<_ParameterDialog> createState() => _ParameterDialogState();
}

class _ParameterDialogState extends State<_ParameterDialog> {
  late String name = widget.original?.name ?? '';
  late String type = widget.original?.type ?? 'core.any';
  late Object? defaultValue = widget.original?.defaultValue;
  bool validDefault = true;
  @override
  Widget build(BuildContext context) {
    final duplicate = widget.existingNames.contains(name);
    final types = createShowrunnerGraphTypes().types;
    return AlertDialog(
      title: Text(widget.original == null ? 'Add parameter' : 'Edit parameter'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              initialValue: name,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Name',
                errorText: duplicate ? 'This name is already used' : null,
              ),
              onChanged: (value) => setState(() => name = value.trim()),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: types.containsKey(type) ? type : null,
              decoration: const InputDecoration(labelText: 'Type'),
              items: [
                for (final entry in types.entries)
                  DropdownMenuItem(
                    value: entry.key,
                    child: Text(entry.value.label),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => type = value);
              },
            ),
            const SizedBox(height: 12),
            GraphValueInput(
              field: ResolvedField(
                id: 'default',
                label: 'Default value (JSON)',
                kind: GraphFieldKind.json,
              ),
              value: defaultValue,
              onChanged: (value) => defaultValue = value,
              onValidityChanged: (valid) =>
                  setState(() => validDefault = valid),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: name.isEmpty || duplicate || !validDefault
              ? null
              : () => Navigator.of(context).pop(
                  AutomationParameter(
                    id: widget.original?.id ?? newGraphId(),
                    name: name,
                    type: type,
                    defaultValue: defaultValue,
                  ),
                ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

String _definitionLabel(
  AutomationEditorController editor,
  NodeDefinition definition,
) => definition.label(
  NodeDefinitionContext(
    document: editor.graph.document,
    space: editor.graph.activeSpace!,
    node: GraphNode(
      id: 'palette',
      type: definition.type,
      data: editor.definitions.defaultData(definition.type),
    ),
  ),
);
