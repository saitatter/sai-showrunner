part of 'graph_workspace.dart';

/// The reference card groups its title and subtitle beside the icon, with no
/// separately colored header. Canvas effects belong to the entire card.
class _GraphNodeHeader extends StatelessWidget {
  const _GraphNodeHeader({
    required this.editor,
    required this.node,
    required this.onToggleCollapse,
    this.onRunNode,
  });
  final ShowRunnerGraphEditor editor;
  final NodeDataModel node;
  final VoidCallback onToggleCollapse;
  final Future<void> Function(String schemaNodeId)? onRunNode;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([editor.executionStates, editor.nodeRevision]),
    builder: (context, child) {
      final badge = editor.nodeBadge(node.id);
      final execution = editor.executionStates.value[node.id];
      final subtitle = editor.nodeSubtitle(node.id);
      final config = editor.nodeConfigLines(node.id);
      return Padding(
        key: ValueKey('graph-node-header-${node.id}'),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: const Color(0x1fffffff),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Icon(
                    editor.nodeIcon(node.id),
                    size: 20,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Tooltip(
                        message: editor.nodeTitle(node.id),
                        child: Text(
                          editor.nodeTitle(node.id),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (subtitle.isNotEmpty)
                        Tooltip(
                          message: subtitle,
                          child: Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xffd6d6d6),
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (editor.isTriggerNode(node.id) &&
                    onRunNode != null &&
                    editor.schemaNodeIdForEditor(node.id) != null)
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: IconButton(
                      tooltip: 'Run automation',
                      padding: EdgeInsets.zero,
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xff4caf50),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => unawaited(
                        onRunNode!(editor.schemaNodeIdForEditor(node.id)!),
                      ),
                      icon: const Icon(Icons.play_arrow, size: 16),
                    ),
                  ),
                if (badge != null && badge != 'Trigger')
                  Container(
                    margin: const EdgeInsets.only(left: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: badge == 'Missing'
                          ? const Color(0xffef5350)
                          : const Color(0xffe9aaff),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      badge,
                      style: TextStyle(
                        color: badge == 'Missing'
                            ? Colors.white
                            : const Color(0xff1b0f21),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
            if (execution != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _ExecutionBadge(execution: execution),
                ),
              ),
            if (config.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.only(top: 4),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Color(0x1affffff))),
                ),
                child: Column(
                  children: [
                    for (final line in config)
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              line.$1,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xffb0b0b0),
                                fontSize: 10.8,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              line.$2,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xffe9e9e9),
                                fontSize: 10.8,
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
          ],
        ),
      );
    },
  );
}

class _ExecutionBadge extends StatelessWidget {
  const _ExecutionBadge({required this.execution});

  final GraphNodeExecutionVisual execution;

  @override
  Widget build(BuildContext context) {
    final (icon, color, tooltip) = switch (execution.status) {
      GraphNodeExecutionStatus.running => (
        Icons.sync,
        const Color(0xff38bdf8),
        _executionTooltip(execution),
      ),
      GraphNodeExecutionStatus.success => (
        Icons.check,
        const Color(0xff4ade80),
        _executionTooltip(execution),
      ),
      GraphNodeExecutionStatus.error => (
        Icons.error_outline,
        const Color(0xfff87171),
        execution.error ?? 'Failed',
      ),
      GraphNodeExecutionStatus.aborted => (
        Icons.cancel_outlined,
        const Color(0xff9aa4b2),
        'Aborted',
      ),
    };
    final runningDuration = execution.status == GraphNodeExecutionStatus.running
        ? DateTime.now().difference(execution.startedAt)
        : execution.duration;
    final label = execution.status == GraphNodeExecutionStatus.running
        ? _durationLabel('Running', runningDuration)
        : execution.status == GraphNodeExecutionStatus.success &&
              execution.duration != null
        ? _durationLabel('Done', execution.duration)
        : null;
    final count = execution.activeCount != null && execution.activeCount! > 1
        ? '×${execution.activeCount}'
        : null;
    return Semantics(
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 16),
            if (count != null || label != null) ...[
              const SizedBox(width: 3),
              Text(
                [?count, ?label].join(' '),
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _executionTooltip(GraphNodeExecutionVisual execution) {
  final duration = execution.status == GraphNodeExecutionStatus.running
      ? DateTime.now().difference(execution.startedAt)
      : execution.duration;
  final details = <String>[
    _durationLabel(
      execution.status == GraphNodeExecutionStatus.running
          ? 'Running'
          : 'Completed',
      duration,
    ),
  ];
  if (execution.activeCount != null && execution.activeCount! > 1) {
    details.add('${execution.activeCount} concurrent runs');
  }
  if (execution.lastIteration != null) {
    details.add('iteration ${execution.lastIteration}');
  }
  if (execution.selectedPort != null) details.add(execution.selectedPort!);
  return details.join(' • ');
}

String _durationLabel(String label, Duration? duration) {
  if (duration == null) return label;
  final milliseconds = duration.inMilliseconds;
  return '$label in ${milliseconds < 1000 ? '${milliseconds}ms' : '${(milliseconds / 1000).toStringAsFixed(2)}s'}';
}

List<NodeEditorMenuEntry> _nodeEditorContextMenu(
  BuildContext context,
  ShowRunnerGraphEditor editor,
  NodeDataModel node, {
  required Future<DartPluginRegistry> registryFuture,
  Future<void> Function(String schemaNodeId)? onRunNode,
}) => [
  NodeEditorMenuSection(
    label: 'Node',
    icon: Icons.tune,
    entries: [
      if (onRunNode != null && editor.schemaNodeIdForEditor(node.id) != null)
        NodeEditorMenuAction(
          label: 'Run from here',
          icon: Icons.play_arrow,
          onSelected: () =>
              unawaited(onRunNode(editor.schemaNodeIdForEditor(node.id)!)),
        ),
      NodeEditorMenuAction(
        label: 'Focus node',
        icon: Icons.center_focus_strong,
        onSelected: () => editor.controller.focusNodesById({node.id}),
      ),
      NodeEditorMenuAction(
        label: 'Rename',
        icon: Icons.edit_outlined,
        onSelected: () => unawaited(_renameNode(context, editor, node)),
      ),
      NodeEditorMenuAction(
        label: node.state.isCollapsed ? 'Expand node' : 'Collapse node',
        icon: node.state.isCollapsed ? Icons.expand_more : Icons.expand_less,
        onSelected: () {
          editor.controller.selectNodesById({node.id});
          editor.controller.toggleCollapseSelectedNodes(
            !node.state.isCollapsed,
          );
        },
      ),
      NodeEditorMenuAction(
        label: 'Edit configuration',
        icon: Icons.tune,
        onSelected: () => unawaited(
          _editNodeConfiguration(
            context,
            editor,
            node,
            registryFuture: registryFuture,
          ),
        ),
      ),
      if (editor.isTriggerNode(node.id))
        NodeEditorMenuAction(
          label: 'Replace trigger',
          icon: Icons.swap_horiz,
          onSelected: () => unawaited(
            _replaceTriggerNode(
              context,
              editor,
              node,
              registryFuture: registryFuture,
            ),
          ),
        ),
    ],
  ),
  NodeEditorMenuSection(
    label: 'Insert',
    icon: Icons.playlist_add,
    entries: [
      NodeEditorMenuAction(
        label: 'Insert action after',
        icon: Icons.playlist_add,
        onSelected: () => unawaited(
          _insertActionAfterNode(
            context,
            editor,
            node,
            registryFuture: registryFuture,
          ),
        ),
      ),
      NodeEditorMenuAction(
        label: 'Insert control flow after',
        icon: Icons.account_tree_outlined,
        enabled: node.ports.values.any(
          (port) =>
              port.prototype.type == PortType.control &&
              port.prototype.direction == PortDirection.output,
        ),
        onSelected: () => unawaited(
          _insertControlFlowAfterNode(
            context,
            editor,
            node,
            registryFuture: registryFuture,
          ),
        ),
      ),
    ],
  ),
  NodeEditorMenuSection(
    label: 'Clipboard',
    icon: Icons.content_copy,
    entries: [
      NodeEditorMenuAction(
        label: 'Copy',
        icon: Icons.copy_outlined,
        onSelected: () => unawaited(editor.copySelection(context: context)),
      ),
    ],
  ),
  NodeEditorMenuAction(
    label: 'Delete',
    icon: Icons.delete_outline,
    enabled: true,
    onSelected: () {
      if (editor.isVariableNode(node.id)) {
        editor.deleteVariableNode(node.id);
      } else if (editor.controller.selectedNodeIds.contains(node.id)) {
        editor.controller.deleteSelection();
      } else {
        editor.controller.removeNodeById(node.id);
        editor.controller.clearSelection();
      }
    },
  ),
];

List<NodeEditorMenuEntry> _canvasNodeEditorContextMenu({
  required BuildContext context,
  required ShowRunnerGraphEditor editor,
  required Offset position,
  required Future<DartPluginRegistry> registryFuture,
  DartPluginRegistry? registry,
}) {
  NodeEditorMenuAction addNode(_NodePickerEntry entry) => NodeEditorMenuAction(
    label: entry.label,
    icon: entry.icon,
    searchText: '${entry.pluginName} ${entry.group}',
    onSelected: () => unawaited(
      _addAndConfigureNode(
        context,
        editor,
        entry.type,
        position: position,
        title: entry.label,
        registryFuture: registryFuture,
      ),
    ),
  );

  List<NodeEditorMenuEntry> grouped(
    Iterable<_NodePickerEntry> nodes, {
    required bool actions,
  }) {
    final groups = <String, List<_NodePickerEntry>>{};
    for (final node in nodes) {
      groups.putIfAbsent(node.group, () => []).add(node);
    }
    return [
      for (final group in groups.entries)
        NodeEditorMenuSection(
          label: group.key,
          icon: actions ? Icons.extension_outlined : Icons.bolt,
          entries: [for (final node in group.value) addNode(node)],
        ),
    ];
  }

  final entries = <NodeEditorMenuEntry>[
    NodeEditorMenuSection(
      label: 'Canvas',
      icon: Icons.dashboard_outlined,
      entries: [
        NodeEditorMenuAction(
          label: 'Center view',
          icon: Icons.center_focus_strong,
          onSelected: () =>
              editor.controller.setViewportOffset(Offset.zero, absolute: true),
        ),
        NodeEditorMenuAction(
          label: 'Reset zoom',
          icon: Icons.zoom_in,
          onSelected: () =>
              editor.controller.setViewportZoom(1, absolute: true),
        ),
        NodeEditorMenuAction(
          label: 'Select all nodes',
          icon: Icons.select_all,
          onSelected: editor.controller.selectAllNodes,
        ),
        NodeEditorMenuAction(
          label: 'Clear selection',
          icon: Icons.deselect,
          onSelected: editor.controller.clearSelection,
        ),
        NodeEditorMenuAction(
          label: 'Paste',
          icon: Icons.paste,
          onSelected: () => unawaited(
            editor.pasteSelection(position: position, context: context),
          ),
        ),
        const NodeEditorMenuDivider(),
        NodeEditorMenuAction(
          label: 'Undo',
          icon: Icons.undo,
          onSelected: editor.controller.history.undo,
        ),
        NodeEditorMenuAction(
          label: 'Redo',
          icon: Icons.redo,
          onSelected: editor.controller.history.redo,
        ),
      ],
    ),
  ];

  if (registry != null) {
    final available = _registeredNodeEntries(registry, enabled: true);
    final triggers = available.where((entry) => entry.category == 'Triggers');
    final actions = available.where((entry) => entry.category == 'Actions');
    final conversions = available.where((entry) => entry.category == 'Data');
    final categories = <String, List<_NodePickerEntry>>{};
    for (final action in actions) {
      categories.putIfAbsent(_actionCategory(action), () => []).add(action);
    }
    if (categories.isNotEmpty) {
      entries.add(
        NodeEditorMenuSection(
          label: 'Categories',
          icon: Icons.category_outlined,
          entries: [
            for (final category in categories.entries)
              NodeEditorMenuSection(
                label: category.key,
                icon: Icons.extension_outlined,
                entries: [for (final node in category.value) addNode(node)],
              ),
          ],
        ),
      );
    }
    entries.add(
      NodeEditorMenuSection(
        label: 'Integrations',
        icon: Icons.extension_outlined,
        entries: [
          NodeEditorMenuSection(
            label: 'Triggers',
            icon: Icons.bolt,
            entries: grouped(triggers, actions: false),
          ),
          NodeEditorMenuSection(
            label: 'Actions',
            icon: Icons.play_circle_outline,
            entries: grouped(actions, actions: true),
          ),
        ],
      ),
    );
    entries.add(
      NodeEditorMenuSection(
        label: 'Data',
        icon: Icons.data_object,
        entries: [
          if (conversions.isNotEmpty)
            NodeEditorMenuSection(
              label: 'Conversions',
              icon: Icons.swap_horiz,
              entries: [for (final node in conversions) addNode(node)],
            ),
          NodeEditorMenuSection(
            label: 'Variables',
            icon: Icons.data_object,
            entries: [
              for (final type in const ['string', 'number', 'boolean', 'color'])
                NodeEditorMenuAction(
                  label:
                      '${type[0].toUpperCase()}${type.substring(1)} variable',
                  icon: Icons.data_object,
                  onSelected: () =>
                      editor.addVariableNodeAtScreenPosition(type, position),
                ),
            ],
          ),
        ],
      ),
    );
  }

  final controlFlow = _GraphNodePalette._nodes.where(
    (entry) => entry.category == 'Control flow',
  );
  entries.add(
    NodeEditorMenuSection(
      label: 'Flow',
      icon: Icons.account_tree_outlined,
      entries: [
        for (final entry in controlFlow)
          NodeEditorMenuAction(
            label: entry.label,
            icon: entry.icon,
            onSelected: () => unawaited(
              _addAndConfigureNode(
                context,
                editor,
                entry.type,
                position: position,
                title: entry.label,
                registryFuture: registryFuture,
              ),
            ),
          ),
        for (final subgraph in editor.subgraphs.value)
          NodeEditorMenuAction(
            label: subgraph.name.isEmpty ? subgraph.id : subgraph.name,
            icon: Icons.functions,
            searchText: 'Call subgraph',
            onSelected: () =>
                editor.addSubgraphCallAtScreenPosition(subgraph.id, position),
          ),
      ],
    ),
  );
  return entries;
}

Future<void> _replaceTriggerNode(
  BuildContext context,
  ShowRunnerGraphEditor editor,
  NodeDataModel node, {
  required Future<DartPluginRegistry> registryFuture,
}) async {
  final selected = await showDialog<({String type, String title})>(
    context: context,
    builder: (context) =>
        _NodePickerDialog(registryFuture: registryFuture, triggersOnly: true),
  );
  if (selected == null || !context.mounted) return;
  final replacementId = editor.replaceTriggerNode(
    node.id,
    selected.type,
    title: selected.title,
  );
  await _configureInsertedNode(
    context,
    editor,
    replacementId,
    registryFuture: registryFuture,
  );
}

Future<void> _insertActionAfterNode(
  BuildContext context,
  ShowRunnerGraphEditor editor,
  NodeDataModel node, {
  required Future<DartPluginRegistry> registryFuture,
}) async {
  final selected = await showDialog<({String type, String title})>(
    context: context,
    builder: (context) =>
        _NodePickerDialog(registryFuture: registryFuture, actionsOnly: true),
  );
  if (selected == null || !context.mounted) return;
  final insertedId = editor.insertActionAfterNode(selected.type, node.id);
  await _configureInsertedNode(
    context,
    editor,
    insertedId,
    registryFuture: registryFuture,
  );
}

Future<void> _insertControlFlowAfterNode(
  BuildContext context,
  ShowRunnerGraphEditor editor,
  NodeDataModel node, {
  required Future<DartPluginRegistry> registryFuture,
}) async {
  final selected = await showDialog<({String type, String title})>(
    context: context,
    builder: (context) => _NodePickerDialog(
      registryFuture: registryFuture,
      controlFlowOnly: true,
    ),
  );
  if (selected == null || !context.mounted) return;
  final insertedId = editor.insertControlFlowAfterNode(selected.type, node.id);
  await _configureInsertedNode(
    context,
    editor,
    insertedId,
    registryFuture: registryFuture,
  );
}

Future<void> _addNodeAtScreenPosition(
  BuildContext context,
  ShowRunnerGraphEditor editor,
  Offset position, {
  required Future<DartPluginRegistry> registryFuture,
}) async {
  final selected = await showDialog<({String type, String title})>(
    context: context,
    builder: (context) => _NodePickerDialog(registryFuture: registryFuture),
  );
  if (selected == null || !context.mounted) return;
  final insertedId = editor.addNodeTypeAtScreenPosition(
    selected.type,
    position,
    title: selected.title,
  );
  await _configureInsertedNode(
    context,
    editor,
    insertedId,
    registryFuture: registryFuture,
  );
}

Future<void> _renameNode(
  BuildContext context,
  ShowRunnerGraphEditor editor,
  NodeDataModel node,
) async {
  final titleController = TextEditingController(
    text:
        editor.customNodeTitle(node.id) ?? node.prototype.displayName(context),
  );
  final title = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Rename node'),
      content: TextField(
        controller: titleController,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Node name'),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(titleController.text),
          child: const Text('Rename'),
        ),
      ],
    ),
  );
  titleController.dispose();
  if (title != null) editor.renameNode(node.id, title);
}
