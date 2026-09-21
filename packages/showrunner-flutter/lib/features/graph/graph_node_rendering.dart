part of 'graph_workspace.dart';

class _GraphNodeHeader extends StatefulWidget {
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
  State<_GraphNodeHeader> createState() => _GraphNodeHeaderState();
}

class _GraphNodeHeaderState extends State<_GraphNodeHeader>
    with SingleTickerProviderStateMixin {
  bool _runHovered = false;
  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 720),
  );
  late final Listenable _stateChanges = Listenable.merge([
    widget.editor.activeNodeIds,
    widget.editor.executionStates,
    widget.editor.nodeRevision,
    widget.editor.searchQuery,
    widget.editor.searchMatchIndex,
    widget.editor.dropTargetNodeId,
  ]);

  @override
  void initState() {
    super.initState();
    widget.editor.activeNodeIds.addListener(_syncPulse);
    widget.editor.executionStates.addListener(_syncPulse);
    widget.editor.nodeRevision.addListener(_syncPulse);
    _syncPulse();
  }

  void _syncPulse() {
    final isRunning = widget.editor.activeNodeIds.value.contains(
      widget.node.id,
    );
    if (isRunning && !_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    } else if (!isRunning && _pulseController.isAnimating) {
      _pulseController.stop();
      _pulseController.value = 1;
    }
  }

  @override
  void dispose() {
    widget.editor.activeNodeIds.removeListener(_syncPulse);
    widget.editor.executionStates.removeListener(_syncPulse);
    widget.editor.nodeRevision.removeListener(_syncPulse);
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([_stateChanges, _pulseController]),
    builder: (context, child) {
      final node = widget.node;
      final accent = widget.editor.nodeAccent(node.id);
      final headerStyle = node.builtHeaderStyle;
      final active = widget.editor.activeNodeIds.value.contains(node.id);
      final execution = widget.editor.executionStates.value[node.id];
      final dropTarget = widget.editor.dropTargetNodeId.value == node.id;
      final searchMatches = widget.editor.searchNodeIds();
      final searchMatch =
          searchMatches.isNotEmpty &&
          searchMatches.elementAt(
                widget.editor.searchMatchIndex.value % searchMatches.length,
              ) ==
              node.id;
      final statusColor = switch (execution?.status) {
        GraphNodeExecutionStatus.success => const Color(0xff4ade80),
        GraphNodeExecutionStatus.error => const Color(0xfff87171),
        GraphNodeExecutionStatus.running => const Color(0xff38bdf8),
        null => accent,
      };
      final pulse = active
          ? Curves.easeInOut.transform(_pulseController.value)
          : 0.0;
      return Opacity(
        opacity:
            widget.editor.searchQuery.value.isEmpty ||
                widget.editor.searchNodeIds().contains(node.id)
            ? 1
            : 0.35,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: headerStyle.decoration.copyWith(
            color: active
                ? Color.lerp(
                    statusColor.withValues(alpha: 0.2),
                    Colors.white,
                    pulse * 0.22,
                  )
                : Colors.transparent,
            gradient: null,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(6),
              topRight: Radius.circular(6),
            ),
            border: Border.all(
              color: dropTarget
                  ? const Color(0xff2ed47a)
                  : searchMatch
                  ? const Color(0xffffcc00)
                  : active || execution != null
                  ? statusColor
                  : Colors.transparent,
              width: dropTarget
                  ? 2.5
                  : searchMatch
                  ? 2
                  : (active ? 1.5 + pulse * 1.5 : 1),
            ),
            boxShadow: [
              if (dropTarget)
                const BoxShadow(
                  color: Color(0x772ed47a),
                  blurRadius: 0,
                  spreadRadius: 3,
                ),
              if (searchMatch)
                const BoxShadow(
                  color: Color(0x99ffcc00),
                  blurRadius: 0,
                  spreadRadius: 2,
                ),
              if (active)
                BoxShadow(
                  color: statusColor.withValues(alpha: 0.18 + pulse * 0.18),
                  blurRadius: 8 + pulse * 8,
                ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
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
                        widget.editor.nodeIcon(node.id),
                        size: 20,
                        color: accent,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.editor.nodeTitle(node.id),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: headerStyle.textStyle.copyWith(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                    if (widget.editor.isTriggerNode(node.id) &&
                        widget.onRunNode != null &&
                        widget.editor.schemaNodeIdForEditor(node.id) != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Tooltip(
                          message: 'Run automation',
                          child: MouseRegion(
                            onEnter: (_) => setState(() => _runHovered = true),
                            onExit: (_) => setState(() => _runHovered = false),
                            child: InkWell(
                              onTap: () => unawaited(
                                widget.onRunNode!(
                                  widget.editor.schemaNodeIdForEditor(node.id)!,
                                ),
                              ),
                              borderRadius: BorderRadius.circular(10),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 120),
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  color: _runHovered
                                      ? const Color(0xffa7f3b9)
                                      : const Color(0xff68d391),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    if (_runHovered)
                                      const BoxShadow(
                                        color: Color(0x8868d391),
                                        blurRadius: 8,
                                        spreadRadius: 1,
                                      ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.play_arrow,
                                  color: Color(0xff101316),
                                  size: 14,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (widget.editor.nodeBadge(node.id) case final badge?)
                      Container(
                        margin: const EdgeInsets.only(left: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xffe9aaff),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          badge,
                          style: TextStyle(
                            color: const Color(0xff1b0f21),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    if (execution != null) ...[
                      const SizedBox(width: 4),
                      _ExecutionBadge(execution: execution),
                    ],
                    IconButton(
                      tooltip: node.state.isCollapsed
                          ? 'Expand node'
                          : 'Collapse node',
                      onPressed: widget.onToggleCollapse,
                      icon: Icon(
                        node.state.isCollapsed
                            ? Icons.expand_more
                            : Icons.expand_less,
                        size: 18,
                        color: Colors.white60,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 24,
                        height: 24,
                      ),
                    ),
                  ],
                ),
                if (widget.editor.nodeSubtitle(node.id).isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 40, top: 2),
                    child: Text(
                      widget.editor.nodeSubtitle(node.id),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xffd6d6d6),
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                for (final line in widget.editor.nodeConfigLines(node.id))
                  Padding(
                    padding: const EdgeInsets.only(left: 25, top: 3),
                    child: Row(
                      children: [
                        Text(
                          line.$1,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 10,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            line.$2,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
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
        'Running',
      ),
      GraphNodeExecutionStatus.success => (
        Icons.check,
        const Color(0xff4ade80),
        _durationLabel('Completed', execution.duration),
      ),
      GraphNodeExecutionStatus.error => (
        Icons.error_outline,
        const Color(0xfff87171),
        execution.error ?? 'Failed',
      ),
    };
    return Tooltip(
      message: tooltip,
      child: Icon(icon, color: color, size: 16),
    );
  }
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
