import 'package:flutter/material.dart';
import 'package:sai_nodes_core/sai_nodes_core.dart';
import 'shader_graph_controller.dart';
import 'shader_graph_model.dart';

class ShaderGraphToolbar extends StatelessWidget {
  const ShaderGraphToolbar({
    super.key,
    required this.editor,
    required this.starter,
    required this.canCompile,
    required this.snapping,
    required this.onStarter,
    required this.onAdd,
    required this.onReset,
    required this.onFit,
    required this.onFind,
    required this.onAutoLayout,
    required this.onFrame,
    required this.onPalette,
    required this.onInspector,
    required this.onGlsl,
    required this.onPreview,
    required this.onCompile,
    required this.onCancel,
    required this.onSnap,
  });
  final ShaderEditorController editor;
  final String? starter;
  final bool canCompile, snapping;
  final ValueChanged<String> onStarter;
  final VoidCallback onAdd,
      onReset,
      onFit,
      onFind,
      onAutoLayout,
      onFrame,
      onPalette,
      onInspector,
      onGlsl,
      onPreview,
      onCompile,
      onCancel,
      onSnap;
  @override
  Widget build(BuildContext context) => Material(
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
          onPressed: onAdd,
          icon: const Icon(Icons.add),
        ),
        DropdownButton<String>(
          value: starter,
          hint: const Text('Starter graph'),
          items: [
            for (final item in shaderGraphStarters)
              DropdownMenuItem(value: item.id, child: Text(item.name)),
          ],
          onChanged: (id) {
            if (id != null) {
              onStarter(id);
            }
          },
        ),
        IconButton(
          tooltip: 'Reset graph',
          icon: const Icon(Icons.restart_alt),
          onPressed: onReset,
        ),
        IconButton(
          tooltip: 'Undo',
          icon: const Icon(Icons.undo),
          onPressed: editor.graph.canUndo ? editor.graph.undo : null,
        ),
        IconButton(
          tooltip: 'Redo',
          icon: const Icon(Icons.redo),
          onPressed: editor.graph.canRedo ? editor.graph.redo : null,
        ),
        IconButton(
          tooltip: 'Fit graph',
          icon: const Icon(Icons.fit_screen),
          onPressed: onFit,
        ),
        IconButton(
          tooltip: 'Find in graph',
          onPressed: onFind,
          icon: const Icon(Icons.search),
        ),
        IconButton(
          tooltip: 'Snap to grid',
          isSelected: snapping,
          onPressed: onSnap,
          icon: const Icon(Icons.grid_4x4),
        ),
        IconButton(
          tooltip: 'Auto layout',
          icon: const Icon(Icons.auto_fix_high),
          onPressed: onAutoLayout,
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
          onPressed: editor.graph.selection.nodes.isEmpty ? null : onFrame,
        ),
        IconButton(
          tooltip: 'Toggle node palette',
          icon: const Icon(Icons.add_box_outlined),
          onPressed: () => onPalette(),
        ),
        IconButton(
          tooltip: 'Inspector',
          icon: const Icon(Icons.tune),
          onPressed: onInspector,
        ),
        IconButton(
          tooltip: 'Show GLSL',
          icon: const Icon(Icons.code),
          onPressed: () => onGlsl(),
        ),
        IconButton(
          tooltip: 'Preview selected node',
          icon: const Icon(Icons.visibility_outlined),
          onPressed: editor.graph.selection.nodes.length == 1
              ? onPreview
              : null,
        ),
        FilledButton.icon(
          onPressed: canCompile ? onCompile : null,
          icon: const Icon(Icons.check),
          label: const Text('Compile & apply'),
        ),
        TextButton(onPressed: onCancel, child: const Text('Cancel')),
      ],
    ),
  );
}
