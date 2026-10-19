import 'dart:async';
import 'package:flutter/material.dart';
import '../../app/startup_health.dart';
import '../../components/data_inputs/resource_schema.dart';
import '../controller/automation_document_sessions.dart';
import '../controller/automation_editor_controller.dart';
import '../execution/showrunner_execution_visual_adapter.dart';
import 'automation_graph_workspace.dart';

class AutomationResourceWorkspace extends StatelessWidget {
  const AutomationResourceWorkspace({
    super.key,
    required this.editor,
    this.documents,
    this.onSelected,
    this.onClosed,
    this.onReordered,
    this.healthFuture,
    this.execution,
    this.canvasKey,
    this.onRun,
    this.onRunNode,
    this.resourceOptionsLoader,
  });
  final AutomationEditorController editor;
  final AutomationDocumentSessions? documents;
  final ValueChanged<String>? onSelected;
  final FutureOr<void> Function(String fileName)? onClosed;
  final void Function(int oldPosition, int newPosition)? onReordered;
  final Future<StartupHealthSnapshot>? healthFuture;
  final ShowrunnerExecutionVisualAdapter? execution;
  final GlobalKey<AutomationGraphWorkspaceState>? canvasKey;
  final Future<void> Function()? onRun;
  final Future<void> Function(String nodeId)? onRunNode;
  final ResourceOptionsLoader? resourceOptionsLoader;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (documents?.hasDocuments == true)
        SizedBox(
          height: 40,
          child: ReorderableListView(
            scrollDirection: Axis.horizontal,
            buildDefaultDragHandles: false,
            onReorderItem: (oldPosition, newPosition) =>
                onReordered?.call(oldPosition, newPosition),
            children: [
              for (final (index, session) in documents!.documents.indexed)
                ReorderableDragStartListener(
                  key: ValueKey(session.fileName),
                  index: index,
                  child: SizedBox(
                    width: 220,
                    child: Material(
                      color: session.fileName == documents!.activeFileName
                          ? Color.alphaBlend(
                              Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: .14),
                              Theme.of(context).colorScheme.surface,
                            )
                          : null,
                      child: Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () => onSelected?.call(session.fileName),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                child: Text(
                                  '${session.data.metadata['name'] ?? session.fileName}${session.dirty ? ' *' : ''}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Close ${session.fileName}',
                            onPressed: onClosed == null
                                ? null
                                : () => onClosed!(session.fileName),
                            icon: const Icon(Icons.close, size: 16),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      if (healthFuture != null)
        FutureBuilder<StartupHealthSnapshot>(
          future: healthFuture,
          builder: (context, snapshot) =>
              snapshot.data?.state == StartupHealthState.error
              ? ListTile(
                  dense: true,
                  title: Text(
                    'Storage is unavailable: ${snapshot.data?.error}',
                  ),
                )
              : const SizedBox.shrink(),
        ),
      Expanded(
        child: AutomationGraphWorkspace(
          key: canvasKey,
          editor: editor,
          execution: execution,
          resourceOptionsLoader: resourceOptionsLoader,
          onRunNode: onRunNode,
          onRun: onRun == null ? null : (_) => onRun!(),
        ),
      ),
    ],
  );
}
