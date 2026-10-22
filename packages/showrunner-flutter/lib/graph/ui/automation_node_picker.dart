import 'package:flutter/material.dart';
import 'package:sai_nodes_core/sai_nodes_core.dart';
import '../controller/automation_editor_controller.dart';
import '../domain/automation_document.dart';

class AutomationNodePicker extends StatefulWidget {
  const AutomationNodePicker({super.key, required this.editor});
  final AutomationEditorController editor;
  @override
  State<AutomationNodePicker> createState() => _AutomationNodePickerState();
}

class _AutomationNodePickerState extends State<AutomationNodePicker> {
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
