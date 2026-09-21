part of 'graph_workspace.dart';

class _GraphNodePalette extends StatelessWidget {
  const _GraphNodePalette({required this.editor, required this.registryFuture});

  final ShowRunnerGraphEditor editor;
  final Future<DartPluginRegistry> registryFuture;

  static const _nodes = <_NodePickerEntry>[
    _NodePickerEntry(
      type: 'if',
      label: 'If',
      icon: Icons.call_split,
      category: 'Control flow',
      group: 'Control flow',
    ),
    _NodePickerEntry(
      type: 'switch',
      label: 'Switch',
      icon: Icons.alt_route,
      category: 'Control flow',
      group: 'Control flow',
    ),
    _NodePickerEntry(
      type: 'for',
      label: 'For',
      icon: Icons.repeat,
      category: 'Control flow',
      group: 'Control flow',
    ),
    _NodePickerEntry(
      type: 'forEach',
      label: 'For each',
      icon: Icons.loop,
      category: 'Control flow',
      group: 'Control flow',
    ),
    _NodePickerEntry(
      type: 'while',
      label: 'While',
      icon: Icons.sync,
      category: 'Control flow',
      group: 'Control flow',
    ),
    _NodePickerEntry(
      type: 'break',
      label: 'Break',
      icon: Icons.stop_circle_outlined,
      category: 'Control flow',
      group: 'Control flow',
    ),
    _NodePickerEntry(
      type: 'continue',
      label: 'Continue',
      icon: Icons.skip_next,
      category: 'Control flow',
      group: 'Control flow',
    ),
    _NodePickerEntry(
      type: 'return',
      label: 'Return',
      icon: Icons.keyboard_return,
      category: 'Control flow',
      group: 'Control flow',
    ),
  ];

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
    child: Row(
      children: [
        const Icon(Icons.account_tree_outlined, size: 18),
        const SizedBox(width: 8),
        const Text('Add node'),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Search node types',
          onPressed: () async {
            final type = await showDialog<({String type, String title})>(
              context: context,
              builder: (context) =>
                  _NodePickerDialog(registryFuture: registryFuture),
            );
            if (type != null && context.mounted) {
              await _addAndConfigureNode(
                context,
                editor,
                type.type,
                title: type.title,
                registryFuture: registryFuture,
              );
            }
          },
          icon: const Icon(Icons.add_circle_outline),
        ),
        ValueListenableBuilder<List<String>>(
          valueListenable: editor.activeGraphPath,
          builder: (context, path, child) => PopupMenuButton<String>(
            enabled: path.isEmpty,
            tooltip: 'Add variable',
            icon: const Icon(Icons.data_object),
            onSelected: editor.addVariableNode,
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'string', child: Text('String variable')),
              PopupMenuItem(value: 'number', child: Text('Number variable')),
              PopupMenuItem(value: 'boolean', child: Text('Boolean variable')),
              PopupMenuItem(value: 'color', child: Text('Color variable')),
            ],
          ),
        ),
        ValueListenableBuilder<List<SubgraphDefinition>>(
          valueListenable: editor.subgraphs,
          builder: (context, subgraphs, child) => IconButton(
            tooltip: 'Browse subgraphs',
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => _SubgraphBrowser(editor: editor),
            ),
            icon: const Icon(Icons.account_tree_outlined),
          ),
        ),
        ValueListenableBuilder<List<NodeFrame>>(
          valueListenable: editor.frames,
          builder: (context, frames, child) => IconButton(
            tooltip: 'Manage frames',
            onPressed: frames.isEmpty
                ? null
                : () => showDialog<void>(
                    context: context,
                    builder: (context) => _FrameManager(editor: editor),
                  ),
            icon: const Icon(Icons.layers_outlined),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FutureBuilder<DartPluginRegistry>(
            future: registryFuture,
            builder: (context, registrySnapshot) => ValueListenableBuilder<String>(
              valueListenable: editor.searchQuery,
              builder: (context, query, child) => Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: const InputDecoration(
                        isDense: true,
                        prefixIcon: Icon(Icons.search, size: 18),
                        hintText: 'Search nodes',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: editor.setSearchQuery,
                      onSubmitted: (_) => editor.focusSearchResult(),
                    ),
                  ),
                  if (query.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    ValueListenableBuilder<int>(
                      valueListenable: editor.searchMatchIndex,
                      builder: (context, index, child) => Text(
                        '${editor.searchResultCount() == 0 ? 0 : index + 1}/${editor.searchResultCount()}',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Previous match',
                      onPressed: editor.searchResultCount() == 0
                          ? null
                          : () => editor.focusSearchResult(forward: false),
                      icon: const Icon(Icons.keyboard_arrow_up),
                    ),
                    IconButton(
                      tooltip: 'Next match',
                      onPressed: editor.searchResultCount() == 0
                          ? null
                          : () => editor.focusSearchResult(),
                      icon: const Icon(Icons.keyboard_arrow_down),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _GraphActionDropTarget extends StatelessWidget {
  const _GraphActionDropTarget({
    required this.editor,
    required this.registryFuture,
    required this.child,
  });

  final ShowRunnerGraphEditor editor;
  final Future<DartPluginRegistry> registryFuture;
  final Widget child;

  @override
  Widget build(BuildContext context) => DragTarget<String>(
    onWillAcceptWithDetails: (details) => details.data.trim().isNotEmpty,
    onMove: (details) => editor.updateActionDropTarget(details.offset),
    onLeave: (_) => editor.clearActionDropTarget(),
    onAcceptWithDetails: (details) => unawaited(() async {
      editor.clearActionDropTarget();
      await _dropGraphAction(
        context,
        editor,
        details.data,
        details.offset,
        registryFuture: registryFuture,
      );
    }()),
    builder: (context, candidateData, rejectedData) => child,
  );
}

Future<void> _dropGraphAction(
  BuildContext context,
  ShowRunnerGraphEditor editor,
  String nodeType,
  Offset screenPosition, {
  required Future<DartPluginRegistry> registryFuture,
}) async {
  final registry = await registryFuture;
  if (!context.mounted) return;
  final title = _nodeLabelForType(nodeType, registry);
  final flowLinkId = editor.flowLinkIdAtScreenPosition(screenPosition);
  String? nodeId;
  if (flowLinkId != null) {
    nodeId = editor.insertActionOnFlowEdge(nodeType, flowLinkId);
  } else {
    final targetNode = editor.nodeIdAtScreenPosition(screenPosition);
    nodeId = targetNode == null
        ? editor.addNodeTypeAtScreenPosition(
            nodeType,
            screenPosition,
            title: title,
          )
        : editor.insertActionAfterNode(nodeType, targetNode);
  }
  await _configureInsertedNode(
    context,
    editor,
    nodeId,
    registryFuture: Future.value(registry),
  );
}

class _GraphBreadcrumb extends StatelessWidget {
  const _GraphBreadcrumb({required this.editor});

  final ShowRunnerGraphEditor editor;

  @override
  Widget build(BuildContext context) {
    final path = editor.activeGraphPath.value;
    return Material(
      color: const Color(0xff101820),
      child: SizedBox(
        height: 38,
        child: Row(
          children: [
            IconButton(
              tooltip: 'Back to parent graph',
              onPressed: path.isEmpty ? null : editor.goBackToParentGraph,
              icon: const Icon(Icons.arrow_back, size: 18),
            ),
            TextButton(
              onPressed: path.isEmpty
                  ? null
                  : () => editor.navigateToGraphDepth(0),
              child: const Text('Main graph'),
            ),
            for (var index = 0; index < path.length; index++) ...[
              const Icon(Icons.chevron_right, size: 18),
              TextButton(
                onPressed: index == path.length - 1
                    ? null
                    : () => editor.navigateToGraphDepth(index + 1),
                child: Text(_subgraphName(editor, path[index])),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _subgraphName(ShowRunnerGraphEditor editor, String id) =>
    editor.subgraphs.value
        .where((subgraph) => subgraph.id == id)
        .map((subgraph) => subgraph.name)
        .firstOrNull ??
    id;

// Context menus compose sai_nodes defaults with ShowRunner actions such as
// plugin insertion, variables, subgraphs, and graph recovery.
List<ContextMenuEntry> _editorContextMenu({
  required BuildContext context,
  required ShowRunnerGraphEditor editor,
  required Offset position,
  required List<ContextMenuEntry> defaults,
  required Future<DartPluginRegistry> registryFuture,
  DartPluginRegistry? registry,
}) => _showrunnerEditorContextMenu(
  context: context,
  editor: editor,
  position: position,
  defaults: defaults,
  registryFuture: registryFuture,
  registry: registry,
);

List<ContextMenuEntry> _showrunnerEditorContextMenu({
  required BuildContext context,
  required ShowRunnerGraphEditor editor,
  required Offset position,
  required List<ContextMenuEntry> defaults,
  required Future<DartPluginRegistry> registryFuture,
  DartPluginRegistry? registry,
}) {
  final entries = <ContextMenuEntry>[...defaults, const MenuDivider()];
  if (registry != null) {
    final enabledNodes = _registeredNodeEntries(registry, enabled: true);
    final triggers = enabledNodes.where((node) => node.category == 'Triggers');
    final actions = enabledNodes.where((node) => node.category == 'Actions');
    final conversions = enabledNodes.where((node) => node.category == 'Data');

    if (triggers.isNotEmpty) {
      entries.add(
        MenuItem<dynamic>.submenu(
          label: const Text('Add trigger'),
          icon: const Icon(Icons.bolt),
          items: _groupedNodeMenuEntries(
            triggers,
            editor,
            position,
            context: context,
            registryFuture: registryFuture,
          ),
        ),
      );
    }
    if (actions.isNotEmpty) {
      entries.add(
        MenuItem<dynamic>.submenu(
          label: const Text('Add action'),
          icon: const Icon(Icons.play_circle_outline),
          items: _groupedNodeMenuEntries(
            actions,
            editor,
            position,
            context: context,
            registryFuture: registryFuture,
          ),
        ),
      );
      final categories = <String, List<_NodePickerEntry>>{};
      for (final action in actions) {
        categories.putIfAbsent(_actionCategory(action), () => []).add(action);
      }
      entries.add(
        MenuItem<dynamic>.submenu(
          label: const Text('Action categories'),
          icon: const Icon(Icons.category_outlined),
          items: [
            for (final category in categories.entries)
              MenuItem<dynamic>.submenu(
                label: Text(category.key),
                items: _nodeMenuItems(
                  category.value,
                  editor,
                  position,
                  context: context,
                  registryFuture: registryFuture,
                ),
              ),
          ],
        ),
      );
    }
    if (conversions.isNotEmpty) {
      entries.add(
        MenuItem<dynamic>.submenu(
          label: const Text('Conversions'),
          icon: const Icon(Icons.swap_horiz),
          items: _groupedNodeMenuEntries(
            conversions,
            editor,
            position,
            context: context,
            registryFuture: registryFuture,
          ),
        ),
      );
    }
    // Disabled plugins remain registered so existing nodes can be hydrated,
    // rendered, edited, and saved. They are intentionally omitted from all
    // creation menus; re-enabling the plugin in Integrations is the only way
    // to add new nodes from it.
  }
  final builtIns = _GraphNodePalette._nodes.where(
    (node) => node.category == 'Built-in',
  );
  if (builtIns.isNotEmpty) {
    entries.add(
      MenuItem<dynamic>.submenu(
        label: const Text('Built-in nodes'),
        icon: const Icon(Icons.widgets_outlined),
        items: _nodeMenuItems(
          builtIns,
          editor,
          position,
          context: context,
          registryFuture: registryFuture,
        ),
      ),
    );
  }
  if (editor.activeSubgraphId == null) {
    entries.add(
      MenuItem<dynamic>.submenu(
        label: const Text('Add variable'),
        icon: const Icon(Icons.data_object),
        items: [
          for (final type in const ['string', 'number', 'boolean', 'color'])
            MenuItem<dynamic>(
              label: Text('${type[0].toUpperCase()}${type.substring(1)}'),
              onSelected: (_) =>
                  editor.addVariableNodeAtScreenPosition(type, position),
            ),
        ],
      ),
    );
  }
  entries.add(
    MenuItem<dynamic>.submenu(
      label: const Text('Add control flow'),
      icon: const Icon(Icons.account_tree_outlined),
      items: [
        for (final node in _GraphNodePalette._nodes.where(
          (node) => node.category == 'Control flow',
        ))
          MenuItem<dynamic>(
            label: Text(node.label),
            icon: Icon(node.icon),
            onSelected: (_) => _addAndConfigureNode(
              context,
              editor,
              node.type,
              position: position,
              title: node.label,
              registryFuture: registryFuture,
            ),
          ),
      ],
    ),
  );
  if (editor.subgraphs.value.isNotEmpty) {
    entries.add(
      MenuItem<dynamic>.submenu(
        label: const Text('Call subgraph'),
        icon: const Icon(Icons.functions),
        items: [
          for (final subgraph in editor.subgraphs.value)
            MenuItem<dynamic>(
              label: Text(subgraph.name.isEmpty ? subgraph.id : subgraph.name),
              onSelected: (_) =>
                  editor.addSubgraphCallAtScreenPosition(subgraph.id, position),
            ),
        ],
      ),
    );
  }
  entries
    ..add(const MenuDivider())
    ..add(
      MenuItem<dynamic>(
        label: const Text('Search and add node'),
        icon: const Icon(Icons.search),
        onSelected: (_) => _addNodeAtScreenPosition(
          context,
          editor,
          position,
          registryFuture: registryFuture,
        ),
      ),
    );
  return entries;
}

List<_NodePickerEntry> _registeredNodeEntries(
  DartPluginRegistry registry, {
  required bool enabled,
}) {
  final entries = <_NodePickerEntry>[];
  for (final plugin in registry.plugins.where(
    (plugin) => registry.isPluginEnabledId(plugin.id) == enabled,
  )) {
    for (final action in plugin.actions) {
      final conversion = _isConversionEntry(
        plugin.id.value,
        action.actionId.value,
      );
      entries.add(
        _NodePickerEntry(
          type: '${plugin.id.value}.${action.actionId.value}',
          label: action.displayName ?? action.actionId.value,
          icon: conversion ? Icons.swap_horiz : Icons.play_arrow,
          category: conversion ? 'Data' : 'Actions',
          group: conversion ? 'Conversions' : plugin.name,
          pluginId: plugin.id.value,
          pluginName: plugin.name,
          enabled: enabled,
        ),
      );
    }
    for (final trigger in plugin.triggers) {
      entries.add(
        _NodePickerEntry(
          type: 'trigger.${plugin.id.value}.${trigger.triggerId.value}',
          label: trigger.displayName,
          icon: Icons.bolt,
          category: 'Triggers',
          group: plugin.name,
          pluginId: plugin.id.value,
          pluginName: plugin.name,
          enabled: enabled,
        ),
      );
    }
  }
  return entries;
}

List<_NodePickerEntry> _nodePickerEntries(
  DartPluginRegistry? registry, {
  required bool enabled,
}) {
  final entries = <_NodePickerEntry>[
    if (enabled) ..._GraphNodePalette._nodes,
    if (registry != null) ..._registeredNodeEntries(registry, enabled: enabled),
  ];
  return entries;
}

List<ContextMenuEntry> _groupedNodeMenuEntries(
  Iterable<_NodePickerEntry> entries,
  ShowRunnerGraphEditor editor,
  Offset position, {
  required BuildContext context,
  required Future<DartPluginRegistry> registryFuture,
}) {
  final groups = <String, List<_NodePickerEntry>>{};
  for (final entry in entries) {
    groups.putIfAbsent(entry.group, () => []).add(entry);
  }
  return [
    for (final group in groups.entries)
      MenuItem<dynamic>.submenu(
        label: Text(group.key),
        icon: Icon(_nodeIconForType(group.value.first.type)),
        items: _nodeMenuItems(
          group.value,
          editor,
          position,
          context: context,
          registryFuture: registryFuture,
        ),
      ),
  ];
}

List<ContextMenuEntry> _nodeMenuItems(
  Iterable<_NodePickerEntry> entries,
  ShowRunnerGraphEditor editor,
  Offset position, {
  required BuildContext context,
  required Future<DartPluginRegistry> registryFuture,
}) => [
  for (final entry in entries)
    MenuItem<dynamic>(
      label: Text(entry.label),
      icon: Icon(entry.icon),
      enabled: entry.enabled,
      onSelected: entry.enabled
          ? (_) => _addAndConfigureNode(
              context,
              editor,
              entry.type,
              position: position,
              title: entry.label,
              registryFuture: registryFuture,
            )
          : null,
    ),
];

Future<void> _addAndConfigureNode(
  BuildContext context,
  ShowRunnerGraphEditor editor,
  String nodeType, {
  String? title,
  Offset? position,
  required Future<DartPluginRegistry> registryFuture,
}) async {
  final nodeId = position == null
      ? editor.addNodeType(nodeType, title: title)
      : editor.addNodeTypeAtScreenPosition(nodeType, position, title: title);
  await _configureInsertedNode(
    context,
    editor,
    nodeId,
    registryFuture: registryFuture,
  );
}

Future<void> _configureInsertedNode(
  BuildContext context,
  ShowRunnerGraphEditor editor,
  String? nodeId, {
  required Future<DartPluginRegistry> registryFuture,
}) async {
  if (nodeId == null) return;
  editor.controller.selectNodesById({nodeId});
  final node = editor.controller.nodes[nodeId];
  if (node == null) return;
  final registry = await registryFuture;
  if (!context.mounted) return;
  final schema = _configurationSchema(editor, registry, node);
  if (schema != null && editor.nodeConfig(node.id).isEmpty) {
    final defaultValue = constructDartDataInputDefault(schema);
    if (defaultValue is Map) {
      editor.updateNodeConfig(node.id, Map<String, dynamic>.from(defaultValue));
    }
  }
  await _editNodeConfiguration(
    context,
    editor,
    node,
    registryFuture: Future.value(registry),
  );
}

String _actionCategory(_NodePickerEntry entry) {
  final text =
      '${entry.pluginId} ${entry.pluginName} ${entry.type} ${entry.label}'
          .toLowerCase();
  if (text.contains('queue')) return 'Queues';
  if (text.contains('overlay') ||
      text.contains('alert') ||
      text.contains('banner')) {
    return 'Overlays';
  }
  if (const {'obs', 'streamlabs'}.contains(entry.pluginId?.toLowerCase())) {
    return 'Broadcast';
  }
  if (const {
    'twitch',
    'youtube',
    'discord',
    'moderation',
  }.contains(entry.pluginId?.toLowerCase())) {
    return 'Chat';
  }
  if (const {
    'http',
    'os',
    'random',
    'time',
    'variables',
    'input',
    'sound',
    'remote',
  }.contains(entry.pluginId?.toLowerCase())) {
    return 'Utility';
  }
  return 'Other';
}

String _nodeLabelForType(String type, [DartPluginRegistry? registry]) =>
    _GraphNodePalette._nodes
        .where((node) => node.type == type)
        .map((node) => node.label)
        .firstOrNull ??
    _registeredNodeLabel(type, registry) ??
    type;

IconData _nodeIconForType(String type) =>
    _GraphNodePalette._nodes
        .where((node) => node.type == type)
        .map((node) => node.icon)
        .firstOrNull ??
    (type.startsWith('trigger.') ? Icons.bolt : Icons.play_arrow);

String? _registeredNodeLabel(String type, DartPluginRegistry? registry) {
  if (registry == null) return null;
  final parts = type.split('.');
  if (parts.length >= 3 && parts.first == 'trigger') {
    return registry
        .triggerForRuntime(parts[1], parts.sublist(2).join('.'))
        ?.displayName;
  }
  if (parts.length == 2) {
    return registry.actionForRuntime(parts.first, parts.last)?.displayName;
  }
  return null;
}

final class _NodePickerEntry {
  const _NodePickerEntry({
    required this.type,
    required this.label,
    required this.icon,
    required this.category,
    required this.group,
    this.pluginId,
    this.pluginName,
    this.enabled = true,
  });

  final String type;
  final String label;
  final IconData icon;
  final String category;
  final String group;
  final String? pluginId;
  final String? pluginName;
  final bool enabled;
}

class _NodePickerDialog extends StatefulWidget {
  const _NodePickerDialog({
    required this.registryFuture,
    this.actionsOnly = false,
    this.triggersOnly = false,
    this.controlFlowOnly = false,
  });

  final Future<DartPluginRegistry> registryFuture;
  final bool actionsOnly;
  final bool triggersOnly;
  final bool controlFlowOnly;

  @override
  State<_NodePickerDialog> createState() => _NodePickerDialogState();
}

class _SubgraphBrowser extends StatelessWidget {
  const _SubgraphBrowser({required this.editor});

  final ShowRunnerGraphEditor editor;

  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<List<SubgraphDefinition>>(
    valueListenable: editor.subgraphs,
    builder: (context, subgraphs, child) => AlertDialog(
      title: const Text('Subgraphs'),
      content: SizedBox(
        width: 560,
        child: subgraphs.isEmpty
            ? const Text('No subgraphs defined.')
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final subgraph in subgraphs)
                    ExpansionTile(
                      leading: const Icon(Icons.account_tree_outlined),
                      title: Text(
                        subgraph.name.isEmpty ? subgraph.id : subgraph.name,
                      ),
                      subtitle: Text(
                        '${subgraph.nodes.length} nodes, ${subgraph.edges.length} links',
                      ),
                      trailing: IconButton(
                        tooltip: 'Delete subgraph',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => editor.deleteSubgraph(subgraph.id),
                      ),
                      children: [
                        _SubgraphSection(
                          title: 'Parameters',
                          editor: editor,
                          subgraph: subgraph,
                          values: subgraph.parameters,
                        ),
                        _SubgraphSection(
                          title: 'Outputs',
                          editor: editor,
                          subgraph: subgraph,
                          values: subgraph.outputs,
                          output: true,
                        ),
                        if (subgraph.dataWires.isNotEmpty)
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.cable, size: 18),
                            title: Text(
                              '${subgraph.dataWires.length} data wires',
                            ),
                          ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Padding(
                            padding: const EdgeInsets.only(
                              right: 12,
                              bottom: 8,
                            ),
                            child: Wrap(
                              spacing: 8,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () {
                                    editor.enterSubgraph(subgraph.id);
                                    Navigator.of(context).pop();
                                  },
                                  icon: const Icon(Icons.open_in_new),
                                  label: const Text('Open'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: () => _renameSubgraph(
                                    context,
                                    editor,
                                    subgraph,
                                  ),
                                  icon: const Icon(Icons.edit_outlined),
                                  label: const Text('Rename'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: () {
                                    editor.addSubgraphCall(subgraph.id);
                                    Navigator.of(context).pop();
                                  },
                                  icon: const Icon(Icons.add_link),
                                  label: const Text('Call'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
      ),
      actions: [
        OutlinedButton.icon(
          onPressed: editor.addSubgraph,
          icon: const Icon(Icons.add),
          label: const Text('New'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

Future<void> _renameSubgraph(
  BuildContext context,
  ShowRunnerGraphEditor editor,
  SubgraphDefinition subgraph,
) async {
  final controller = TextEditingController(text: subgraph.name);
  final name = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Rename subgraph'),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Subgraph name'),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text),
          child: const Text('Rename'),
        ),
      ],
    ),
  );
  controller.dispose();
  if (name != null) editor.renameSubgraph(subgraph.id, name);
}

class _SubgraphSection extends StatelessWidget {
  const _SubgraphSection({
    required this.title,
    required this.editor,
    required this.subgraph,
    required this.values,
    this.output = false,
  });

  final String title;
  final ShowRunnerGraphEditor editor;
  final SubgraphDefinition subgraph;
  final List<JsonMap> values;
  final bool output;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 12, right: 12, bottom: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.list_alt, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(title)),
            IconButton(
              tooltip: 'Add ${output ? 'output' : 'parameter'}',
              icon: const Icon(Icons.add, size: 18),
              onPressed: () =>
                  editor.addSubgraphParameter(subgraph.id, output: output),
            ),
          ],
        ),
        for (var index = 0; index < values.length; index++)
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.only(left: 26),
            title: Text(values[index]['name']?.toString() ?? 'Unnamed'),
            subtitle: Text(
              _subgraphValueSummary(values[index], output: output),
            ),
            trailing: Wrap(
              children: [
                IconButton(
                  tooltip: 'Edit ${output ? 'output' : 'parameter'}',
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  onPressed: () => _editSubgraphValue(
                    context,
                    editor,
                    subgraph,
                    index,
                    values[index],
                    output: output,
                  ),
                ),
                IconButton(
                  tooltip: 'Delete ${output ? 'output' : 'parameter'}',
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: () => editor.deleteSubgraphParameter(
                    subgraph.id,
                    index,
                    output: output,
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

String _subgraphValueSummary(JsonMap value, {required bool output}) {
  final type = value['type']?.toString() ?? 'any';
  if (output) return type;
  final defaultValue = value['default'];
  final rendered = defaultValue is List || defaultValue is Map
      ? jsonEncode(defaultValue)
      : defaultValue?.toString() ?? '';
  return '$type, default: $rendered';
}

Future<void> _editSubgraphValue(
  BuildContext context,
  ShowRunnerGraphEditor editor,
  SubgraphDefinition subgraph,
  int index,
  JsonMap value, {
  required bool output,
}) async {
  final nameController = TextEditingController(
    text: value['name']?.toString() ?? '',
  );
  final defaultController = TextEditingController(
    text: value['default'] is List || value['default'] is Map
        ? jsonEncode(value['default'])
        : value['default']?.toString() ?? '',
  );
  var selectedType =
      ShowRunnerGraphEditor.subgraphParameterTypes.contains(
        value['type']?.toString(),
      )
      ? value['type'].toString()
      : 'any';
  final result = await showDialog<_SubgraphEditResult>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text('Edit ${output ? 'output' : 'parameter'}'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: selectedType,
                decoration: const InputDecoration(labelText: 'Type'),
                items: [
                  for (final type
                      in ShowRunnerGraphEditor.subgraphParameterTypes)
                    DropdownMenuItem(value: type, child: Text(type)),
                ],
                onChanged: (type) {
                  if (type != null) setState(() => selectedType = type);
                },
              ),
              if (!output) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: defaultController,
                  decoration: const InputDecoration(labelText: 'Default'),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(
              _SubgraphEditResult(
                name: nameController.text,
                type: selectedType,
                defaultValue: defaultController.text,
              ),
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
  nameController.dispose();
  defaultController.dispose();
  if (result == null) return;
  editor.updateSubgraphParameter(
    subgraph.id,
    index,
    field: 'name',
    value: result.name,
    output: output,
  );
  editor.updateSubgraphParameter(
    subgraph.id,
    index,
    field: 'type',
    value: result.type,
    output: output,
  );
  if (!output) {
    editor.updateSubgraphParameter(
      subgraph.id,
      index,
      field: 'default',
      value: result.defaultValue,
    );
  }
}

final class _SubgraphEditResult {
  const _SubgraphEditResult({
    required this.name,
    required this.type,
    required this.defaultValue,
  });

  final String name;
  final String type;
  final String defaultValue;
}

class _FrameManager extends StatelessWidget {
  const _FrameManager({required this.editor});

  final ShowRunnerGraphEditor editor;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Graph frames'),
    content: SizedBox(
      width: 420,
      child: ValueListenableBuilder<List<NodeFrame>>(
        valueListenable: editor.frames,
        builder: (context, frames, child) => ListView(
          shrinkWrap: true,
          children: [
            for (final frame in frames)
              ListTile(
                selected: editor.selectedFrameId.value == frame.id,
                leading: const Icon(Icons.crop_square),
                title: Text(frame.title),
                subtitle: Text(
                  '${frame.bounds.width.round()} x ${frame.bounds.height.round()}',
                ),
                onTap: () => editor.selectFrame(frame.id),
                trailing: Wrap(
                  spacing: 0,
                  children: [
                    IconButton(
                      tooltip: 'Rename frame',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => _renameFrame(context, editor, frame),
                    ),
                    IconButton(
                      tooltip: 'Delete frame',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () {
                        editor.selectFrame(frame.id);
                        editor.deleteSelectedFrame();
                      },
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Close'),
      ),
    ],
  );
}

Future<void> _renameFrame(
  BuildContext context,
  ShowRunnerGraphEditor editor,
  NodeFrame frame,
) async {
  final controller = TextEditingController(text: frame.title);
  final title = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Rename frame'),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Frame title'),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text),
          child: const Text('Rename'),
        ),
      ],
    ),
  );
  controller.dispose();
  if (title != null) editor.renameFrame(frame.id, title);
}

class _NodePickerDialogState extends State<_NodePickerDialog> {
  String _query = '';
  int _highlightedIndex = 0;
  List<_NodePickerEntry> _visibleEntries = const [];
  late String _category = widget.actionsOnly
      ? 'Actions'
      : widget.controlFlowOnly
      ? 'Control flow'
      : 'All';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add node'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Focus(
              onKeyEvent: (node, event) {
                if (event is! KeyDownEvent) return KeyEventResult.ignored;
                if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                  _moveHighlight(1);
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                  _moveHighlight(-1);
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.enter) {
                  _selectHighlightedEntry(context, _visibleEntries);
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  labelText: 'Search node types',
                ),
                onChanged: (value) => setState(() {
                  _query = value;
                  _highlightedIndex = 0;
                }),
                onSubmitted: (_) =>
                    _selectHighlightedEntry(context, _visibleEntries),
              ),
            ),
            const SizedBox(height: 12),
            if (!widget.actionsOnly &&
                !widget.triggersOnly &&
                !widget.controlFlowOnly)
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Category',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'All', child: Text('All')),
                  DropdownMenuItem(value: 'Triggers', child: Text('Triggers')),
                  DropdownMenuItem(value: 'Actions', child: Text('Actions')),
                  DropdownMenuItem(value: 'Data', child: Text('Data')),
                  DropdownMenuItem(value: 'Built-in', child: Text('Built-in')),
                  DropdownMenuItem(
                    value: 'Control flow',
                    child: Text('Control flow'),
                  ),
                ],
                onChanged: (value) => setState(() {
                  _category = value ?? 'All';
                  _highlightedIndex = 0;
                }),
              ),
            const SizedBox(height: 12),
            FutureBuilder<DartPluginRegistry>(
              future: widget.registryFuture,
              builder: (context, snapshot) {
                final entries = _nodePickerEntries(
                  snapshot.data,
                  enabled: true,
                );
                final query = _query.toLowerCase().trim();
                bool matches(_NodePickerEntry node) {
                  final matchesCategory = widget.triggersOnly
                      ? node.category == 'Triggers'
                      : widget.actionsOnly
                      ? node.category == 'Actions' || node.category == 'Data'
                      : widget.controlFlowOnly
                      ? node.category == 'Control flow'
                      : _category == 'All' || node.category == _category;
                  final matchesQuery =
                      query.isEmpty ||
                      '${node.label} ${node.type} ${node.pluginName ?? ''}'
                          .toLowerCase()
                          .contains(query);
                  return matchesCategory && matchesQuery;
                }

                final visibleMatches = entries.where(matches).toList();
                _visibleEntries = visibleMatches;
                final disabledMatches = _nodePickerEntries(
                  snapshot.data,
                  enabled: false,
                ).where(matches).toList();
                if (visibleMatches.isEmpty) {
                  if (disabledMatches.isNotEmpty) {
                    final names = disabledMatches
                        .map((entry) => entry.pluginName ?? entry.group)
                        .toSet()
                        .take(3)
                        .join(', ');
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Matches exist in disabled plugins: $names. Enable them in Integrations to add new nodes.',
                      ),
                    );
                  }
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No matching nodes.'),
                  );
                }
                final groups = <String, List<_NodePickerEntry>>{};
                for (final node in visibleMatches) {
                  groups
                      .putIfAbsent(
                        '${node.category}:\u0000${node.group}',
                        () => [],
                      )
                      .add(node);
                }
                return ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 240),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final group in groups.entries)
                        ExpansionTile(
                          key: ValueKey('$_category:$query:${group.key}'),
                          initiallyExpanded:
                              query.isNotEmpty || _category != 'All',
                          title: Text(group.key.split('\u0000').last),
                          subtitle: Text(group.key.split('\u0000').first),
                          children: [
                            for (final node in group.value)
                              Builder(
                                builder: (context) {
                                  final index = visibleMatches.indexOf(node);
                                  return ListTile(
                                    selected: index == _highlightedIndex,
                                    leading: Icon(node.icon),
                                    title: Text(node.label),
                                    subtitle: node.pluginName == null
                                        ? null
                                        : Text(node.pluginName!),
                                    onTap: () => _selectEntry(context, node),
                                  );
                                },
                              ),
                          ],
                        ),
                    ],
                  ),
                );
              },
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

  void _selectEntry(BuildContext context, _NodePickerEntry entry) {
    if (!entry.enabled) return;
    Navigator.of(context).pop((type: entry.type, title: entry.label));
  }

  void _selectHighlightedEntry(
    BuildContext context,
    List<_NodePickerEntry> entries,
  ) {
    if (entries.isEmpty) return;
    final index = math.min(_highlightedIndex, entries.length - 1);
    _selectEntry(context, entries[index]);
  }

  void _moveHighlight(int delta) {
    if (_visibleEntries.isEmpty) return;
    setState(() {
      _highlightedIndex = math.min(
        math.max(_highlightedIndex + delta, 0),
        _visibleEntries.length - 1,
      );
    });
  }
}

bool _isConversionEntry(String pluginId, String actionId) =>
    pluginId.toLowerCase() == 'showrunner' &&
    const {
      'convertnumbertostring',
      'convertbooleantostring',
      'convertstringtonumber',
      'convertbooleantonumber',
      'convertnumbertoboolean',
      'convertstringtoboolean',
      'convertobjecttojsonstring',
      'convertarraytojsonstring',
      'convertjsonstringtoobject',
      'convertjsonstringtoarray',
    }.contains(actionId.toLowerCase());

// Node cards use public sai_nodes builders while keeping execution state,
// search dimming, and ShowRunner titles outside the package.
Widget _buildNodeHeader(
  BuildContext context,
  NodeDataModel node,
  NodeStyle style,
  VoidCallback onToggleCollapse, {
  required ShowRunnerGraphEditor editor,
  Future<void> Function(String schemaNodeId)? onRunNode,
}) => _GraphNodeHeader(
  editor: editor,
  node: node,
  onToggleCollapse: onToggleCollapse,
  onRunNode: onRunNode,
);

void _handleNodeDoubleTap(
  BuildContext context,
  ShowRunnerGraphEditor editor,
  NodeDataModel node,
) {
  final subgraphId = editor.subgraphIdForEditor(node.id);
  if (subgraphId != null) {
    editor.enterSubgraph(subgraphId);
    return;
  }
  if (editor.isVariableNode(node.id)) {
    unawaited(_renameNode(context, editor, node));
  }
}
