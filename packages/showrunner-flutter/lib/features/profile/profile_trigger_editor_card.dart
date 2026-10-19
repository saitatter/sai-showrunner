import 'package:flutter/material.dart';
import 'package:sai_nodes_core/sai_nodes_core.dart';
import '../../components/data_inputs/data_input.dart';
import '../../components/data_inputs/resource_schema.dart';
import '../../graph/controller/automation_editor_controller.dart';
import '../../graph/definitions/showrunner_graph_types.dart';
import '../../graph/domain/automation_document.dart';
import '../../graph/ui/inline_automation_graph.dart';
import '../../plugins/registry/plugin_registry.dart';
import '../../schema/json.dart';

/// Profile event metadata around an automation with one canonical controller.
class ProfileTriggerEditorCard extends StatefulWidget {
  const ProfileTriggerEditorCard({
    super.key,
    required this.trigger,
    required this.registry,
    required this.registryFuture,
    required this.resourceOptionsLoader,
    required this.queueOptionsFuture,
    required this.dragHandle,
    required this.onChanged,
    required this.onValidityChanged,
    required this.onDelete,
  });
  final JsonMap trigger;
  final DartPluginRegistry registry;
  final Future<DartPluginRegistry> registryFuture;
  final ResourceOptionsLoader resourceOptionsLoader;
  final Future<List<String>> queueOptionsFuture;
  final Widget dragHandle;
  final ValueChanged<JsonMap> onChanged;
  final ValueChanged<bool> onValidityChanged;
  final VoidCallback onDelete;
  @override
  State<ProfileTriggerEditorCard> createState() =>
      _ProfileTriggerEditorCardState();
}

class _ProfileTriggerEditorCardState extends State<ProfileTriggerEditorCard> {
  late final AutomationEditorController editor;
  late final TextEditingController description;
  bool expanded = true;
  double height = 600;
  GraphNode? get event => editor
      .graph
      .document
      .spaces[mainAutomationSpace]!
      .nodes
      .values
      .where((node) => decodeContractNodeType(node.type, 'trigger') != null)
      .firstOrNull;
  @override
  void initState() {
    super.initState();
    editor = AutomationEditorController(
      document: AutomationDocument.fromJson(
        Map<String, Object?>.from(widget.trigger['automation'] as Map),
      ),
      registry: widget.registry,
    );
    description = TextEditingController(
      text: widget.trigger['description']?.toString() ?? '',
    )..addListener(_emit);
    final source = event;
    if (source != null) editor.graph.select(GraphSelection(nodes: {source.id}));
    editor.graph.addDocumentListener(_documentChanged);
  }

  void _documentChanged(GraphDocumentChange change) {
    _emit();
    if (mounted) setState(() {});
  }

  void _emit() {
    widget.onValidityChanged(event != null);
    widget.onChanged({
      'id': widget.trigger['id'],
      'description': description.text.trim(),
      'automation': editor.document.toJson(),
    });
  }

  @override
  void dispose() {
    description.removeListener(_emit);
    description.dispose();
    editor.graph.removeDocumentListener(_documentChanged);
    editor.dispose();
    super.dispose();
  }

  void _selectEvent(String? type) {
    if (type == null) return;
    final node = event;
    final contract = decodeContractNodeType(type, 'trigger')!;
    final definition = widget.registry.trigger(
      TriggerKey(
        plugin: PluginId(contract.$1),
        trigger: TriggerId(contract.$2),
      ),
    );
    final config = definition?.configSchema == null
        ? const <String, Object?>{}
        : constructDartDataInputDefault(definition!.configSchema!);
    if (node == null) {
      editor.addNode(type, const GraphPoint(40, 80));
    } else {
      editor.graph.execute(
        ReplaceNodeTypeCommand(
          mainAutomationSpace,
          node.id,
          type,
          data: {...node.data, 'config': config},
        ),
        label: 'Change event trigger',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final source = event;
    final choices = [
      for (final plugin in widget.registry.plugins) ...plugin.triggers,
    ];
    final known = choices.any(
      (trigger) =>
          triggerNodeType(trigger.pluginId.value, trigger.triggerId.value) ==
          source?.type,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                widget.dragHandle,
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: known ? source?.type : null,
                    key: ValueKey(source?.type),
                    decoration: const InputDecoration(labelText: 'Trigger'),
                    isExpanded: true,
                    items: [
                      for (final trigger in choices)
                        DropdownMenuItem(
                          value: triggerNodeType(
                            trigger.pluginId.value,
                            trigger.triggerId.value,
                          ),
                          child: Text(trigger.displayName),
                        ),
                    ],
                    onChanged: _selectEvent,
                  ),
                ),
                IconButton(
                  tooltip: expanded ? 'Collapse trigger' : 'Expand trigger',
                  onPressed: () => setState(() => expanded = !expanded),
                  icon: Icon(expanded ? Icons.expand_less : Icons.expand_more),
                ),
                IconButton(
                  tooltip: 'Delete trigger',
                  onPressed: widget.onDelete,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            if (expanded) ...[
              const SizedBox(height: 12),
              TextField(
                controller: description,
                decoration: const InputDecoration(labelText: 'Description'),
              ),
              const SizedBox(height: 12),
              FutureBuilder<List<String>>(
                future: widget.queueOptionsFuture,
                builder: (context, snapshot) {
                  final options = {
                    ...?snapshot.data,
                    if (editor.document.queueId != null)
                      editor.document.queueId!,
                  };
                  return DropdownButtonFormField<String>(
                    key: ValueKey(editor.document.queueId),
                    initialValue: editor.document.queueId ?? '',
                    decoration: const InputDecoration(labelText: 'Queue'),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('No queue'),
                      ),
                      for (final option in options)
                        DropdownMenuItem(value: option, child: Text(option)),
                    ],
                    onChanged: (value) => editor.updateSettings({
                      ...editor.document.settings,
                      'queue': value == '' ? null : value,
                    }),
                  );
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Stop propagation'),
                value: source?.data['stop'] == true,
                onChanged: source == null
                    ? null
                    : (value) => editor.graph.execute(
                        UpdateNodeDataCommand(mainAutomationSpace, source.id, {
                          ...source.data,
                          'stop': value,
                        }),
                        label: 'Set event propagation',
                      ),
              ),
              InlineAutomationGraph(
                editor: editor,
                registryFuture: widget.registryFuture,
                resourceOptionsLoader: widget.resourceOptionsLoader,
                height: height,
              ),
              Slider(
                value: height,
                min: 360,
                max: 900,
                onChanged: (value) => setState(() => height = value),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
