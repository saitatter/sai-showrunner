import 'package:flutter/material.dart';
import 'package:sai_nodes/sai_nodes.dart' show ConnectionRouting;
import '../controller/automation_editor_controller.dart';
import '../domain/automation_document.dart';

class AutomationGraphToolbar extends StatelessWidget {
  const AutomationGraphToolbar({
    super.key,
    required this.editor,
    required this.snapping,
    required this.routing,
    required this.inspector,
    required this.running,
    required this.onAdd,
    required this.onFit,
    required this.onFind,
    required this.onToggleSnapping,
    required this.onRoutingChanged,
    required this.onToggleInspector,
    this.onRun,
  });
  final AutomationEditorController editor;
  final bool snapping, inspector, running;
  final ConnectionRouting routing;
  final VoidCallback onAdd, onFit, onFind, onToggleSnapping, onToggleInspector;
  final ValueChanged<ConnectionRouting> onRoutingChanged;
  final VoidCallback? onRun;
  @override
  Widget build(BuildContext context) {
    final graph = editor.graph;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        children: [
          TextButton.icon(
            key: const ValueKey('graph-add-node'),
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Add node'),
          ),
          IconButton(
            tooltip: 'Undo',
            onPressed: graph.canUndo ? graph.undo : null,
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            tooltip: 'Redo',
            onPressed: graph.canRedo ? graph.redo : null,
            icon: const Icon(Icons.redo),
          ),
          IconButton(
            tooltip: 'Fit graph',
            onPressed: onFit,
            icon: const Icon(Icons.fit_screen),
          ),
          IconButton(
            tooltip: 'Find in graph',
            onPressed: onFind,
            icon: const Icon(Icons.search),
          ),
          IconButton(
            tooltip: 'Snap to grid',
            isSelected: snapping,
            onPressed: onToggleSnapping,
            icon: const Icon(Icons.grid_4x4),
          ),
          DropdownButton<ConnectionRouting>(
            value: routing,
            underline: const SizedBox.shrink(),
            items: [
              for (final value in ConnectionRouting.values)
                DropdownMenuItem(value: value, child: Text(value.name)),
            ],
            onChanged: (value) {
              if (value != null) onRoutingChanged(value);
            },
          ),
          DropdownButton<String>(
            key: const ValueKey('graph-space'),
            value: graph.activeSpaceId,
            underline: const SizedBox.shrink(),
            items: [
              const DropdownMenuItem(
                value: mainAutomationSpace,
                child: Text('Main graph'),
              ),
              for (final signature in editor.document.subgraphs.values)
                DropdownMenuItem(
                  value: signature.spaceId,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 200),
                    child: Tooltip(
                      message: signature.name,
                      child: Text(
                        signature.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
            ],
            onChanged: (value) {
              if (value != null) graph.setActiveSpace(value);
            },
          ),
          IconButton(
            tooltip: 'New subgraph',
            onPressed: () => editor.createSubgraph(),
            icon: const Icon(Icons.account_tree_outlined),
          ),
          IconButton(
            tooltip: 'Inspector',
            isSelected: inspector,
            onPressed: onToggleInspector,
            icon: const Icon(Icons.tune),
          ),
          TextButton.icon(
            onPressed:
                onRun != null &&
                    !running &&
                    graph.resolution.diagnostics.isEmpty
                ? onRun
                : null,
            icon: Icon(running ? Icons.hourglass_empty : Icons.play_arrow),
            label: const Text('Run'),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(editor.isDirty ? 'Unsaved changes' : 'Saved'),
          ),
          if (graph.resolution.diagnostics.isEmpty)
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text(
                'Graph healthy',
                style: TextStyle(color: Color(0xff69c8a3)),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              '${graph.activeSpace?.nodes.length ?? 0} nodes · ${graph.activeSpace?.connections.length ?? 0} connections',
            ),
          ),
        ],
      ),
    );
  }
}
