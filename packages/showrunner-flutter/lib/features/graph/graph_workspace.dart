import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:sai_nodes/sai_nodes.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_context_menu/flutter_context_menu.dart';

import '../../app/app_feedback.dart';
import '../../app/startup_health.dart';
import '../../app/automation_document_manager.dart';
import '../../components/data_inputs/data_input.dart';
import '../../editor/showrunner_graph_editor.dart';
import '../../editor/models/graph_editor_models.dart';
import '../../plugins/registry/plugin_registry.dart';
import '../../schema/automation.dart';
import '../../services/showrunner_data_service.dart';
import 'graph_canvas_controls.dart';
import 'graph_canvas_search.dart';

part 'graph_node_configuration_dialogs.dart';
part 'graph_minimap.dart';
part 'graph_inspector.dart';
part 'graph_visual_overlays.dart';
part 'graph_node_insertion.dart';

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
    this.automationDocuments,
    this.onAutomationSelected,
    this.onAutomationClosed,
    this.onAutomationReordered,
  });

  final ShowRunnerGraphEditor editor;
  final Future<StartupHealthSnapshot> healthFuture;
  final ShowRunnerDataService dataService;
  final Future<DartPluginRegistry> registryFuture;
  final Future<void> Function(String schemaNodeId)? onRunNode;
  final AutomationDocumentManager? automationDocuments;
  final ValueChanged<String>? onAutomationSelected;
  final FutureOr<void> Function(String fileName)? onAutomationClosed;
  final void Function(int oldPosition, int newPosition)? onAutomationReordered;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (automationDocuments != null && automationDocuments!.hasDocuments)
        _AutomationDocumentTabBar(
          documents: automationDocuments!.documents,
          activeFileName: automationDocuments!.activeFileName,
          onSelected: onAutomationSelected ?? (_) {},
          onClosed: onAutomationClosed ?? (_) {},
          onReordered: onAutomationReordered ?? (_, _) {},
        ),
      if (_documentTitle != null) _GraphDocumentHeader(title: _documentTitle!),
      _StartupHealthBanner(healthFuture: healthFuture),
      _GraphNodePalette(editor: editor, registryFuture: registryFuture),
      Expanded(
        child: ValueListenableBuilder<List<String>>(
          valueListenable: editor.activeGraphPath,
          builder: (context, path, child) => Column(
            children: [
              if (path.isNotEmpty) _GraphBreadcrumb(editor: editor),
              Align(
                alignment: Alignment.centerLeft,
                child: GraphCanvasControls(editor: editor),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: const Color(0xffb86cff),
                        width: 1.5,
                      ),
                    ),
                    child: ClipRect(
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
                              onDuplicate: () =>
                                  editor.duplicateSelectedAction(),
                              onDeleteSelection: editor.deleteSelection,
                              onMoveSelection:
                                  (key, {required extendSelection}) =>
                                      editor.moveSelection(
                                        key,
                                        extendSelection: extendSelection,
                                      ),
                              onSearch: editor.openCanvasSearch,
                              child: _GraphActionDropTarget(
                                editor: editor,
                                registryFuture: registryFuture,
                                child: NodeEditorWidget(
                                  controller: editor.controller,
                                  expandToParent: true,
                                  overlay: () => [
                                    OverlayData(
                                      top: 0,
                                      left: 0,
                                      right: 0,
                                      bottom: 0,
                                      child: _GraphFramesOverlay(
                                        editor: editor,
                                      ),
                                    ),
                                    OverlayData(
                                      top: 0,
                                      left: 0,
                                      right: 0,
                                      bottom: 0,
                                      child: _GraphDropTargetOverlay(
                                        editor: editor,
                                      ),
                                    ),
                                    OverlayData(
                                      top: 0,
                                      left: 0,
                                      right: 0,
                                      bottom: 0,
                                      child: _GraphAlignmentGuidesOverlay(
                                        editor: editor,
                                      ),
                                    ),
                                    OverlayData(
                                      top: 0,
                                      left: 0,
                                      right: 0,
                                      bottom: 0,
                                      child: _ExecutionLinkOverlay(
                                        editor: editor,
                                      ),
                                    ),
                                    OverlayData(
                                      top: 0,
                                      left: 0,
                                      right: 0,
                                      bottom: 0,
                                      child: _InvalidLinkOverlay(
                                        editor: editor,
                                      ),
                                    ),
                                    OverlayData(
                                      top: 12,
                                      right: 12,
                                      child: GraphCanvasSearch(editor: editor),
                                    ),
                                    OverlayData(
                                      top: 16,
                                      left: 16,
                                      child: _GraphStatus(editor: editor),
                                    ),
                                    OverlayData(
                                      top: 60,
                                      left: 16,
                                      right: 16,
                                      child: _GraphWireHealthOverlay(
                                        editor: editor,
                                      ),
                                    ),
                                    OverlayData(
                                      bottom: 16,
                                      left: 16,
                                      child: _GraphHealth(editor: editor),
                                    ),
                                    OverlayData(
                                      top: 68,
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
                                      (
                                        context,
                                        node,
                                        style,
                                        onToggleCollapse,
                                      ) => _buildNodeHeader(
                                        context,
                                        node,
                                        style,
                                        onToggleCollapse,
                                        editor: editor,
                                        onRunNode: onRunNode,
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
                                  nodeEditorMenuBuilder: (context, position) =>
                                      _canvasNodeEditorContextMenu(
                                        context: context,
                                        editor: editor,
                                        position: position,
                                        registryFuture: registryFuture,
                                        registry: registrySnapshot.data,
                                      ),
                                  onNodeDoubleTap: (context, node) =>
                                      _handleNodeDoubleTap(
                                        context,
                                        editor,
                                        node,
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

  String? get _documentTitle {
    final session = automationDocuments?.active;
    if (session == null) return null;
    final configured = session.data.extra['name']?.toString().trim();
    if (configured != null && configured.isNotEmpty) {
      return _displayDocumentTitle(configured);
    }
    final fileName = session.fileName.trim();
    if (fileName.isEmpty) return null;
    final withoutExtension = fileName.replaceFirst(RegExp(r'\.[^.]+$'), '');
    return _displayDocumentTitle(withoutExtension);
  }
}

class _GraphDocumentHeader extends StatelessWidget {
  const _GraphDocumentHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'AUTOMATION FLOW',
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.7,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

String _normalizeDocumentTitle(String value) => value.replaceAll('->', '→');

String _displayDocumentTitle(String value) {
  if (!value.contains('->')) return _normalizeDocumentTitle(value);
  return value.replaceAll('->', String.fromCharCodes(const [0x2192]));
}

class _AutomationDocumentTabBar extends StatelessWidget {
  const _AutomationDocumentTabBar({
    required this.documents,
    required this.activeFileName,
    required this.onSelected,
    required this.onClosed,
    required this.onReordered,
  });

  final List<AutomationDocumentSession> documents;
  final String? activeFileName;
  final ValueChanged<String> onSelected;
  final FutureOr<void> Function(String fileName) onClosed;
  final void Function(int oldPosition, int newPosition) onReordered;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainer,
    child: SizedBox(
      height: 42,
      child: Align(
        alignment: Alignment.centerLeft,
        child: ReorderableListView.builder(
          scrollDirection: Axis.horizontal,
          shrinkWrap: true,
          primary: false,
          anchor: 0,
          buildDefaultDragHandles: false,
          padding: EdgeInsets.zero,
          itemCount: documents.length,
          onReorderItem: onReordered,
          itemBuilder: (context, position) {
            final document = documents[position];
            final selected = document.fileName == activeFileName;
            final title = document.data.extra['name']?.toString().trim();
            return ReorderableDragStartListener(
              key: ValueKey('automation-tab-${document.fileName}'),
              index: position,
              child: Material(
                color: selected
                    ? Theme.of(context).colorScheme.surfaceContainerHighest
                    : Theme.of(context).colorScheme.surfaceContainer,
                child: InkWell(
                  onTap: () => onSelected(document.fileName),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 12, right: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.bolt, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          '${title == null || title.isEmpty ? document.fileName : title}${document.dirty ? ' *' : ''}',
                        ),
                        IconButton(
                          tooltip: 'Close ${document.fileName}',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.close, size: 16),
                          onPressed: () => onClosed(document.fileName),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
}

/// A compact graph surface for inline automations such as profile activation
/// and stream-plan transitions.
///
/// It omits the application-level health and settings panels while retaining
/// the same canvas menus, toolbar, shortcuts, configuration dialogs, and
/// persisted-resource hydration as the full graph workspace.
class ShowRunnerInlineGraphEditor extends StatelessWidget {
  const ShowRunnerInlineGraphEditor({
    super.key,
    required this.editor,
    required this.registryFuture,
    this.height = 420,
  });

  final ShowRunnerGraphEditor editor;
  final Future<DartPluginRegistry> registryFuture;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: Column(
      children: [
        GraphCanvasControls(editor: editor),
        Expanded(
          child: FutureBuilder<DartPluginRegistry>(
            future: registryFuture,
            builder: (context, registrySnapshot) => NodeEditorShortcutsWidget(
              controller: editor.controller,
              onCopy: (context) => editor.copySelection(context: context),
              onPaste: (context) => editor.pasteSelection(context: context),
              onCut: (context) => editor.cutSelection(context: context),
              onDuplicate: () => editor.duplicateSelectedAction(),
              onDeleteSelection: editor.deleteSelection,
              onMoveSelection: (key, {required extendSelection}) =>
                  editor.moveSelection(key, extendSelection: extendSelection),
              onSearch: editor.openCanvasSearch,
              child: _GraphActionDropTarget(
                editor: editor,
                registryFuture: registryFuture,
                child: NodeEditorWidget(
                  controller: editor.controller,
                  expandToParent: true,
                  overlay: () => [
                    OverlayData(
                      top: 0,
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _GraphDropTargetOverlay(editor: editor),
                    ),
                    OverlayData(
                      top: 0,
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _GraphAlignmentGuidesOverlay(editor: editor),
                    ),
                    OverlayData(
                      top: 12,
                      right: 12,
                      child: GraphCanvasSearch(editor: editor),
                    ),
                    OverlayData(
                      top: 12,
                      left: 12,
                      right: 12,
                      child: _GraphWireHealthOverlay(editor: editor),
                    ),
                  ],
                  headerBuilder: (context, node, style, onToggleCollapse) =>
                      _buildNodeHeader(
                        context,
                        node,
                        style,
                        onToggleCollapse,
                        editor: editor,
                      ),
                  fieldBuilder: _buildNodeField,
                  portBuilder: _buildNodePort,
                  nodeMenuBuilder: (context, node) => _nodeEditorContextMenu(
                    context,
                    editor,
                    node,
                    registryFuture: registryFuture,
                  ),
                  nodeEditorMenuBuilder: (context, position) =>
                      _canvasNodeEditorContextMenu(
                        context: context,
                        editor: editor,
                        position: position,
                        registryFuture: registryFuture,
                        registry: registrySnapshot.data,
                      ),
                  onNodeDoubleTap: (context, node) =>
                      _handleNodeDoubleTap(context, editor, node),
                  editorContextMenuBuilder: (context, position, defaults) =>
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
        ),
      ],
    ),
  );
}

// Node insertion is ShowRunner-owned because plugin manifests and persisted
// node metadata are not generic graph-editor concerns.
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

class _GraphWireHealthOverlay extends StatelessWidget {
  const _GraphWireHealthOverlay({required this.editor});

  final ShowRunnerGraphEditor editor;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([
      editor.nodeRevision,
      editor.activeGraphPath,
      editor.selectedInvalidFlowEdgeId,
      editor.selectedInvalidDataWireId,
    ]),
    builder: (context, child) {
      final invalidDataWires = editor.invalidDataWires;
      final invalidFlowEdges = editor.invalidFlowEdges;
      if (invalidDataWires.isEmpty && invalidFlowEdges.isEmpty) {
        return const SizedBox.shrink();
      }

      return Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (invalidDataWires.isNotEmpty)
                _wireHealthBanner(
                  context,
                  title:
                      '${invalidDataWires.length} invalid data wire'
                      '${invalidDataWires.length == 1 ? '' : 's'}',
                  message:
                      'One or more data connections could not be restored.',
                  onSelect: () =>
                      editor.selectInvalidDataWire(invalidDataWires.first.id),
                  onCleanup: () {
                    for (final wire in List.of(invalidDataWires)) {
                      editor.discardInvalidDataWire(wire.id);
                    }
                  },
                ),
              if (invalidDataWires.isNotEmpty && invalidFlowEdges.isNotEmpty)
                const SizedBox(height: 6),
              if (invalidFlowEdges.isNotEmpty)
                _wireHealthBanner(
                  context,
                  title:
                      '${invalidFlowEdges.length} invalid sequence edge'
                      '${invalidFlowEdges.length == 1 ? '' : 's'}',
                  message:
                      'One or more execution connections could not be restored.',
                  onSelect: () =>
                      editor.selectInvalidFlowEdge(invalidFlowEdges.first.id),
                  onCleanup: () {
                    for (final edge in List.of(invalidFlowEdges)) {
                      editor.discardInvalidFlowEdge(edge.id);
                    }
                  },
                ),
            ],
          ),
        ),
      );
    },
  );

  Widget _wireHealthBanner(
    BuildContext context, {
    required String title,
    required String message,
    required VoidCallback onSelect,
    required VoidCallback onCleanup,
  }) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xff4c292b).withValues(alpha: 0.96),
      border: Border.all(color: const Color(0xff9f4d50)),
      borderRadius: BorderRadius.circular(6),
      boxShadow: const [
        BoxShadow(
          color: Color(0x33000000),
          blurRadius: 8,
          offset: Offset(0, 2),
        ),
      ],
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(Icons.warning_amber, color: Color(0xffffb4a9), size: 19),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xffffd7d2),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xffffc4be),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(onPressed: onSelect, child: const Text('Select')),
          TextButton(onPressed: onCleanup, child: const Text('Clean up')),
        ],
      ),
    ),
  );
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
                          onTap: () {
                            editor.selectInvalidFlowEdge(edge.id);
                            Navigator.of(context).pop();
                          },
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
                          onTap: () {
                            editor.selectInvalidDataWire(wire.id);
                            Navigator.of(context).pop();
                          },
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
