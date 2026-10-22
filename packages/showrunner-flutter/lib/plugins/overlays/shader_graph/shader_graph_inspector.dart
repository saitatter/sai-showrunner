import 'package:flutter/material.dart';
import 'package:sai_nodes_core/sai_nodes_core.dart';
import '../../../graph/ui/graph_value_input.dart';
import 'shader_graph_controller.dart';
import 'shader_graph_model.dart';
import 'shader_node_definitions.dart';

class ShaderGraphInspector extends StatelessWidget {
  const ShaderGraphInspector({
    super.key,
    required this.editor,
    required this.onValidityChanged,
  });
  final ShaderEditorController editor;
  final void Function(String nodeId, String fieldId, bool valid)
  onValidityChanged;
  @override
  Widget build(BuildContext context) {
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
              onValidityChanged: (valid) =>
                  onValidityChanged(selected.id, field.id, valid),
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
}
