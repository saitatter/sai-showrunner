import 'package:flutter/material.dart';
import '../../persistence/document_revision.dart';
import 'package:sai_nodes_core/sai_nodes_core.dart';
import '../controller/automation_editor_controller.dart';
import '../domain/automation_document.dart';
import '../../components/data_inputs/resource_schema.dart';
import 'graph_value_input.dart';
import 'automation_graph_schema_input.dart';
import 'automation_parameter_dialog.dart';

class AutomationGraphInspector extends StatelessWidget {
  const AutomationGraphInspector({
    super.key,
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
        ? AutomationGraphSchemaInput(
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
      builder: (context) => AutomationParameterDialog(
        original: original,
        existingNames: {
          for (final port in output ? signature.outputs : signature.parameters)
            if (port.id != original?.id) port.name,
        },
      ),
    );
    if (parameter == null || !context.mounted) return;
    final current = editor.document.subgraphs[signature.id];
    if (current == null ||
        DocumentRevision.of(current.toJson()) !=
            DocumentRevision.of(signature.toJson())) {
      onError(StateError('Subgraph changed while editing its parameter.'));
      return;
    }
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
