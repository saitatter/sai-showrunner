import 'dart:async';
import 'package:flutter/material.dart';

import 'package:showrunner_flutter/graph/controller/automation_editor_controller.dart';
import 'package:showrunner_flutter/graph/domain/automation_document.dart';
import 'package:showrunner_flutter/components/data_inputs/resource_schema.dart';
import 'package:showrunner_flutter/graph/ui/inline_automation_graph.dart';
import 'package:sai_nodes_core/sai_nodes_core.dart';

import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/schema/json.dart';
import 'package:showrunner_flutter/schema/stream_plan.dart';

class StreamPlanSegmentEditor extends StatefulWidget {
  const StreamPlanSegmentEditor({
    super.key,
    required this.index,
    required this.segment,
    this.registryFuture,
    this.resourceOptionsLoader,
    required this.onChanged,
    required this.onGraphDirty,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onDelete,
  });

  final int index;
  final StreamPlanSegmentData segment;
  final Future<DartPluginRegistry>? registryFuture;
  final ResourceOptionsLoader? resourceOptionsLoader;
  final ValueChanged<StreamPlanSegmentData> onChanged;
  final VoidCallback onGraphDirty;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback onDelete;

  @override
  State<StreamPlanSegmentEditor> createState() =>
      StreamPlanSegmentEditorState();
}

class StreamPlanSegmentEditorState extends State<StreamPlanSegmentEditor> {
  AutomationEditorController? _activationEditor;
  AutomationEditorController? _deactivationEditor;

  @override
  void initState() {
    super.initState();
    if (widget.registryFuture != null) {
      _activationEditor = AutomationEditorController(
        document: AutomationDocument.fromJson(
          widget.segment.activationAutomation,
        ),
      );
      _deactivationEditor = AutomationEditorController(
        document: AutomationDocument.fromJson(
          widget.segment.deactivationAutomation,
        ),
      );
      _activationEditor!.graph.addDocumentListener(_graphChanged);
      _deactivationEditor!.graph.addDocumentListener(_graphChanged);
    }
  }

  void _graphChanged(GraphDocumentChange change) => _syncAutomationChanges();

  @override
  void dispose() {
    _activationEditor?.graph.removeDocumentListener(_graphChanged);
    _deactivationEditor?.graph.removeDocumentListener(_graphChanged);
    _activationEditor?.dispose();
    _deactivationEditor?.dispose();
    super.dispose();
  }

  void _syncAutomationChanges() {
    widget.onChanged(snapshot());
    widget.onGraphDirty();
  }

  StreamPlanSegmentData snapshot() {
    final segment = widget.segment;
    return StreamPlanSegmentData(
      id: segment.id,
      name: segment.name,
      components: segment.components,
      activationAutomation:
          _activationEditor?.document.toJson() ?? segment.activationAutomation,
      deactivationAutomation:
          _deactivationEditor?.document.toJson() ??
          segment.deactivationAutomation,
    );
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Segment ${widget.index + 1}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                tooltip: 'Move up',
                onPressed: widget.onMoveUp,
                icon: const Icon(Icons.arrow_upward),
              ),
              IconButton(
                tooltip: 'Move down',
                onPressed: widget.onMoveDown,
                icon: const Icon(Icons.arrow_downward),
              ),
              IconButton(
                tooltip: 'Delete segment',
                onPressed: widget.onDelete,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          TextFormField(
            initialValue: widget.segment.name,
            decoration: const InputDecoration(labelText: 'Name'),
            onChanged: (name) => widget.onChanged(_copy(name: name)),
          ),
          const SizedBox(height: 8),
          if (_activationEditor != null)
            _inlineAutomation('On Activate', _activationEditor!),
          if (_deactivationEditor != null)
            _inlineAutomation('On Deactivate', _deactivationEditor!),
          if (_activationEditor == null)
            _automationSummary(
              'On Activate',
              widget.segment.activationAutomation,
            ),
          if (_deactivationEditor == null)
            _automationSummary(
              'On Deactivate',
              widget.segment.deactivationAutomation,
            ),
          const SizedBox(height: 8),
          _componentFields(),
        ],
      ),
    ),
  );

  Widget _componentFields() {
    final component = widget.segment.components['twitch-stream-info'];
    if (component is! Map) return const SizedBox.shrink();
    final config = Map<String, dynamic>.from(component);
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        _componentField(
          'Stream title',
          'title',
          config['title']?.toString() ?? '',
        ),
        _componentField(
          'Category',
          'category',
          config['category']?.toString() ?? '',
        ),
        _componentTagsField(
          config['tags'] is List
              ? (config['tags'] as List).map((tag) => tag.toString()).join(', ')
              : '',
        ),
      ],
    );
  }

  Widget _componentField(String label, String key, String value) => SizedBox(
    width: 260,
    child: TextFormField(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      onChanged: (next) {
        final components = {
          ...widget.segment.components,
          'twitch-stream-info': {
            ...Map<String, dynamic>.from(
              widget.segment.components['twitch-stream-info'] as Map,
            ),
            key: next,
          },
        };
        widget.onChanged(_copy(components: components));
      },
    ),
  );

  Widget _componentTagsField(String value) => SizedBox(
    width: 260,
    child: TextFormField(
      initialValue: value,
      decoration: const InputDecoration(labelText: 'Tags (comma separated)'),
      onChanged: (next) {
        final components = {
          ...widget.segment.components,
          'twitch-stream-info': {
            ...Map<String, dynamic>.from(
              widget.segment.components['twitch-stream-info'] as Map,
            ),
            'tags': next
                .split(',')
                .map((tag) => tag.trim())
                .where((tag) => tag.isNotEmpty)
                .toList(),
          },
        };
        widget.onChanged(_copy(components: components));
      },
    ),
  );

  StreamPlanSegmentData _copy({String? name, JsonMap? components}) =>
      StreamPlanSegmentData(
        id: widget.segment.id,
        name: name ?? widget.segment.name,
        components: components ?? widget.segment.components,
        activationAutomation: widget.segment.activationAutomation,
        deactivationAutomation: widget.segment.deactivationAutomation,
      );

  Widget _automationSummary(String label, JsonMap automation) {
    final graph = automation['graph'];
    final nodes = graph is Map && graph['nodes'] is List
        ? (graph['nodes'] as List).length
        : 0;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.account_tree_outlined),
      title: Text(label),
      subtitle: Text('$nodes automation node${nodes == 1 ? '' : 's'}'),
    );
  }

  Widget _inlineAutomation(String label, AutomationEditorController editor) =>
      ExpansionTile(
        key: ValueKey('stream-plan-segment-${widget.segment.id}-$label'),
        leading: const Icon(Icons.account_tree_outlined),
        title: Text(label),
        subtitle: Text('${editor.graph.activeSpace!.nodes.length} nodes'),
        children: [
          SizedBox(
            width: 720,
            child: InlineAutomationGraph(
              editor: editor,
              registryFuture: widget.registryFuture!,
              resourceOptionsLoader: widget.resourceOptionsLoader,
            ),
          ),
        ],
      );
}
