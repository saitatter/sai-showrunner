import 'package:flutter/material.dart';
import 'shader_graph_model.dart';
import 'shader_node_definitions.dart';

class ShaderFindDialog extends StatefulWidget {
  const ShaderFindDialog({super.key, required this.document});
  final ShaderDocument document;
  @override
  State<ShaderFindDialog> createState() => _ShaderFindDialogState();
}

class _ShaderFindDialogState extends State<ShaderFindDialog> {
  String query = '';
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Find in shader graph'),
    content: SizedBox(
      width: 520,
      height: 420,
      child: Column(
        children: [
          TextField(
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Search graph nodes'),
            onChanged: (value) => setState(() => query = value),
          ),
          Expanded(
            child: ListView(
              children: [
                for (final node in widget.document.nodes)
                  if ('${node.id} ${node.shaderDefinitionId} ${widget.document.space.nodePresentations[node.id]?.title ?? ''}'
                      .toLowerCase()
                      .contains(query.toLowerCase()))
                    ListTile(
                      title: Text(
                        widget
                                .document
                                .space
                                .nodePresentations[node.id]
                                ?.title ??
                            shaderNodeDefinitionById[node.shaderDefinitionId]
                                ?.name ??
                            node.type,
                      ),
                      subtitle: Text(node.id),
                      onTap: () => Navigator.pop(context, node.id),
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
        child: const Text('Close'),
      ),
    ],
  );
}
