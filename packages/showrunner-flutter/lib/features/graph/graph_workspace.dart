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
import 'graph_execution_panel.dart';

part 'graph_node_configuration_dialogs.dart';
part 'graph_minimap.dart';
part 'graph_inspector.dart';
part 'graph_visual_overlays.dart';
part 'graph_node_insertion.dart';
part 'graph_node_rendering.dart';
part 'graph_health.dart';

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
      GraphExecutionPanel(editor: editor),
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
