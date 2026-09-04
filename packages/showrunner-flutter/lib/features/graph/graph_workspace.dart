import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:sai_nodes/sai_nodes.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_context_menu/flutter_context_menu.dart';

import '../../app/startup_health.dart';
import '../../components/data_inputs/data_input.dart';
import '../../editor/showrunner_graph_editor.dart';
import '../../plugins/registry/plugin_registry.dart';
import '../../schema/automation.dart';
import '../../services/showrunner_data_service.dart';

/// Composes the ShowRunner graph surface around the generic `sai_nodes` canvas.
///
/// The canvas handles viewport, selection, links, history, and shortcuts;
/// the widgets below handle ShowRunner palette, persistence, execution, and
/// graph-specific overlays.
class GraphWorkspace extends StatelessWidget {
  const GraphWorkspace({
    super.key,
    required this.editor,
    required this.healthFuture,
    required this.dataService,
    required this.registryFuture,
    this.onRunNode,
  });

  final ShowRunnerGraphEditor editor;
  final Future<StartupHealthSnapshot> healthFuture;
  final ShowRunnerDataService dataService;
  final Future<DartPluginRegistry> registryFuture;
  final Future<void> Function(String schemaNodeId)? onRunNode;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      _StartupHealthBanner(healthFuture: healthFuture),
      _FlutterSettingsPanel(dataService: dataService),
      _GraphNodePalette(editor: editor, registryFuture: registryFuture),
      Expanded(
        child: ValueListenableBuilder<List<String>>(
          valueListenable: editor.activeGraphPath,
          builder: (context, path, child) => Column(
            children: [
              _GraphBreadcrumb(editor: editor),
              NodeEditorToolbar(
                controller: editor.controller,
                onAutoLayout: editor.autoLayout,
              ),
              Expanded(
                child: FutureBuilder<DartPluginRegistry>(
                  future: registryFuture,
                  builder: (context, registrySnapshot) =>
                      NodeEditorShortcutsWidget(
                        controller: editor.controller,
                        onCopy: (context) =>
                            editor.copySelection(context: context),
                        onPaste: (context) =>
                            editor.pasteSelection(context: context),
                        onCut: (context) =>
                            editor.cutSelection(context: context),
                        onDuplicate: () => editor.duplicateSelectedAction(),
                        onMoveSelection: (key, {required extendSelection}) =>
                            editor.moveSelection(
                              key,
                              extendSelection: extendSelection,
                            ),
                        child: NodeEditorWidget(
                          controller: editor.controller,
                          expandToParent: true,
                          overlay: () => [
                            OverlayData(
                              top: 0,
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: _GraphFramesOverlay(editor: editor),
                            ),
                            OverlayData(
                              top: 0,
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: _ExecutionLinkOverlay(editor: editor),
                            ),
                            OverlayData(
                              top: 0,
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: _InvalidLinkOverlay(editor: editor),
                            ),
                            OverlayData(
                              top: 16,
                              left: 16,
                              child: _GraphStatus(editor: editor),
                            ),
                            OverlayData(
                              bottom: 16,
                              left: 16,
                              child: _GraphHealth(editor: editor),
                            ),
                            OverlayData(
                              top: 16,
                              right: 16,
                              child: _SelectedNodeDetails(
                                editor: editor,
                                registryFuture: registryFuture,
                              ),
                            ),
                            OverlayData(
                              bottom: 16,
                              right: 16,
                              child: _GraphMinimap(editor: editor),
                            ),
                          ],
                          headerBuilder:
                              (context, node, style, onToggleCollapse) =>
                                  _buildNodeHeader(
                                    context,
                                    node,
                                    style,
                                    onToggleCollapse,
                                    editor: editor,
                                  ),
                          fieldBuilder: _buildNodeField,
                          portBuilder: _buildNodePort,
                          nodeMenuBuilder: (context, node) =>
                              _nodeEditorContextMenu(
                                context,
                                editor,
                                node,
                                registryFuture: registryFuture,
                                onRunNode: onRunNode,
                              ),
                          editorContextMenuBuilder:
                              (context, position, defaults) =>
                                  _editorContextMenu(
                                    context: context,
                                    editor: editor,
                                    position: position,
                                    defaults: defaults,
                                    registry: registrySnapshot.data,
                                    registryFuture: registryFuture,
                                  ),
                        ),
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

// Node insertion is ShowRunner-owned because plugin manifests and persisted
// node metadata are not generic graph-editor concerns.
class _GraphNodePalette extends StatelessWidget {
  const _GraphNodePalette({required this.editor, required this.registryFuture});

  final ShowRunnerGraphEditor editor;
  final Future<DartPluginRegistry> registryFuture;

  static const _nodes = <_NodePickerEntry>[
    _NodePickerEntry(
      type: 'trigger.chatMessage',
      label: 'Chat message',
      icon: Icons.bolt,
      category: 'Triggers',
      group: 'Built-in',
    ),
    _NodePickerEntry(
      type: 'queue.addItem',
      label: 'Add to queue',
      icon: Icons.low_priority,
      category: 'Built-in',
      group: 'Built-in',
    ),
    _NodePickerEntry(
      type: 'overlay.pushChat',
      label: 'Push chat overlay',
      icon: Icons.layers_outlined,
      category: 'Built-in',
      group: 'Built-in',
    ),
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
              builder: (context) => _NodePickerDialog(
                registryFuture: registryFuture,
                recentNodeTypes: editor.recentNodeTypes.value,
              ),
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
        ValueListenableBuilder<List<GraphFrame>>(
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
            builder: (context, registrySnapshot) =>
                ValueListenableBuilder<List<String>>(
                  valueListenable: editor.recentNodeTypes,
                  builder: (context, recent, child) =>
                      ValueListenableBuilder<String>(
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
                                    : () => editor.focusSearchResult(
                                        forward: false,
                                      ),
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
                            if (query.isEmpty && recent.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              const Icon(Icons.history, size: 16),
                              for (final type in recent.take(3))
                                Padding(
                                  padding: const EdgeInsets.only(left: 4),
                                  child: ActionChip(
                                    label: Text(
                                      _nodeLabelForType(
                                        type,
                                        registrySnapshot.data,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    avatar: Icon(
                                      _nodeIconForType(
                                        type,
                                        registrySnapshot.data,
                                      ),
                                      size: 16,
                                    ),
                                    onPressed: () => _addAndConfigureNode(
                                      context,
                                      editor,
                                      type,
                                      title: _nodeLabelForType(
                                        type,
                                        registrySnapshot.data,
                                      ),
                                      registryFuture: registryFuture,
                                    ),
                                  ),
                                ),
                            ],
                          ],
                        ),
                      ),
                ),
          ),
        ),
      ],
    ),
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
  if (editor.recentNodeTypes.value.isNotEmpty) {
    entries.add(
      MenuItem<void>.submenu(
        label: const Text('Recently used'),
        icon: const Icon(Icons.history),
        items: [
          for (final type in editor.recentNodeTypes.value)
            MenuItem<void>(
              label: Text(_nodeLabelForType(type, registry)),
              icon: Icon(_nodeIconForType(type, registry)),
              onSelected: (_) => _addAndConfigureNode(
                context,
                editor,
                type,
                position: position,
                title: _nodeLabelForType(type, registry),
                registryFuture: registryFuture,
              ),
            ),
        ],
      ),
    );
  }
  if (registry != null) {
    final enabledNodes = _registeredNodeEntries(registry, enabled: true);
    final disabledNodes = _registeredNodeEntries(registry, enabled: false);
    final triggers = enabledNodes.where((node) => node.category == 'Triggers');
    final actions = enabledNodes.where((node) => node.category == 'Actions');
    final conversions = enabledNodes.where((node) => node.category == 'Data');

    if (triggers.isNotEmpty) {
      entries.add(
        MenuItem<void>.submenu(
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
        MenuItem<void>.submenu(
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
        MenuItem<void>.submenu(
          label: const Text('Action categories'),
          icon: const Icon(Icons.category_outlined),
          items: [
            for (final category in categories.entries)
              MenuItem<void>.submenu(
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
        MenuItem<void>.submenu(
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
    if (disabledNodes.isNotEmpty) {
      final disabledPlugins = disabledNodes
          .map((node) => node.pluginName ?? node.group)
          .toSet()
          .join(', ');
      entries.add(
        MenuItem<void>.submenu(
          label: const Text('Disabled plugins'),
          icon: const Icon(Icons.visibility_off_outlined),
          items: [
            MenuItem<void>(
              label: Text('Enable in Integrations: $disabledPlugins'),
              icon: const Icon(Icons.info_outline),
              enabled: false,
            ),
            const MenuDivider(),
            ..._groupedNodeMenuEntries(
              disabledNodes,
              editor,
              position,
              context: context,
              registryFuture: registryFuture,
            ),
          ],
        ),
      );
    }
  }
  final builtIns = _GraphNodePalette._nodes.where(
    (node) => node.category == 'Built-in',
  );
  if (builtIns.isNotEmpty) {
    entries.add(
      MenuItem<void>.submenu(
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
      MenuItem<void>.submenu(
        label: const Text('Add variable'),
        icon: const Icon(Icons.data_object),
        items: [
          for (final type in const ['string', 'number', 'boolean', 'color'])
            MenuItem<void>(
              label: Text('${type[0].toUpperCase()}${type.substring(1)}'),
              onSelected: (_) =>
                  editor.addVariableNodeAtScreenPosition(type, position),
            ),
        ],
      ),
    );
  }
  entries.add(
    MenuItem<void>.submenu(
      label: const Text('Add control flow'),
      icon: const Icon(Icons.account_tree_outlined),
      items: [
        for (final node in _GraphNodePalette._nodes.where(
          (node) => node.category == 'Control flow',
        ))
          MenuItem<void>(
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
      MenuItem<void>.submenu(
        label: const Text('Call subgraph'),
        icon: const Icon(Icons.functions),
        items: [
          for (final subgraph in editor.subgraphs.value)
            MenuItem<void>(
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
      MenuItem<void>(
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
    (plugin) => registry.isPluginEnabled(plugin.id) == enabled,
  )) {
    for (final action in plugin.actions) {
      final conversion = _isConversionEntry(plugin.id, action.actionId);
      entries.add(
        _NodePickerEntry(
          type: '${plugin.id}.${action.actionId}',
          label: action.displayName ?? action.actionId,
          icon: conversion ? Icons.swap_horiz : Icons.play_arrow,
          category: conversion ? 'Data' : 'Actions',
          group: conversion ? 'Conversions' : plugin.name,
          pluginId: plugin.id,
          pluginName: plugin.name,
          enabled: enabled,
        ),
      );
    }
    for (final trigger in plugin.triggers) {
      entries.add(
        _NodePickerEntry(
          type: 'trigger.${plugin.id}.${trigger.triggerId}',
          label: trigger.displayName,
          icon: Icons.bolt,
          category: 'Triggers',
          group: plugin.name,
          pluginId: plugin.id,
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
  Iterable<String> recentNodeTypes = const [],
}) {
  final entries = <_NodePickerEntry>[
    if (enabled) ..._GraphNodePalette._nodes,
    if (registry != null) ..._registeredNodeEntries(registry, enabled: enabled),
  ];
  final recentTypes = recentNodeTypes.toSet();
  if (recentTypes.isEmpty) return entries;

  final entriesByType = <String, _NodePickerEntry>{
    for (final entry in entries) entry.type: entry,
  };
  final recentEntries = <_NodePickerEntry>[];
  for (final type in recentNodeTypes) {
    final entry = entriesByType[type];
    if (entry == null) continue;
    recentEntries.add(
      _NodePickerEntry(
        type: entry.type,
        label: entry.label,
        icon: entry.icon,
        category: entry.category,
        group: 'Recently used',
        pluginId: entry.pluginId,
        pluginName: entry.pluginName,
        enabled: entry.enabled,
      ),
    );
  }
  return [
    ...recentEntries,
    ...entries.where((entry) => !recentTypes.contains(entry.type)),
  ];
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
      MenuItem<void>.submenu(
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
    MenuItem<void>(
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

IconData _nodeIconForType(String type, [DartPluginRegistry? registry]) =>
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
        .findTrigger(parts[1], parts.sublist(2).join('.'))
        ?.displayName;
  }
  if (parts.length == 2) {
    return registry.findAction(parts.first, parts.last)?.displayName;
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
    this.recentNodeTypes = const [],
    this.actionsOnly = false,
    this.triggersOnly = false,
    this.controlFlowOnly = false,
  });

  final Future<DartPluginRegistry> registryFuture;
  final List<String> recentNodeTypes;
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
      child: ValueListenableBuilder<List<GraphFrame>>(
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
  GraphFrame frame,
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
                  recentNodeTypes: widget.recentNodeTypes,
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
                  recentNodeTypes: widget.recentNodeTypes,
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
                              query.isNotEmpty ||
                              _category != 'All' ||
                              group.key.split('\u0000').last == 'Recently used',
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
}) => _GraphNodeHeader(
  editor: editor,
  node: node,
  onToggleCollapse: onToggleCollapse,
);

class _GraphNodeHeader extends StatefulWidget {
  const _GraphNodeHeader({
    required this.editor,
    required this.node,
    required this.onToggleCollapse,
  });

  final ShowRunnerGraphEditor editor;
  final NodeDataModel node;
  final VoidCallback onToggleCollapse;

  @override
  State<_GraphNodeHeader> createState() => _GraphNodeHeaderState();
}

class _GraphNodeHeaderState extends State<_GraphNodeHeader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 720),
  );
  late final Listenable _stateChanges = Listenable.merge([
    widget.editor.activeNodeIds,
    widget.editor.executionStates,
    widget.editor.nodeRevision,
    widget.editor.searchQuery,
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
      final accent = _nodeAccent(node);
      final headerStyle = node.builtHeaderStyle;
      final active = widget.editor.activeNodeIds.value.contains(node.id);
      final execution = widget.editor.executionStates.value[node.id];
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
                : accent.withValues(alpha: 0.22),
            gradient: null,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(8),
              topRight: Radius.circular(8),
            ),
            border: Border.all(
              color: active || execution != null
                  ? statusColor
                  : Colors.transparent,
              width: active ? 1.5 + pulse * 1.5 : 1,
            ),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: statusColor.withValues(alpha: 0.18 + pulse * 0.18),
                      blurRadius: 8 + pulse * 8,
                    ),
                  ]
                : null,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Row(
              children: [
                Icon(_nodeIcon(node), size: 17, color: accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.editor.customNodeTitle(node.id) ??
                        node.prototype.displayName(context),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: headerStyle.textStyle.copyWith(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                if (execution != null) ...[
                  _ExecutionBadge(execution: execution),
                  const SizedBox(width: 4),
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

Future<void> _replaceTriggerNode(
  BuildContext context,
  ShowRunnerGraphEditor editor,
  NodeDataModel node, {
  required Future<DartPluginRegistry> registryFuture,
}) async {
  final selected = await showDialog<({String type, String title})>(
    context: context,
    builder: (context) => _NodePickerDialog(
      registryFuture: registryFuture,
      recentNodeTypes: editor.recentNodeTypes.value,
      triggersOnly: true,
    ),
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
    builder: (context) => _NodePickerDialog(
      registryFuture: registryFuture,
      recentNodeTypes: editor.recentNodeTypes.value,
      actionsOnly: true,
    ),
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
      recentNodeTypes: editor.recentNodeTypes.value,
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
    builder: (context) => _NodePickerDialog(
      registryFuture: registryFuture,
      recentNodeTypes: editor.recentNodeTypes.value,
    ),
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

// Execution and invalid-link overlays are projections of runtime/schema state;
// they deliberately do not alter sai_nodes' link model.
class _ExecutionLinkOverlay extends StatefulWidget {
  const _ExecutionLinkOverlay({required this.editor});

  final ShowRunnerGraphEditor editor;

  @override
  State<_ExecutionLinkOverlay> createState() => _ExecutionLinkOverlayState();
}

class _GraphFramesOverlay extends StatelessWidget {
  const _GraphFramesOverlay({required this.editor});

  final ShowRunnerGraphEditor editor;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([
      editor.frames,
      editor.selectedFrameId,
      editor.controller.viewportOffsetNotifier,
      editor.controller.viewportZoomNotifier,
    ]),
    builder: (context, child) => LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _GraphFramesPainter(
                    frames: editor.frames.value,
                    selectedFrameId: editor.selectedFrameId.value,
                    viewportOffset: editor.controller.viewportOffset,
                    viewportZoom: editor.controller.viewportZoom,
                  ),
                ),
              ),
            ),
            for (final frame in editor.frames.value)
              _FrameInteractionLayer(
                editor: editor,
                frame: frame,
                screenBounds: _frameScreenBounds(
                  frame,
                  size,
                  editor.controller.viewportOffset,
                  editor.controller.viewportZoom,
                ),
              ),
          ],
        );
      },
    ),
  );
}

class _FrameInteractionLayer extends StatelessWidget {
  const _FrameInteractionLayer({
    required this.editor,
    required this.frame,
    required this.screenBounds,
  });

  final ShowRunnerGraphEditor editor;
  final GraphFrame frame;
  final Rect screenBounds;

  @override
  Widget build(BuildContext context) {
    if (screenBounds.width <= 0 || screenBounds.height <= 0) {
      return const SizedBox.shrink();
    }
    final headerWidth = math.min(screenBounds.width, 220.0);
    return Stack(
      children: [
        Positioned(
          left: screenBounds.left,
          top: screenBounds.top,
          width: headerWidth,
          height: 34,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => editor.selectFrame(frame.id),
            onPanStart: (_) => editor.selectFrame(frame.id),
            onPanUpdate: (details) => editor.moveFrame(
              frame.id,
              details.delta / editor.controller.viewportZoom,
            ),
            child: const SizedBox.expand(),
          ),
        ),
        Positioned(
          left: screenBounds.right - 22,
          top: screenBounds.bottom - 22,
          width: 22,
          height: 22,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => editor.selectFrame(frame.id),
            onPanStart: (_) => editor.selectFrame(frame.id),
            onPanUpdate: (details) => editor.resizeFrame(
              frame.id,
              details.delta / editor.controller.viewportZoom,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xff101010).withValues(alpha: 0.88),
                border: Border.all(color: Colors.white38),
                borderRadius: BorderRadius.circular(3),
              ),
              child: const Icon(
                Icons.north_west,
                size: 14,
                color: Colors.white70,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _GraphFramesPainter extends CustomPainter {
  const _GraphFramesPainter({
    required this.frames,
    required this.selectedFrameId,
    required this.viewportOffset,
    required this.viewportZoom,
  });

  final List<GraphFrame> frames;
  final String? selectedFrameId;
  final Offset viewportOffset;
  final double viewportZoom;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    for (final frame in frames) {
      final bounds = _frameScreenBounds(
        frame,
        size,
        viewportOffset,
        viewportZoom,
      );
      final selected = frame.id == selectedFrameId;
      final color = _parseFrameColor(frame.color);
      canvas.drawRRect(
        RRect.fromRectAndRadius(bounds, const Radius.circular(8)),
        Paint()..color = color.withValues(alpha: selected ? 0.08 : 0.035),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(bounds, const Radius.circular(8)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = selected ? 2 : 1
          ..color = color.withValues(alpha: selected ? 0.9 : 0.42),
      );
      final label = TextPainter(
        text: TextSpan(
          text: frame.title,
          style: TextStyle(
            color: color.withValues(alpha: selected ? 0.95 : 0.7),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '...',
      )..layout(maxWidth: math.max(40, bounds.width - 16));
      label.paint(canvas, Offset(bounds.left + 8, bounds.top + 6));
    }
  }

  @override
  bool shouldRepaint(_GraphFramesPainter oldDelegate) =>
      oldDelegate.frames != frames ||
      oldDelegate.selectedFrameId != selectedFrameId ||
      oldDelegate.viewportOffset != viewportOffset ||
      oldDelegate.viewportZoom != viewportZoom;
}

Rect _frameScreenBounds(
  GraphFrame frame,
  Size size,
  Offset viewportOffset,
  double viewportZoom,
) => Rect.fromLTRB(
  size.width / 2 + (frame.bounds.left + viewportOffset.dx) * viewportZoom,
  size.height / 2 + (frame.bounds.top + viewportOffset.dy) * viewportZoom,
  size.width / 2 + (frame.bounds.right + viewportOffset.dx) * viewportZoom,
  size.height / 2 + (frame.bounds.bottom + viewportOffset.dy) * viewportZoom,
);

Color _parseFrameColor(String value) {
  final normalized = value.replaceFirst('#', '').trim();
  final hex = normalized.length == 6 ? 'ff$normalized' : normalized;
  final parsed = int.tryParse(hex, radix: 16);
  return parsed == null ? const Color(0xff64b5f6) : Color(parsed);
}

class _ExecutionLinkOverlayState extends State<_ExecutionLinkOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animationController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: AnimatedBuilder(
      animation: Listenable.merge([
        widget.editor.controller,
        widget.editor.activeNodeIds,
        widget.editor.executionStates,
        widget.editor.controller.viewportOffsetNotifier,
        widget.editor.controller.viewportZoomNotifier,
        _animationController,
      ]),
      builder: (context, child) => CustomPaint(
        painter: _ExecutionLinkPainter(
          links: widget.editor.controller.linksAsList,
          nodes: widget.editor.controller.nodes,
          executionStates: widget.editor.executionStates.value,
          progress: _animationController.value,
          viewportOffset: widget.editor.controller.viewportOffset,
          viewportZoom: widget.editor.controller.viewportZoom,
        ),
        size: Size.infinite,
      ),
    ),
  );
}

class _ExecutionLinkPainter extends CustomPainter {
  const _ExecutionLinkPainter({
    required this.links,
    required this.nodes,
    required this.executionStates,
    required this.progress,
    required this.viewportOffset,
    required this.viewportZoom,
  });

  final List<LinkDataModel> links;
  final Map<String, NodeDataModel> nodes;
  final Map<String, GraphNodeExecutionVisual> executionStates;
  final double progress;
  final Offset viewportOffset;
  final double viewportZoom;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    for (final link in links) {
      final source = nodes[link.endpoints.sourceNodeId];
      final target = nodes[link.endpoints.targetNodeId];
      final sourcePort = source?.ports[link.endpoints.sourcePortId];
      final targetPort = target?.ports[link.endpoints.targetPortId];
      if (source == null ||
          target == null ||
          sourcePort == null ||
          targetPort == null) {
        continue;
      }
      final sourceState = executionStates[source.id]?.status;
      final targetState = executionStates[target.id]?.status;
      final isActive =
          sourceState == GraphNodeExecutionStatus.success &&
          targetState == GraphNodeExecutionStatus.running;
      final isCompleted =
          sourceState == GraphNodeExecutionStatus.success &&
          targetState == GraphNodeExecutionStatus.success;
      final isFailed = targetState == GraphNodeExecutionStatus.error;
      if (!isActive && !isCompleted && !isFailed) continue;

      final path = _pathFor(
        _screenPoint(source.offset + sourcePort.offset, size),
        _screenPoint(target.offset + targetPort.offset, size),
      );
      final color = isFailed
          ? const Color(0xfff87171)
          : isActive
          ? const Color(0xff38bdf8)
          : const Color(0xff4ade80);
      if (isActive) {
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 8
            ..color = color.withValues(alpha: 0.14)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
        );
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = isActive ? 3.5 : 2.5
          ..color = color.withValues(alpha: isActive ? 0.98 : 0.72),
      );
      if (isActive) {
        final dot = _cubicPoint(path, progress);
        canvas.drawCircle(dot, 5, Paint()..color = color);
        canvas.drawCircle(
          dot,
          9,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = color.withValues(alpha: 0.28),
        );
      }
    }
  }

  Offset _screenPoint(Offset world, Size size) => Offset(
    size.width / 2 + (world.dx + viewportOffset.dx) * viewportZoom,
    size.height / 2 + (world.dy + viewportOffset.dy) * viewportZoom,
  );

  Path _pathFor(Offset source, Offset target) {
    final controlOffset = math.min((target.dx - source.dx).abs() / 2, 400);
    return Path()
      ..moveTo(source.dx, source.dy)
      ..cubicTo(
        source.dx + controlOffset,
        source.dy,
        target.dx - controlOffset,
        target.dy,
        target.dx,
        target.dy,
      );
  }

  Offset _cubicPoint(Path path, double value) {
    final metrics = path.computeMetrics().first;
    return metrics.getTangentForOffset(metrics.length * value)!.position;
  }

  @override
  bool shouldRepaint(_ExecutionLinkPainter oldDelegate) =>
      oldDelegate.links != links ||
      oldDelegate.nodes != nodes ||
      oldDelegate.executionStates != executionStates ||
      oldDelegate.progress != progress ||
      oldDelegate.viewportOffset != viewportOffset ||
      oldDelegate.viewportZoom != viewportZoom;
}

class _InvalidLinkOverlay extends StatelessWidget {
  const _InvalidLinkOverlay({required this.editor});

  final ShowRunnerGraphEditor editor;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([
      editor.controller,
      editor.nodeRevision,
      editor.activeGraphPath,
    ]),
    builder: (context, child) => CustomPaint(
      painter: _InvalidLinkPainter(
        flowEdges: editor.invalidFlowEdges,
        dataWires: editor.invalidDataWires,
        nodes: editor.controller.nodes,
        editor: editor,
        viewportOffset: editor.controller.viewportOffset,
        viewportZoom: editor.controller.viewportZoom,
      ),
      size: Size.infinite,
    ),
  );
}

class _InvalidLinkPainter extends CustomPainter {
  const _InvalidLinkPainter({
    required this.flowEdges,
    required this.dataWires,
    required this.nodes,
    required this.editor,
    required this.viewportOffset,
    required this.viewportZoom,
  });

  final List<GraphEdge> flowEdges;
  final List<DataWire> dataWires;
  final Map<String, NodeDataModel> nodes;
  final ShowRunnerGraphEditor editor;
  final Offset viewportOffset;
  final double viewportZoom;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = const Color(0xfff87171).withValues(alpha: 0.92);
    for (final edge in flowEdges) {
      final path = _flowPath(edge, size);
      if (path != null) _drawDashedPath(canvas, path, paint);
    }
    for (final wire in dataWires) {
      final path = _dataPath(wire, size);
      if (path != null) _drawDashedPath(canvas, path, paint);
    }
  }

  Path? _flowPath(GraphEdge edge, Size size) {
    final source = _nodeForSchemaId(edge.from);
    final target = _nodeForSchemaId(edge.to);
    if (source == null || target == null) return null;
    final sourcePoint = _screenPoint(
      source.offset +
          (_port(
                source,
                edge.port ?? 'completed',
                output: true,
                data: false,
              )?.offset ??
              const Offset(180, 42)),
      size,
    );
    final targetPoint = _screenPoint(
      target.offset +
          (_port(target, 'exec', output: false, data: false)?.offset ??
              const Offset(0, 42)),
      size,
    );
    return _pathFor(sourcePoint, targetPoint);
  }

  Path? _dataPath(DataWire wire, Size size) {
    final source = _nodeForSchemaId(wire.fromNode);
    final target = _nodeForSchemaId(wire.toNode);
    if (source == null || target == null) return null;
    final sourcePoint = _screenPoint(
      source.offset +
          (_port(source, wire.fromPort, output: true, data: true)?.offset ??
              const Offset(180, 42)),
      size,
    );
    final targetPoint = _screenPoint(
      target.offset +
          (_port(target, wire.toPort, output: false, data: true)?.offset ??
              const Offset(0, 42)),
      size,
    );
    return _pathFor(sourcePoint, targetPoint);
  }

  NodeDataModel? _nodeForSchemaId(String schemaId) {
    final editorId = editor.editorNodeIdForSchema(schemaId);
    return editorId == null ? null : nodes[editorId];
  }

  PortDataModel? _port(
    NodeDataModel node,
    String portId, {
    required bool output,
    required bool data,
  }) {
    final expectedDirection = output
        ? PortDirection.output
        : PortDirection.input;
    final expectedType = data ? PortType.data : PortType.control;
    final exact = node.ports[portId];
    if (exact?.prototype.direction == expectedDirection &&
        exact?.prototype.type == expectedType) {
      return exact;
    }
    return node.ports.values
        .where(
          (port) =>
              port.prototype.direction == expectedDirection &&
              port.prototype.type == expectedType,
        )
        .firstOrNull;
  }

  Offset _screenPoint(Offset world, Size size) => Offset(
    size.width / 2 + (world.dx + viewportOffset.dx) * viewportZoom,
    size.height / 2 + (world.dy + viewportOffset.dy) * viewportZoom,
  );

  Path _pathFor(Offset source, Offset target) {
    final controlOffset = math.min((target.dx - source.dx).abs() / 2, 400);
    return Path()
      ..moveTo(source.dx, source.dy)
      ..cubicTo(
        source.dx + controlOffset,
        source.dy,
        target.dx - controlOffset,
        target.dy,
        target.dx,
        target.dy,
      );
  }

  void _drawDashedPath(Canvas canvas, Path path, Paint paint) {
    for (final metric in path.computeMetrics()) {
      for (var distance = 0.0; distance < metric.length; distance += 12) {
        canvas.drawPath(
          metric.extractPath(distance, math.min(distance + 7, metric.length)),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_InvalidLinkPainter oldDelegate) =>
      oldDelegate.flowEdges != flowEdges ||
      oldDelegate.dataWires != dataWires ||
      oldDelegate.nodes != nodes ||
      oldDelegate.viewportOffset != viewportOffset ||
      oldDelegate.viewportZoom != viewportZoom;
}

Widget _buildNodeField(
  BuildContext context,
  FieldDataModel field,
  NodeStyle style,
) {
  final fieldStyle = field.prototype.style;
  return Container(
    padding: fieldStyle.padding,
    decoration: fieldStyle.decoration.copyWith(
      color: const Color(0xff10181d),
      border: Border.all(color: const Color(0xff33434b)),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            field.prototype.displayName(context),
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 56,
          child: field.prototype.visualizerBuilder(field.data),
        ),
      ],
    ),
  );
}

Widget _buildNodePort(
  BuildContext context,
  PortDataModel port,
  NodeStyle style,
) {
  final isInput = port.prototype.direction == PortDirection.input;
  final color = port.state.isHovered ? Colors.white : port.style.color;
  final label = Text(
    port.prototype.displayName(context),
    overflow: TextOverflow.ellipsis,
    textAlign: isInput ? TextAlign.left : TextAlign.right,
    style: const TextStyle(color: Colors.white70, fontSize: 11),
  );
  final marker = Container(
    width: 9,
    height: 9,
    decoration: BoxDecoration(
      color: port.prototype.type == PortType.data ? Colors.transparent : color,
      shape: BoxShape.circle,
      border: Border.all(color: color, width: 1.5),
    ),
  );
  return Row(
    key: port.key,
    mainAxisSize: MainAxisSize.min,
    children: isInput
        ? [marker, const SizedBox(width: 6), Flexible(child: label)]
        : [Flexible(child: label), const SizedBox(width: 6), marker],
  );
}

Color _nodeAccent(NodeDataModel node) => switch (node.prototype.idName) {
  'trigger.chatMessage' => const Color(0xff60a5fa),
  'queue.addItem' => const Color(0xfff59e0b),
  'overlay.pushChat' => const Color(0xff34d399),
  _ => const Color(0xff94a3b8),
};

IconData _nodeIcon(NodeDataModel node) => switch (node.prototype.idName) {
  'trigger.chatMessage' => Icons.bolt,
  'queue.addItem' => Icons.low_priority,
  'overlay.pushChat' => Icons.layers_outlined,
  _ => Icons.extension_outlined,
};

// The remaining widgets are graph-domain panels layered over the canvas.
class _StartupHealthBanner extends StatelessWidget {
  const _StartupHealthBanner({required this.healthFuture});

  final Future<StartupHealthSnapshot> healthFuture;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<StartupHealthSnapshot>(
      future: healthFuture,
      builder: (context, snapshot) {
        final result = snapshot.data;
        final state = result?.state ?? StartupHealthState.loading;
        final health = result?.health;
        final (label, color, icon) = switch (state) {
          StartupHealthState.loading => (
            'Checking local data',
            Colors.blueGrey,
            Icons.sync,
          ),
          StartupHealthState.ready => (
            'Local data ready',
            Colors.teal,
            Icons.check_circle,
          ),
          StartupHealthState.offline => (
            'Local data incomplete',
            Colors.orange,
            Icons.cloud_off,
          ),
          StartupHealthState.error => (
            'Local data error',
            Colors.redAccent,
            Icons.error_outline,
          ),
        };
        final details = health == null
            ? result?.error?.toString() ?? 'Waiting for the data service.'
            : '${health.settingsFileCount} settings files; '
                  '${health.stateDirectoryExists ? 'state directory found' : 'state directory missing'}';
        return Container(
          width: double.infinity,
          color: color.withValues(alpha: 0.14),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(color: color, fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(details, overflow: TextOverflow.ellipsis)),
            ],
          ),
        );
      },
    );
  }
}

class _FlutterSettingsPanel extends StatefulWidget {
  const _FlutterSettingsPanel({required this.dataService});

  final ShowRunnerDataService dataService;

  @override
  State<_FlutterSettingsPanel> createState() => _FlutterSettingsPanelState();
}

class _FlutterSettingsPanelState extends State<_FlutterSettingsPanel> {
  static const _pluginId = 'showrunner-flutter';
  static const _settingId = 'migrationProbeEnabled';

  bool _enabled = false;
  bool _loading = true;
  bool _saving = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final settings = await widget.dataService.loadPluginSettings(_pluginId);
      if (!mounted) return;
      setState(() {
        _enabled = settings[_settingId] == true;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _update(bool value) async {
    final previous = _enabled;
    setState(() {
      _enabled = value;
      _saving = true;
      _error = null;
    });
    try {
      await widget.dataService.updatePluginSetting(
        _pluginId,
        _settingId,
        value,
      );
      if (!mounted) return;
      setState(() => _saving = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _enabled = previous;
        _saving = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final message = _error == null
        ? 'Saved in user/settings/showrunner-flutter.yaml'
        : 'Unable to load or save this setting';
    return Material(
      color: const Color(0xff182126),
      child: ListTile(
        dense: true,
        leading: Icon(
          Icons.tune,
          color: Theme.of(context).colorScheme.secondary,
        ),
        title: const Text('Flutter migration settings'),
        subtitle: Text(message),
        trailing: _loading || _saving
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Switch(
                value: _enabled,
                onChanged: _error == null ? _update : null,
              ),
      ),
    );
  }
}

class _GraphStatus extends StatelessWidget {
  const _GraphStatus({required this.editor});

  final ShowRunnerGraphEditor editor;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        editor.controller,
        editor.activeNodeIds,
        editor.executionStates,
        editor.graphFeedback,
      ]),
      builder: (context, child) {
        final states = editor.executionStates.value.values;
        final running = states
            .where((state) => state.status == GraphNodeExecutionStatus.running)
            .length;
        final completed = states
            .where((state) => state.status == GraphNodeExecutionStatus.success)
            .length;
        final failed = states
            .where((state) => state.status == GraphNodeExecutionStatus.error)
            .length;
        final feedback = editor.graphFeedback.value;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xff182126).withValues(alpha: 0.94),
            border: Border.all(
              color: feedback == null
                  ? const Color(0xff2dd4bf)
                  : const Color(0xfff87171),
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${editor.controller.nodes.length} nodes  /  '
                    '${editor.controller.project.projectData.links.length} links  '
                    '|  $running running  $completed done  $failed failed',
                    style: const TextStyle(
                      color: Color(0xffb8f3e8),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (feedback != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Icon(
                            Icons.error_outline,
                            color: Color(0xfffca5a5),
                            size: 15,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            feedback,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xfffecaca),
                              fontSize: 11,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Dismiss graph feedback',
                          onPressed: () => editor.graphFeedback.value = null,
                          icon: const Icon(Icons.close, size: 15),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                            width: 22,
                            height: 22,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GraphHealth extends StatelessWidget {
  const _GraphHealth({required this.editor});

  final ShowRunnerGraphEditor editor;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: editor.controller,
    builder: (context, child) {
      final issues = editor.currentGraphIssues();
      final healthy = issues.isEmpty;
      return DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xff182126).withValues(alpha: 0.94),
          border: Border.all(
            color: healthy ? const Color(0xff4ade80) : const Color(0xfffbbf24),
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: TextButton.icon(
          onPressed: () => _showGraphHealth(context, issues),
          icon: Icon(
            healthy ? Icons.check_circle_outline : Icons.warning_amber,
            color: healthy ? const Color(0xff86efac) : const Color(0xfffde68a),
            size: 16,
          ),
          label: Text(
            healthy
                ? 'Graph healthy'
                : '${issues.length} graph issue${issues.length == 1 ? '' : 's'}',
            style: TextStyle(
              color: healthy
                  ? const Color(0xffbbf7d0)
                  : const Color(0xfffef3c7),
              fontSize: 12,
            ),
          ),
        ),
      );
    },
  );

  Future<void> _showGraphHealth(
    BuildContext context,
    List<String> issues,
  ) async {
    final invalidFlowEdges = editor.invalidFlowEdges;
    final invalidDataWires = editor.invalidDataWires;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Graph health'),
        content: SizedBox(
          width: 520,
          child:
              issues.isEmpty &&
                  invalidFlowEdges.isEmpty &&
                  invalidDataWires.isEmpty
              ? const Text('No structural issues were found.')
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final issue in issues)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.warning_amber, size: 18),
                        title: Text(issue),
                      ),
                    if (invalidFlowEdges.isNotEmpty) ...[
                      const Divider(),
                      const ListTile(
                        dense: true,
                        leading: Icon(Icons.alt_route, size: 18),
                        title: Text('Stale flow links'),
                      ),
                      for (final edge in invalidFlowEdges)
                        ListTile(
                          dense: true,
                          title: Text(edge.id),
                          subtitle: Text(
                            '${edge.from} -> ${edge.to} '
                            '(${edge.port ?? 'completed'})',
                          ),
                          trailing: IconButton(
                            tooltip: 'Discard stale flow link',
                            onPressed: () {
                              editor.discardInvalidFlowEdge(edge.id);
                              Navigator.of(context).pop();
                            },
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ),
                    ],
                    if (invalidDataWires.isNotEmpty) ...[
                      const Divider(),
                      const ListTile(
                        dense: true,
                        leading: Icon(Icons.data_object, size: 18),
                        title: Text('Stale data links'),
                      ),
                      for (final wire in invalidDataWires)
                        ListTile(
                          dense: true,
                          title: Text(wire.id),
                          subtitle: Text(
                            '${wire.fromNode}.${wire.fromPort} -> '
                            '${wire.toNode}.${wire.toPort}',
                          ),
                          trailing: IconButton(
                            tooltip: 'Discard stale data link',
                            onPressed: () {
                              editor.discardInvalidDataWire(wire.id);
                              Navigator.of(context).pop();
                            },
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ),
                    ],
                  ],
                ),
        ),
        actions: [
          if (issues.isNotEmpty)
            TextButton.icon(
              onPressed: () {
                editor.repairCurrentGraph();
                Navigator.of(context).pop();
              },
              icon: const Icon(Icons.build_circle_outlined),
              label: const Text('Repair graph'),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _SelectedNodeDetails extends StatelessWidget {
  const _SelectedNodeDetails({
    required this.editor,
    required this.registryFuture,
  });

  final ShowRunnerGraphEditor editor;
  final Future<DartPluginRegistry> registryFuture;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([
      editor.controller,
      editor.frames,
      editor.nodeRevision,
      editor.controller.viewportOffsetNotifier,
      editor.controller.viewportZoomNotifier,
    ]),
    builder: (context, child) {
      final selected = editor.controller.selectedNodeIds
          .map((id) => editor.controller.nodes[id])
          .whereType<NodeDataModel>()
          .toList();
      final selectedLinks = editor.controller.selectedLinkIds;
      final selectedFrame = editor.frames.value
          .where((frame) => frame.id == editor.selectedFrameId.value)
          .firstOrNull;
      if (selectedFrame != null) {
        return _FrameDetailsPanel(editor: editor, frame: selectedFrame);
      }
      if (selected.isEmpty && selectedLinks.isEmpty) {
        return const SizedBox.shrink();
      }
      if (selected.isEmpty) {
        return _panel('Selection', '${selectedLinks.length} links selected');
      }
      if (selected.length > 1) {
        return _panel('Selection', '${selected.length} nodes selected');
      }
      final node = selected.single;
      final fields = node.fields.values
          .map(
            (field) => '${field.prototype.displayName(context)}: ${field.data}',
          )
          .join('\n');
      final resultMapping = editor.nodeResultMapping(node.id);
      final resultDetails = resultMapping.entries
          .map((entry) => '${entry.key} -> ${entry.value}')
          .join('\n');
      final details = [
        if (fields.isNotEmpty) fields,
        if (resultDetails.isNotEmpty) 'Returns\n$resultDetails',
      ].join('\n');
      return _panel(
        node.prototype.displayName(context),
        details.isEmpty ? 'No editable fields' : details,
        action: OutlinedButton.icon(
          onPressed: () => _editNodeConfiguration(
            context,
            editor,
            node,
            registryFuture: registryFuture,
          ),
          icon: const Icon(Icons.tune, size: 16),
          label: const Text('Edit configuration'),
        ),
      );
    },
  );
}

class _FrameDetailsPanel extends StatefulWidget {
  const _FrameDetailsPanel({required this.editor, required this.frame});

  final ShowRunnerGraphEditor editor;
  final GraphFrame frame;

  @override
  State<_FrameDetailsPanel> createState() => _FrameDetailsPanelState();
}

class _FrameDetailsPanelState extends State<_FrameDetailsPanel> {
  late final TextEditingController _titleController;
  late final TextEditingController _colorController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.frame.title);
    _colorController = TextEditingController(text: widget.frame.color);
  }

  @override
  void didUpdateWidget(covariant _FrameDetailsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.frame.id != widget.frame.id) {
      _titleController.text = widget.frame.title;
      _colorController.text = widget.frame.color;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _colorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final memberCount = widget.frame.nodeIds
        .where((id) => widget.editor.editorNodeIdForSchema(id) != null)
        .length;
    final selectionCount = widget.editor.controller.selectedNodeIds.length;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xff182126).withValues(alpha: 0.96),
        border: Border.all(color: _parseFrameColor(widget.frame.color)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Annotation block',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close annotation details',
                    onPressed: () {
                      widget.editor.selectFrame(null);
                      widget.editor.controller.clearSelection();
                    },
                    icon: const Icon(Icons.close, size: 16),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 24,
                      height: 24,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Label',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) =>
                    widget.editor.renameFrame(widget.frame.id, value),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _colorController,
                decoration: InputDecoration(
                  isDense: true,
                  labelText: 'Color',
                  border: const OutlineInputBorder(),
                  prefixIcon: Padding(
                    padding: const EdgeInsets.all(10),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: _parseFrameColor(widget.frame.color),
                        shape: BoxShape.circle,
                      ),
                      child: const SizedBox(width: 12, height: 12),
                    ),
                  ),
                ),
                onChanged: (value) =>
                    widget.editor.updateFrameColor(widget.frame.id, value),
              ),
              const SizedBox(height: 8),
              Text(
                '$memberCount node${memberCount == 1 ? '' : 's'} in block',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  OutlinedButton.icon(
                    onPressed: selectionCount == 0
                        ? null
                        : widget.editor.addSelectionToSelectedFrame,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add selection'),
                  ),
                  OutlinedButton.icon(
                    onPressed: selectionCount == 0 || memberCount == 0
                        ? null
                        : widget.editor.removeSelectionFromSelectedFrame,
                    icon: const Icon(Icons.remove, size: 16),
                    label: const Text('Remove'),
                  ),
                  OutlinedButton.icon(
                    onPressed: memberCount == 0
                        ? null
                        : widget.editor.clearSelectedFrameNodes,
                    icon: const Icon(Icons.clear, size: 16),
                    label: const Text('Clear nodes'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    widget.editor.deleteSelectedFrame();
                    widget.editor.controller.clearSelection();
                  },
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('Delete block'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xffff8a80),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _panel(String title, String details, {Widget? action}) => DecoratedBox(
  decoration: BoxDecoration(
    color: const Color(0xff182126).withValues(alpha: 0.94),
    border: Border.all(color: const Color(0xff60a5fa)),
    borderRadius: BorderRadius.circular(6),
  ),
  child: ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 260),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            details,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          if (action != null) ...[const SizedBox(height: 10), action],
        ],
      ),
    ),
  ),
);

// Configuration stays outside sai_nodes because schemas, defaults, and
// persisted plugin payloads belong to ShowRunner's domain contract.
Future<void> _editNodeConfiguration(
  BuildContext context,
  ShowRunnerGraphEditor editor,
  NodeDataModel node, {
  required Future<DartPluginRegistry> registryFuture,
}) async {
  if (editor.isVariableNode(node.id)) {
    final data = await showDialog<JsonMap>(
      context: context,
      builder: (context) => _VariableNodeConfigDialog(
        title: 'Configure ${editor.nodeTitle(node.id)}',
        type: editor.variableNodeType(node.id) ?? 'string',
        initialValue: editor.variableNodeData(node.id),
      ),
    );
    if (data != null) {
      editor.updateVariableNodeName(node.id, data['name']?.toString() ?? '');
      editor.updateVariableNodeValue(node.id, data['value']);
    }
    return;
  }
  if (ShowRunnerGraphEditor.isControlFlowType(node.prototype.idName)) {
    final data = await showDialog<JsonMap>(
      context: context,
      builder: (context) => _ControlNodeConfigDialog(
        title: 'Configure ${editor.nodeTitle(node.id)}',
        nodeType: node.prototype.idName,
        initialValue: editor.nodeData(node.id),
      ),
    );
    if (data != null) editor.updateControlNodeData(node.id, data);
    return;
  }
  final registry = await registryFuture;
  if (!context.mounted) return;
  if (editor.isTriggerNode(node.id)) {
    final trigger = _triggerDefinition(editor, registry, node);
    final config = editor.nodeConfig(node.id);
    final schema = _triggerConfigurationSchema(trigger, config);
    final result = await showDialog<_TriggerConfigurationResult>(
      context: context,
      builder: (context) => _TriggerConfigurationDialog(
        title: 'Configure ${editor.nodeTitle(node.id)}',
        schema: schema,
        initialValue: config,
        stop: editor.nodeData(node.id)['stop'] == true,
      ),
    );
    if (!context.mounted || result == null) return;
    editor.updateTriggerNodeData(
      node.id,
      config: result.config,
      stop: result.stop,
    );
    return;
  }
  final actionDefinition = _actionDefinition(editor, registry, node);
  final schema = _configurationSchema(editor, registry, node);
  if (schema != null) {
    final config = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _SchemaConfigurationDialog(
        title: 'Configure ${editor.nodeTitle(node.id)}',
        schema: schema,
        initialValue: editor.nodeConfig(node.id),
      ),
    );
    if (config != null) {
      editor.updateNodeConfig(node.id, config);
      if (!context.mounted) return;
      await _editActionResultMapping(
        context,
        editor,
        node,
        actionDefinition?.resultSchema,
      );
    }
    return;
  }
  final configController = TextEditingController(
    text: const JsonEncoder.withIndent(
      '  ',
    ).convert(editor.nodeConfig(node.id)),
  );
  final config = await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Configure ${editor.nodeTitle(node.id)}'),
      content: SizedBox(
        width: 520,
        child: TextField(
          controller: configController,
          autofocus: true,
          minLines: 8,
          maxLines: 18,
          decoration: const InputDecoration(
            labelText: 'JSON configuration',
            alignLabelWithHint: true,
            border: OutlineInputBorder(),
          ),
          style: const TextStyle(fontFamily: 'monospace'),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            try {
              final decoded = jsonDecode(configController.text);
              if (decoded is! Map) {
                throw const FormatException('Expected JSON object');
              }
              Navigator.of(context).pop(Map<String, dynamic>.from(decoded));
            } on FormatException catch (error) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(error.message)));
            }
          },
          child: const Text('Apply'),
        ),
      ],
    ),
  );
  configController.dispose();
  if (config != null) {
    editor.updateNodeConfig(node.id, config);
    if (!context.mounted) return;
    await _editActionResultMapping(
      context,
      editor,
      node,
      actionDefinition?.resultSchema,
    );
  }
}

class _VariableNodeConfigDialog extends StatefulWidget {
  const _VariableNodeConfigDialog({
    required this.title,
    required this.type,
    required this.initialValue,
  });

  final String title;
  final String type;
  final JsonMap initialValue;

  @override
  State<_VariableNodeConfigDialog> createState() =>
      _VariableNodeConfigDialogState();
}

class _VariableNodeConfigDialogState extends State<_VariableNodeConfigDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _valueController;
  late bool _booleanValue;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.initialValue['name']?.toString() ?? '',
    );
    final initialValue = widget.initialValue['value'];
    _valueController = TextEditingController(
      text: initialValue?.toString() ?? '',
    );
    _booleanValue = initialValue is bool ? initialValue : true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _valueController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 360,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          if (widget.type == 'boolean')
            DropdownButtonFormField<bool>(
              initialValue: _booleanValue,
              decoration: const InputDecoration(
                labelText: 'Value',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: true, child: Text('true')),
                DropdownMenuItem(value: false, child: Text('false')),
              ],
              onChanged: (value) => setState(() {
                _booleanValue = value ?? true;
              }),
            )
          else
            TextField(
              controller: _valueController,
              keyboardType: widget.type == 'number'
                  ? const TextInputType.numberWithOptions(decimal: true)
                  : TextInputType.text,
              decoration: InputDecoration(
                labelText: 'Value',
                hintText: widget.type == 'color' ? '#ffffff' : null,
                border: const OutlineInputBorder(),
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
      FilledButton(
        onPressed: () {
          final value = widget.type == 'boolean'
              ? _booleanValue
              : widget.type == 'number'
              ? num.tryParse(_valueController.text) ?? 0
              : _valueController.text;
          Navigator.of(context).pop(<String, dynamic>{
            'name': _nameController.text,
            'value': value,
          });
        },
        child: const Text('Apply'),
      ),
    ],
  );
}

class _ControlNodeConfigDialog extends StatefulWidget {
  const _ControlNodeConfigDialog({
    required this.title,
    required this.nodeType,
    required this.initialValue,
  });

  final String title;
  final String nodeType;
  final JsonMap initialValue;

  @override
  State<_ControlNodeConfigDialog> createState() =>
      _ControlNodeConfigDialogState();
}

class _ControlNodeConfigDialogState extends State<_ControlNodeConfigDialog> {
  late final TextEditingController _conditionVariableController;
  late final TextEditingController _conditionCompareController;
  late final TextEditingController _counterController;
  late final TextEditingController _startController;
  late final TextEditingController _endController;
  late final TextEditingController _stepController;
  late final TextEditingController _collectionController;
  late final TextEditingController _switchExpressionController;
  late final TextEditingController _maxIterationsController;
  late String _conditionMode;
  late List<Map<String, dynamic>> _cases;
  late List<TextEditingController> _caseControllers;

  @override
  void initState() {
    super.initState();
    final condition = widget.initialValue['condition'];
    _conditionMode = _expressionMode(condition);
    _conditionVariableController = TextEditingController(
      text: _expressionVariable(condition),
    );
    _conditionCompareController = TextEditingController(
      text: _expressionCompareValue(condition),
    );
    _counterController = TextEditingController(
      text: widget.initialValue['variable']?.toString() ?? 'i',
    );
    _startController = TextEditingController(
      text: _literalNumber(widget.initialValue['start']).toString(),
    );
    _endController = TextEditingController(
      text: _literalNumber(widget.initialValue['end'], 10).toString(),
    );
    _stepController = TextEditingController(
      text: _literalNumber(widget.initialValue['step'], 1).toString(),
    );
    _collectionController = TextEditingController(
      text: _expressionVariable(widget.initialValue['collection']),
    );
    _switchExpressionController = TextEditingController(
      text: _expressionVariable(widget.initialValue['expression']),
    );
    _maxIterationsController = TextEditingController(
      text: (widget.initialValue['maxIterations'] ?? 1000).toString(),
    );
    final rawCases = widget.initialValue['cases'];
    _cases = rawCases is List
        ? rawCases
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList()
        : <Map<String, dynamic>>[];
    _caseControllers = [
      for (final item in _cases)
        TextEditingController(text: item['value']?.toString() ?? ''),
    ];
  }

  @override
  void dispose() {
    _conditionVariableController.dispose();
    _conditionCompareController.dispose();
    _counterController.dispose();
    _startController.dispose();
    _endController.dispose();
    _stepController.dispose();
    _collectionController.dispose();
    _switchExpressionController.dispose();
    _maxIterationsController.dispose();
    for (final controller in _caseControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fields = switch (widget.nodeType) {
      'if' || 'while' => <Widget>[
        _expressionModeField(),
        if (_conditionMode == 'variable' || _conditionMode == 'equals')
          _textField(
            controller: _conditionVariableController,
            label: 'Variable',
            hint: 'message.approved',
          ),
        if (_conditionMode == 'equals')
          _textField(
            controller: _conditionCompareController,
            label: 'Equals',
            hint: 'approved',
          ),
        _expressionSummary(),
        if (widget.nodeType == 'while')
          _textField(
            controller: _maxIterationsController,
            label: 'Max iterations',
            keyboardType: TextInputType.number,
          ),
      ],
      'for' => <Widget>[
        _textField(controller: _counterController, label: 'Counter'),
        _textField(
          controller: _startController,
          label: 'Start',
          keyboardType: TextInputType.number,
        ),
        _textField(
          controller: _endController,
          label: 'End',
          keyboardType: TextInputType.number,
        ),
        _textField(
          controller: _stepController,
          label: 'Step',
          keyboardType: TextInputType.number,
        ),
      ],
      'forEach' => <Widget>[
        _textField(controller: _counterController, label: 'Item variable'),
        _textField(
          controller: _collectionController,
          label: 'Collection variable',
          hint: 'items',
        ),
        _expressionSummary(collection: true),
      ],
      'switch' => <Widget>[
        _textField(
          controller: _switchExpressionController,
          label: 'Switch variable',
          hint: 'platform',
        ),
        _switchExpressionSummary(),
        _switchCases(),
      ],
      _ => <Widget>[
        const Text('This control node does not have editable fields yet.'),
      ],
    };
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < fields.length; index++) ...[
                if (index > 0) const SizedBox(height: 12),
                fields[index],
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_result()),
          child: const Text('Apply'),
        ),
      ],
    );
  }

  Widget _expressionModeField() => DropdownButtonFormField<String>(
    initialValue: _conditionMode,
    decoration: const InputDecoration(
      labelText: 'Condition',
      border: OutlineInputBorder(),
    ),
    items: const [
      DropdownMenuItem(value: 'true', child: Text('Always true')),
      DropdownMenuItem(value: 'false', child: Text('Always false')),
      DropdownMenuItem(value: 'variable', child: Text('Variable is truthy')),
      DropdownMenuItem(value: 'equals', child: Text('Variable equals value')),
    ],
    onChanged: (value) => setState(() => _conditionMode = value ?? 'true'),
  );

  Widget _expressionSummary({bool collection = false}) {
    final variable = collection
        ? _collectionController.text.trim()
        : _conditionVariableController.text.trim();
    final valid = variable.isNotEmpty;
    return _summaryBox(
      collection
          ? (valid ? 'Collection: $variable' : 'Collection is empty')
          : switch (_conditionMode) {
              'false' => 'Always false',
              'variable' => 'Truthy: ${valid ? variable : 'value'}',
              'equals' =>
                '${valid ? variable : 'value'} == ${_conditionCompareController.text}',
              _ => 'Always true',
            },
      valid ||
          (!collection && _conditionMode == 'true' ||
              _conditionMode == 'false'),
    );
  }

  Widget _switchExpressionSummary() {
    final variable = _switchExpressionController.text.trim();
    return _summaryBox(
      variable.isEmpty ? 'Switch variable is empty' : 'Switch: $variable',
      variable.isNotEmpty,
    );
  }

  Widget _summaryBox(String text, bool valid) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xff101010),
      border: Border.all(
        color: valid ? const Color(0xff365b4a) : const Color(0xff9f4545),
      ),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Text(
        text,
        style: TextStyle(
          color: valid ? const Color(0xffb8eaff) : const Color(0xffffb4b4),
          fontFamily: 'monospace',
          fontSize: 12,
        ),
      ),
    ),
  );

  Widget _switchCases() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('Cases', style: TextStyle(fontWeight: FontWeight.w700)),
      for (var index = 0; index < _cases.length; index++) ...[
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _caseControllers[index],
                onChanged: (value) => _cases[index]['value'] = value,
                decoration: const InputDecoration(
                  labelText: 'Case value',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Delete case',
              onPressed: () => setState(() {
                _caseControllers.removeAt(index).dispose();
                _cases.removeAt(index);
              }),
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
      ],
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: () => setState(() {
            final index = _cases.length;
            _cases.add({'value': 'case${index + 1}', 'port': 'case:$index'});
            _caseControllers.add(
              TextEditingController(text: 'case${index + 1}'),
            );
          }),
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Add case'),
        ),
      ),
    ],
  );

  Widget _textField({
    required TextEditingController controller,
    required String label,
    String? hint,
    TextInputType? keyboardType,
  }) => TextField(
    controller: controller,
    autofocus: label == 'Condition',
    keyboardType: keyboardType,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      border: const OutlineInputBorder(),
    ),
  );

  JsonMap _result() {
    switch (widget.nodeType) {
      case 'if':
        return {'condition': _conditionExpression()};
      case 'while':
        return {
          'condition': _conditionExpression(),
          'maxIterations': _number(_maxIterationsController.text, 1000).toInt(),
        };
      case 'for':
        return {
          'variable': _counterController.text.trim().isEmpty
              ? 'i'
              : _counterController.text.trim(),
          'start': _literal(_number(_startController.text, 0)),
          'end': _literal(_number(_endController.text, 10)),
          'step': _literal(_number(_stepController.text, 1)),
        };
      case 'forEach':
        return {
          'variable': _counterController.text.trim().isEmpty
              ? 'item'
              : _counterController.text.trim(),
          'collection': _variableExpression(
            _collectionController.text,
            'items',
          ),
        };
      case 'switch':
        return {
          'expression': _variableExpression(
            _switchExpressionController.text,
            'value',
          ),
          'cases': _cases,
        };
      default:
        return {};
    }
  }

  Map<String, dynamic> _conditionExpression() {
    final variable = _conditionVariableController.text.trim();
    switch (_conditionMode) {
      case 'false':
        return {'type': 'literal', 'value': false};
      case 'variable':
        return _variableExpression(variable, 'value');
      case 'equals':
        return {
          'type': 'binary',
          'op': '==',
          'left': _variableExpression(variable, 'value'),
          'right': {
            'type': 'literal',
            'value': _conditionCompareController.text,
          },
        };
      default:
        return {'type': 'literal', 'value': true};
    }
  }

  static Map<String, dynamic> _variableExpression(
    String value,
    String fallback,
  ) => {
    'type': 'variable',
    'name': value.trim().isEmpty ? fallback : value.trim(),
  };

  static Map<String, dynamic> _literal(num value) => {
    'type': 'literal',
    'value': value,
  };

  static double _number(String value, num fallback) =>
      double.tryParse(value.trim()) ?? fallback.toDouble();

  static String _expressionMode(dynamic expression) {
    if (expression is! Map) return 'true';
    if (expression['type'] == 'literal' && expression['value'] == false) {
      return 'false';
    }
    if (expression['type'] == 'binary' && expression['op'] == '==') {
      return 'equals';
    }
    if (expression['type'] == 'variable') return 'variable';
    return 'true';
  }

  static String _expressionVariable(dynamic expression) {
    if (expression is! Map) return '';
    if (expression['type'] == 'variable') {
      return expression['name']?.toString() ?? '';
    }
    if (expression['type'] == 'binary' && expression['left'] is Map) {
      return _expressionVariable(expression['left']);
    }
    return '';
  }

  static String _expressionCompareValue(dynamic expression) {
    if (expression is Map && expression['right'] is Map) {
      return expression['right']['value']?.toString() ?? '';
    }
    return '';
  }

  static double _literalNumber(dynamic expression, [num fallback = 0]) {
    if (expression is Map && expression['type'] == 'literal') {
      return _number(expression['value']?.toString() ?? '', fallback);
    }
    return fallback.toDouble();
  }
}

DartActionDefinition? _actionDefinition(
  ShowRunnerGraphEditor editor,
  DartPluginRegistry registry,
  NodeDataModel node,
) {
  final nodeData = editor.nodeData(node.id);
  final plugin = nodeData['plugin'];
  final action = nodeData['action'];
  if (plugin is String && action is String) {
    return registry.findAction(plugin, action);
  }
  final parts = node.prototype.idName.split('.');
  if (parts.length != 2 || parts.first == 'trigger') return null;
  return registry.findAction(parts.first, parts.last);
}

DartTriggerDefinition? _triggerDefinition(
  ShowRunnerGraphEditor editor,
  DartPluginRegistry registry,
  NodeDataModel node,
) {
  final data = editor.nodeData(node.id);
  final plugin = data['plugin']?.toString();
  final trigger = data['trigger']?.toString();
  if (plugin != null && trigger != null) {
    return registry.findTrigger(plugin, trigger);
  }
  final parts = node.prototype.idName.split('.');
  if (parts.length < 3 || parts.first != 'trigger') return null;
  return registry.findTrigger(parts[1], parts.sublist(2).join('.'));
}

DartDataInputSchema? _triggerConfigurationSchema(
  DartTriggerDefinition? definition,
  JsonMap config,
) {
  final declared = definition?.configSchema;
  if (declared != null && (declared.fields.isNotEmpty || config.isEmpty)) {
    return declared;
  }
  if (config.isEmpty) return null;
  return DartDataInputSchema(
    label: 'Settings',
    kind: DartDataInputKind.object,
    fields: [
      for (final entry in config.entries)
        _inferredTriggerField(entry.key, entry.value),
    ],
  );
}

DartDataInputSchema _inferredTriggerField(String key, dynamic value) {
  if (value is Map) {
    return DartDataInputSchema(
      label: key,
      key: key,
      kind: DartDataInputKind.object,
      fields: [
        for (final entry in value.entries)
          _inferredTriggerField(entry.key.toString(), entry.value),
      ],
    );
  }
  return DartDataInputSchema(
    label: key,
    key: key,
    kind: switch (value) {
      bool _ => DartDataInputKind.boolean,
      num _ => DartDataInputKind.number,
      List _ => DartDataInputKind.array,
      _ => DartDataInputKind.text,
    },
  );
}

DartDataInputSchema? _configurationSchema(
  ShowRunnerGraphEditor editor,
  DartPluginRegistry registry,
  NodeDataModel node,
) {
  final actionDefinition = _actionDefinition(editor, registry, node);
  if (actionDefinition != null) return actionDefinition.configSchema;
  final parts = node.prototype.idName.split('.');
  if (parts.length >= 3 && parts.first == 'trigger') {
    return registry
        .findTrigger(parts[1], parts.sublist(2).join('.'))
        ?.configSchema;
  }
  if (parts.length != 2) return null;
  return registry.findAction(parts.first, parts.last)?.configSchema;
}

Future<void> _editActionResultMapping(
  BuildContext context,
  ShowRunnerGraphEditor editor,
  NodeDataModel node,
  DartDataInputSchema? schema,
) async {
  if (schema?.kind != DartDataInputKind.object || schema!.fields.isEmpty) {
    return;
  }
  final mapping = await showDialog<JsonMap>(
    context: context,
    builder: (context) => _ActionResultMappingDialog(
      title: 'Map ${editor.nodeTitle(node.id)} returns',
      schema: schema,
      initialValue: editor.nodeResultMapping(node.id),
    ),
  );
  if (mapping != null) editor.updateNodeResultMapping(node.id, mapping);
}

class _ActionResultMappingDialog extends StatefulWidget {
  const _ActionResultMappingDialog({
    required this.title,
    required this.schema,
    required this.initialValue,
  });

  final String title;
  final DartDataInputSchema schema;
  final JsonMap initialValue;

  @override
  State<_ActionResultMappingDialog> createState() =>
      _ActionResultMappingDialogState();
}

class _ActionResultMappingDialogState
    extends State<_ActionResultMappingDialog> {
  late final Map<String, TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = {
      for (final field in widget.schema.fields)
        (field.key ?? field.label): TextEditingController(
          text: widget.initialValue[field.key ?? field.label]?.toString() ?? '',
        ),
    };
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  JsonMap _mapping() => {
    for (final entry in _controllers.entries)
      if (entry.value.text.trim().isNotEmpty)
        entry.key: entry.value.text.trim(),
  };

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final field in widget.schema.fields)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TextField(
                  controller: _controllers[field.key ?? field.label],
                  decoration: InputDecoration(
                    labelText: field.label,
                    hintText: field.key ?? field.label,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(_mapping()),
        child: const Text('Apply'),
      ),
    ],
  );
}

class _SchemaConfigurationDialog extends StatefulWidget {
  const _SchemaConfigurationDialog({
    required this.title,
    required this.schema,
    required this.initialValue,
  });

  final String title;
  final DartDataInputSchema schema;
  final Map<String, dynamic> initialValue;

  @override
  State<_SchemaConfigurationDialog> createState() =>
      _SchemaConfigurationDialogState();
}

final class _TriggerConfigurationResult {
  const _TriggerConfigurationResult({required this.config, required this.stop});

  final JsonMap config;
  final bool stop;
}

class _TriggerConfigurationDialog extends StatefulWidget {
  const _TriggerConfigurationDialog({
    required this.title,
    required this.schema,
    required this.initialValue,
    required this.stop,
  });

  final String title;
  final DartDataInputSchema? schema;
  final JsonMap initialValue;
  final bool stop;

  @override
  State<_TriggerConfigurationDialog> createState() =>
      _TriggerConfigurationDialogState();
}

class _TriggerConfigurationDialogState
    extends State<_TriggerConfigurationDialog> {
  late Map<String, dynamic> _value;
  late bool _stop;

  @override
  void initState() {
    super.initState();
    _value = Map<String, dynamic>.from(widget.initialValue);
    _stop = widget.stop;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.schema != null && widget.schema!.fields.isNotEmpty)
              DartDataInput(
                schema: widget.schema!,
                value: _value,
                onChanged: (value) {
                  if (value is Map) {
                    setState(() => _value = Map<String, dynamic>.from(value));
                  }
                },
              )
            else
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('No trigger settings'),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Stop subsequent triggers'),
              value: _stop,
              onChanged: (value) => setState(() => _stop = value),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(
          context,
        ).pop(_TriggerConfigurationResult(config: _value, stop: _stop)),
        child: const Text('Apply'),
      ),
    ],
  );
}

class _SchemaConfigurationDialogState
    extends State<_SchemaConfigurationDialog> {
  late Map<String, dynamic> _value;

  @override
  void initState() {
    super.initState();
    _value = Map<String, dynamic>.from(widget.initialValue);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: DartDataInput(
          schema: widget.schema,
          value: _value,
          onChanged: (value) {
            if (value is Map) {
              setState(() => _value = Map<String, dynamic>.from(value));
            }
          },
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(_value),
        child: const Text('Apply'),
      ),
    ],
  );
}

// sai_nodes supplies the canvas viewport; this minimap renders ShowRunner
// frames, execution state, and persisted graph links in a compact projection.
class _GraphMinimap extends StatelessWidget {
  const _GraphMinimap({required this.editor});

  final ShowRunnerGraphEditor editor;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([
      editor.controller,
      editor.frames,
      editor.executionStates,
    ]),
    builder: (context, child) {
      final nodes = editor.controller.nodes.values.toList();
      final editorRenderObject = editor.controller.editorKey.currentContext
          ?.findRenderObject();
      final viewportSize =
          editorRenderObject is RenderBox && editorRenderObject.hasSize
          ? editorRenderObject.size
          : Size.zero;
      final painter = _GraphMinimapPainter(
        nodes,
        links: editor.controller.linksAsList,
        frames: editor.frames.value,
        executionStates: editor.executionStates.value,
        viewportOffset: editor.controller.viewportOffset,
        viewportZoom: editor.controller.viewportZoom,
        viewportSize: viewportSize,
      );
      return DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xff182126).withValues(alpha: 0.94),
          border: Border.all(color: const Color(0xff475569)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) => _moveViewportToMinimapPosition(
            editor,
            painter,
            details.localPosition,
          ),
          onPanUpdate: (details) => _moveViewportToMinimapPosition(
            editor,
            painter,
            details.localPosition,
          ),
          child: SizedBox(
            width: 180,
            height: 120,
            child: CustomPaint(painter: painter),
          ),
        ),
      );
    },
  );
}

class _GraphMinimapPainter extends CustomPainter {
  const _GraphMinimapPainter(
    this.nodes, {
    required this.links,
    required this.frames,
    required this.executionStates,
    required this.viewportOffset,
    required this.viewportZoom,
    required this.viewportSize,
  });

  final List<NodeDataModel> nodes;
  final List<LinkDataModel> links;
  final List<GraphFrame> frames;
  final Map<String, GraphNodeExecutionVisual> executionStates;
  final Offset viewportOffset;
  final double viewportZoom;
  final Size viewportSize;

  ({double minX, double minY, double scale})? get _metrics {
    if (nodes.isEmpty) return null;
    final minX = nodes
        .map((node) => node.offset.dx)
        .reduce((a, b) => a < b ? a : b);
    final minY = nodes
        .map((node) => node.offset.dy)
        .reduce((a, b) => a < b ? a : b);
    final maxX = nodes
        .map((node) => node.offset.dx + 180)
        .reduce((a, b) => a > b ? a : b);
    final maxY = nodes
        .map((node) => node.offset.dy + 90)
        .reduce((a, b) => a > b ? a : b);
    return (
      minX: minX,
      minY: minY,
      scale: math.min(180 / (maxX - minX + 40), 120 / (maxY - minY + 40)),
    );
  }

  Offset? worldPositionFor(Offset localPosition) {
    final metrics = _metrics;
    if (metrics == null) return null;
    return Offset(
      metrics.minX + (localPosition.dx - 20) / metrics.scale,
      metrics.minY + (localPosition.dy - 20) / metrics.scale,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final metrics = _metrics;
    if (metrics == null) return;
    final paint = Paint()..style = PaintingStyle.fill;
    final framePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xfff472b6);
    for (final frame in frames) {
      canvas.drawRect(_toMiniRect(frame.bounds, metrics), framePaint);
    }
    final linkPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final link in links) {
      final source = nodes
          .where((node) => node.id == link.endpoints.sourceNodeId)
          .firstOrNull;
      final target = nodes
          .where((node) => node.id == link.endpoints.targetNodeId)
          .firstOrNull;
      if (source == null || target == null) continue;
      linkPaint.color = _minimapColor(
        source.prototype.idName,
        executionStates[source.id]?.status,
      ).withValues(alpha: 0.7);
      final sourcePoint = _toMiniPoint(
        source.offset + const Offset(140, 28),
        metrics,
      );
      final targetPoint = _toMiniPoint(
        target.offset + const Offset(0, 28),
        metrics,
      );
      canvas.drawLine(sourcePoint, targetPoint, linkPaint);
    }
    for (final node in nodes) {
      paint.color = _minimapColor(
        node.prototype.idName,
        executionStates[node.id]?.status,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            20 + (node.offset.dx - metrics.minX) * metrics.scale,
            20 + (node.offset.dy - metrics.minY) * metrics.scale,
            140 * metrics.scale,
            55 * metrics.scale,
          ),
          const Radius.circular(2),
        ),
        paint,
      );
    }
    final viewportWorld = Rect.fromLTWH(
      -viewportSize.width / (2 * viewportZoom) - viewportOffset.dx,
      -viewportSize.height / (2 * viewportZoom) - viewportOffset.dy,
      viewportSize.width / viewportZoom,
      viewportSize.height / viewportZoom,
    );
    final viewportPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white;
    canvas.drawRect(_toMiniRect(viewportWorld, metrics), viewportPaint);
  }

  Rect _toMiniRect(
    Rect rect,
    ({double minX, double minY, double scale}) metrics,
  ) => Rect.fromLTRB(
    20 + (rect.left - metrics.minX) * metrics.scale,
    20 + (rect.top - metrics.minY) * metrics.scale,
    20 + (rect.right - metrics.minX) * metrics.scale,
    20 + (rect.bottom - metrics.minY) * metrics.scale,
  );

  Offset _toMiniPoint(
    Offset point,
    ({double minX, double minY, double scale}) metrics,
  ) => Offset(
    20 + (point.dx - metrics.minX) * metrics.scale,
    20 + (point.dy - metrics.minY) * metrics.scale,
  );

  @override
  bool shouldRepaint(_GraphMinimapPainter oldDelegate) =>
      oldDelegate.nodes != nodes ||
      oldDelegate.links != links ||
      oldDelegate.frames != frames ||
      oldDelegate.executionStates != executionStates ||
      oldDelegate.viewportOffset != viewportOffset ||
      oldDelegate.viewportZoom != viewportZoom ||
      oldDelegate.viewportSize != viewportSize;
}

Color _minimapColor(String idName, GraphNodeExecutionStatus? status) =>
    switch (status) {
      GraphNodeExecutionStatus.running => const Color(0xff38bdf8),
      GraphNodeExecutionStatus.success => const Color(0xff4ade80),
      GraphNodeExecutionStatus.error => const Color(0xfff87171),
      null => _nodeTypeMinimapColor(idName),
    };

Color _nodeTypeMinimapColor(String idName) => switch (idName) {
  'trigger.chatMessage' => const Color(0xff60a5fa),
  'queue.addItem' => const Color(0xfff59e0b),
  'overlay.pushChat' => const Color(0xff34d399),
  _ => const Color(0xff94a3b8),
};

void _moveViewportToMinimapPosition(
  ShowRunnerGraphEditor editor,
  _GraphMinimapPainter painter,
  Offset localPosition,
) {
  final worldPosition = painter.worldPositionFor(localPosition);
  if (worldPosition == null) return;
  editor.controller.setViewportOffset(-worldPosition, absolute: true);
}
