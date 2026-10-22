import 'shader_graph_toolbar.dart';
import 'shader_find_dialog.dart';
import 'shader_graph_inspector.dart';
import 'shader_compile_panel.dart';
import 'shader_node_palette.dart';
import 'package:flutter/material.dart';
import 'package:sai_nodes_core/sai_nodes_core.dart';
import 'package:sai_nodes/sai_nodes.dart'
    show NodeEditor, GraphSceneBuilder, GraphNodePickerRequest;

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
  String? starter;
  int resultRevision = -1;
  Object _documentLease = Object();
  bool snapping = false;
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

  Future<void> _find() async {
    final lease = _documentLease;
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => ShaderFindDialog(document: editor.document),
    );
    if (!mounted ||
        selected == null ||
        !identical(lease, _documentLease) ||
        !editor.document.space.nodes.containsKey(selected)) {
      return;
    }
    editor.graph.select(GraphSelection(nodes: {selected}));
    final scene = GraphSceneBuilder().build(editor.graph);
    editor.graph.focusNodes(
      {selected},
      {
        for (final node in scene.nodes.values)
          node.node.id: node.geometry.bounds,
      },
      viewport,
    );
  }

  void _fit() {
    final scene = GraphSceneBuilder().build(editor.graph);
    editor.graph.fitSpace({
      for (final item in scene.nodes.values) item.node.id: item.geometry.bounds,
    }, viewport);
  }

  void _load(ShaderDocument document) {
    _documentLease = Object();
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

  Future<GraphNode?> _pick(GraphNodePickerRequest request) async {
    final lease = _documentLease;
    var query = '';
    final node = await showDialog<GraphNode>(
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
    return mounted && identical(lease, _documentLease) ? node : null;
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

  void _error(Object error) => ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text(
        'Shader action could not be completed. Check the graph and retry.',
      ),
    ),
  );
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
                  child: const Text(
                    'The shader document is unsupported or malformed. Its saved data has not been changed.',
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ],
            )
          : Column(
              children: [
                ShaderGraphToolbar(
                  editor: editor,
                  starter: starter,
                  canCompile: invalidFields.isEmpty,
                  snapping: snapping,
                  onSnap: () => setState(() => snapping = !snapping),
                  onStarter: (id) {
                    starter = id;
                    _load(createShaderGraphStarter(id));
                  },
                  onAdd: _addFromPicker,
                  onReset: () {
                    starter = null;
                    _load(initial);
                  },
                  onFit: _fit,
                  onFind: _find,
                  onAutoLayout: _autoLayout,
                  onFrame: _frame,
                  onPalette: () => setState(() => showPalette = !showPalette),
                  onInspector: _toggleInspector,
                  onGlsl: () => setState(() => showGlsl = !showGlsl),
                  onPreview: () => _compile(preview: true),
                  onCompile: _compile,
                  onCancel: () => Navigator.pop(context),
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
                          SizedBox(
                            key: const ValueKey('shader-node-palette'),
                            width: palette ? 210 : 0,
                            child: Offstage(
                              offstage: !palette,
                              child: ShaderNodePalette(onAdd: _add),
                            ),
                          ),
                          Expanded(
                            child: NodeEditor(
                              controller: editor.graph,
                              headerBuilder: showrunnerNodeHeader,
                              portLabelBuilder: showrunnerPortLabel,
                              onCreateNode: _pick,
                              snapToGrid: snapping,
                              onFind: _find,
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
  Widget _inspector() => ShaderGraphInspector(
    key: ObjectKey(_documentLease),
    editor: editor,
    onValidityChanged: (node, field, valid) => setState(() {
      if (valid) {
        invalidFields.remove((node, field));
      } else {
        invalidFields.add((node, field));
      }
    }),
  );

  Widget _compilePanel() => ShaderCompilePanel(
    result: result!,
    showGlsl: showGlsl,
    onApply:
        result!.isValid && compiledDocument != null && invalidFields.isEmpty
        ? () {
            if (resultRevision != editor.graph.semanticRevision ||
                invalidFields.isNotEmpty) {
              return;
            }
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
          }
        : null,
  );
}
