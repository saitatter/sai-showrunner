import 'package:flutter/material.dart';
import 'package:sai_nodes_core/sai_nodes_core.dart';
import 'package:sai_nodes/sai_nodes.dart'
    show NodeEditor, GraphSceneBuilder, GraphNodePickerRequest;

import '../../../graph/ui/graph_value_input.dart';
import '../../../graph/ui/showrunner_node_widgets.dart';
import 'shader_graph_compiler.dart';
import 'shader_graph_controller.dart';
import 'shader_graph_model.dart';
import 'shader_node_definitions.dart';

final class ShaderGraphEditorResult {
  const ShaderGraphEditorResult({
    required this.graph,
    required this.glsl,
    required this.uniforms,
    required this.bindings,
  });
  final ShaderDocument graph;
  final String glsl;
  final Map<String, dynamic> uniforms, bindings;
}

/// Product controls around the same immutable canvas used by automations.
class ShaderGraphEditorDialog extends StatefulWidget {
  const ShaderGraphEditorDialog({super.key, required this.config});
  final Map<String, dynamic> config;
  @override
  State<ShaderGraphEditorDialog> createState() =>
      _ShaderGraphEditorDialogState();
}

class _ShaderGraphEditorDialogState extends State<ShaderGraphEditorDialog> {
  late final ShaderEditorController editor;
  late final ShaderDocument initial;
  Object? loadError;
  ShaderGraphCompileResult? result;
  ShaderDocument? compiledDocument;
  bool showPalette = true, showInspector = true, showGlsl = false;
  String search = '';
  String? starter;
  int resultRevision = -1;
  GraphSize viewport = const GraphSize(800, 600);
  final invalidFields = <(String, String)>{};
  @override
  void initState() {
    super.initState();
    try {
      final raw = widget.config['shaderGraph'];
      initial = raw == null
          ? createDefaultShaderDocument()
          : ShaderDocument.fromJson(raw as Map);
    } catch (error) {
      loadError = error;
      initial = createShaderDocument();
    }
    editor = ShaderEditorController(initial);
    editor.graph.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fit();
    });
  }

  void _changed() {
    if (!mounted) return;
    if (resultRevision != editor.graph.semanticRevision) {
      result = null;
      compiledDocument = null;
    }
    invalidFields.removeWhere(
      (key) => !editor.document.space.nodes.containsKey(key.$1),
    );
    setState(() {});
  }

  @override
  void dispose() {
    editor.graph.removeListener(_changed);
    editor.dispose();
    super.dispose();
  }

  void _fit() {
    final scene = GraphSceneBuilder().build(editor.graph);
    editor.graph.fitSpace({
      for (final item in scene.nodes.values) item.node.id: item.geometry.bounds,
    }, viewport);
  }

  void _load(ShaderDocument document) {
    invalidFields.clear();
    result = null;
    compiledDocument = null;
    editor.load(document);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fit();
    });
  }

  void _add(ShaderNodeDefinition definition) {
    final id = newGraphId();
    final position = editor.graph.camera.viewportToWorld(
      GraphPoint(viewport.width / 2, viewport.height / 2),
    );
    editor.graph.execute(
      AddNodeCommand(
        shaderSpaceId,
        createShaderNode(id, definition.id),
        presentation: NodePresentation(nodeId: id, position: position),
      ),
      label: 'Add ${definition.name}',
    );
    editor.graph.select(GraphSelection(nodes: {id}));
  }

  Future<GraphNode?> _pick(GraphNodePickerRequest request) {
    var query = '';
    return showDialog<GraphNode>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: const Text('Add shader node'),
          content: SizedBox(
            width: 380,
            height: 440,
            child: Column(
              children: [
                TextField(
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Search shader nodes',
                  ),
                  onChanged: (value) => refresh(() => query = value),
                ),
                Expanded(
                  child: ListView(
                    children: [
                      for (final definition in shaderNodeDefinitions.where(
                        (item) => '${item.name} ${item.category} ${item.id}'
                            .toLowerCase()
                            .contains(query.toLowerCase()),
                      ))
                        ListTile(
                          title: Text(definition.name),
                          subtitle: Text(definition.category),
                          onTap: () => Navigator.pop(
                            context,
                            createShaderNode(newGraphId(), definition.id),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addFromPicker() async {
    final position = editor.graph.camera.viewportToWorld(
      GraphPoint(viewport.width / 2, viewport.height / 2),
    );
    final node = await _pick(GraphNodePickerRequest(position: position));
    if (!mounted || node == null) return;
    editor.graph.execute(
      AddNodeCommand(
        shaderSpaceId,
        node,
        presentation: NodePresentation(nodeId: node.id, position: position),
      ),
      label: 'Add shader node',
    );
    editor.graph.select(GraphSelection(nodes: {node.id}));
  }

  Future<void> _toggleInspector() async {
    final width =
        (context.findRenderObject() as RenderBox?)?.size.width ?? 1000;
    if (width >= 692) {
      setState(() => showInspector = !showInspector);
      return;
    }
    final changes = ValueNotifier(0);
    void changed() => changes.value++;
    editor.graph.addListener(changed);
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (context) => SizedBox(
          height: MediaQuery.sizeOf(context).height * .8,
          child: ListenableBuilder(
            listenable: changes,
            builder: (context, _) => _inspector(),
          ),
        ),
      );
    } finally {
      editor.graph.removeListener(changed);
      changes.dispose();
    }
  }

  void _compile({bool preview = false}) {
    var document = editor.document;
    if (preview) {
      final selected = editor.graph.selection.nodes.singleOrNull;
      final candidate = selected == null
          ? null
          : createShaderNodePreviewGraph(document, selected);
      if (candidate == null) return;
      document = candidate;
    }
    setState(() {
      result = preview ? compileShaderGraph(document) : editor.compile();
      compiledDocument = preview ? null : document;
      resultRevision = editor.graph.semanticRevision;
    });
  }

  void _frame() {
    final scene = GraphSceneBuilder().build(editor.graph);
    final members = editor.graph.selection.nodes;
    final bounds = members
        .map((id) => scene.nodes[id]?.geometry.bounds)
        .whereType<GraphRect>();
    if (bounds.isEmpty) return;
    final frame = GraphFrame(
      id: newGraphId(),
      title: 'Frame',
      bounds: bounds.reduce((a, b) => a.union(b)).inflate(28),
      memberNodeIds: members,
      metadata: {'color': '#7c4dff'},
    );
    editor.graph.execute(
      CreateFrameCommand(shaderSpaceId, frame),
      label: 'Frame selection',
    );
  }

  void _autoLayout() {
    editor.graph.execute(
      MoveNodesCommand(shaderSpaceId, {
        for (final (index, node) in editor.document.nodes.indexed)
          node.id: GraphPoint(50 + (index % 4) * 340, 50 + (index ~/ 4) * 400),
      }),
      label: 'Auto layout',
    );
    _fit();
  }

  void _error(Object error) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text('$error')));
  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(16),
    child: SizedBox(
      width: 1500,
      height: 950,
      child: loadError != null
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(
                  title: Text('Shader document could not be opened'),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText('$loadError'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ],
            )
          : Column(
              children: [
                Material(
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text(
                          'Shader Graph',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Add shader node',
                        onPressed: _addFromPicker,
                        icon: const Icon(Icons.add),
                      ),
                      DropdownButton<String>(
                        value: starter,
                        hint: const Text('Starter graph'),
                        items: [
                          for (final item in shaderGraphStarters)
                            DropdownMenuItem(
                              value: item.id,
                              child: Text(item.name),
                            ),
                        ],
                        onChanged: (id) {
                          if (id != null) {
                            starter = id;
                            _load(createShaderGraphStarter(id));
                          }
                        },
                      ),
                      IconButton(
                        tooltip: 'Reset graph',
                        icon: const Icon(Icons.restart_alt),
                        onPressed: () {
                          starter = null;
                          _load(initial);
                        },
                      ),
                      IconButton(
                        tooltip: 'Undo',
                        icon: const Icon(Icons.undo),
                        onPressed: editor.graph.canUndo
                            ? editor.graph.undo
                            : null,
                      ),
                      IconButton(
                        tooltip: 'Redo',
                        icon: const Icon(Icons.redo),
                        onPressed: editor.graph.canRedo
                            ? editor.graph.redo
                            : null,
                      ),
                      IconButton(
                        tooltip: 'Fit graph',
                        icon: const Icon(Icons.fit_screen),
                        onPressed: _fit,
                      ),
                      IconButton(
                        tooltip: 'Auto layout',
                        icon: const Icon(Icons.auto_fix_high),
                        onPressed: _autoLayout,
                      ),
                      IconButton(
                        tooltip: 'Delete selection',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: editor.graph.selection.isEmpty
                            ? null
                            : editor.graph.deleteSelection,
                      ),
                      IconButton(
                        tooltip: 'Add frame from selection',
                        icon: const Icon(Icons.crop_free),
                        onPressed: editor.graph.selection.nodes.isEmpty
                            ? null
                            : _frame,
                      ),
                      IconButton(
                        tooltip: 'Toggle node palette',
                        icon: const Icon(Icons.add_box_outlined),
                        onPressed: () =>
                            setState(() => showPalette = !showPalette),
                      ),
                      IconButton(
                        tooltip: 'Inspector',
                        icon: const Icon(Icons.tune),
                        onPressed: _toggleInspector,
                      ),
                      IconButton(
                        tooltip: 'Show GLSL',
                        icon: const Icon(Icons.code),
                        onPressed: () => setState(() => showGlsl = !showGlsl),
                      ),
                      IconButton(
                        tooltip: 'Preview selected node',
                        icon: const Icon(Icons.visibility_outlined),
                        onPressed: editor.graph.selection.nodes.length == 1
                            ? () => _compile(preview: true)
                            : null,
                      ),
                      FilledButton.icon(
                        onPressed: invalidFields.isEmpty ? _compile : null,
                        icon: const Icon(Icons.check),
                        label: const Text('Compile & apply'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final palette =
                          showPalette && constraints.maxWidth >= 850;
                      final inspector =
                          showInspector && constraints.maxWidth >= 660;
                      viewport = GraphSize(
                        constraints.maxWidth -
                            (palette ? 210 : 0) -
                            (inspector ? 280 : 0),
                        constraints.maxHeight,
                      );
                      return Row(
                        children: [
                          if (palette)
                            SizedBox(
                              width: 210,
                              child: Column(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: TextField(
                                      decoration: const InputDecoration(
                                        labelText: 'Search shader nodes',
                                      ),
                                      onChanged: (value) =>
                                          setState(() => search = value),
                                    ),
                                  ),
                                  Expanded(
                                    child: ListView(
                                      children: [
                                        for (final category
                                            in shaderNodeCategories)
                                          ExpansionTile(
                                            initiallyExpanded: true,
                                            title: Text(category),
                                            children: [
                                              for (final definition
                                                  in shaderNodeDefinitions.where(
                                                    (item) =>
                                                        item.category ==
                                                            category &&
                                                        '${item.name} ${item.id}'
                                                            .toLowerCase()
                                                            .contains(
                                                              search
                                                                  .toLowerCase(),
                                                            ),
                                                  ))
                                                ListTile(
                                                  dense: true,
                                                  title: Text(definition.name),
                                                  onTap: () => _add(definition),
                                                ),
                                            ],
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          Expanded(
                            child: NodeEditor(
                              controller: editor.graph,
                              headerBuilder: showrunnerNodeHeader,
                              portLabelBuilder: showrunnerPortLabel,
                              onCreateNode: _pick,
                              onError: _error,
                            ),
                          ),
                          if (inspector)
                            SizedBox(width: 280, child: _inspector()),
                        ],
                      );
                    },
                  ),
                ),
                if (result != null)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: _compilePanel(),
                  ),
              ],
            ),
    ),
  );
  Widget _inspector() {
    final document = editor.document;
    final node = editor.graph.selection.nodes.singleOrNull;
    final selected = document.space.nodes[node];
    final fields =
        editor.graph.resolution.structures[shaderSpaceId]?[node]?.fields ??
        <ResolvedField>[];
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Text('Output', style: TextStyle(fontWeight: FontWeight.bold)),
        DropdownButton<String>(
          isExpanded: true,
          value:
              document.space.nodes[document.outputNodeId]?.shaderDefinitionId ==
                  'fragment_output'
              ? document.outputNodeId
              : null,
          hint: const Text('Select fragment output'),
          items: [
            for (final output in document.nodes.where(
              (node) => node.shaderDefinitionId == 'fragment_output',
            ))
              DropdownMenuItem(
                value: output.id,
                child: Text(
                  document.space.nodePresentations[output.id]?.title ??
                      output.id,
                ),
              ),
          ],
          onChanged: editor.setOutput,
        ),
        Text('Nodes: ${document.nodes.length}'),
        Text('Connections: ${document.connections.length}'),
        if (selected != null) ...[
          const Divider(),
          Text(
            shaderNodeDefinitionById[selected.shaderDefinitionId]?.name ??
                selected.type,
          ),
          SelectableText(selected.id),
          for (final field in fields)
            GraphValueInput(
              key: ValueKey('${selected.id}/${field.id}'),
              field: field,
              value: selected.shaderValues.containsKey(field.id)
                  ? selected.shaderValues[field.id]
                  : field.metadata['defaultValue'],
              onChanged: (value) =>
                  editor.updateField(selected.id, field, value),
              onValidityChanged: (valid) => setState(() {
                if (valid) {
                  invalidFields.remove((selected.id, field.id));
                } else {
                  invalidFields.add((selected.id, field.id));
                }
              }),
            ),
        ],
        const Divider(),
        const Text('Frames', style: TextStyle(fontWeight: FontWeight.bold)),
        for (final frame in document.space.frames.values)
          ListTile(
            dense: true,
            title: Text(frame.title),
            subtitle: Text('${frame.memberNodeIds.length} nodes'),
            onTap: () =>
                editor.graph.select(GraphSelection(frames: {frame.id})),
            trailing: IconButton(
              tooltip: 'Delete frame',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => editor.graph.execute(
                RemoveFrameCommand(shaderSpaceId, frame.id),
                label: 'Delete frame',
              ),
            ),
          ),
        for (final issue in editor.graph.resolution.diagnostics)
          Text(
            issue.message,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    );
  }

  Widget _compilePanel() => ListView(
    shrinkWrap: true,
    padding: const EdgeInsets.all(12),
    children: [
      for (final error in result!.errors)
        Text(
          error,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      for (final warning in result!.warnings) Text(warning),
      if (result!.isValid) const Text('Shader compiled successfully.'),
      if (showGlsl) SelectableText(result!.glsl),
      if (result!.isValid && compiledDocument != null && invalidFields.isEmpty)
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: () {
              final document = compiledDocument!;
              Navigator.pop(
                context,
                ShaderGraphEditorResult(
                  graph: document,
                  glsl: result!.glsl,
                  uniforms: collectShaderUniformDefaults(document),
                  bindings: collectShaderUniformBindings(document),
                ),
              );
            },
            child: const Text('Apply'),
          ),
        ),
    ],
  );
}
