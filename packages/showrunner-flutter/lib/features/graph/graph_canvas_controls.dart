import 'package:flutter/material.dart';
import 'package:sai_nodes/sai_nodes.dart';

import '../../editor/showrunner_graph_editor.dart';

/// Compact canvas toolbar matching main's graph controls. Graph mutations are
/// delegated to the generic controller; annotations and preview are owned by
/// the ShowRunner graph adapter.
class GraphCanvasControls extends StatelessWidget {
  const GraphCanvasControls({super.key, required this.editor});

  final ShowRunnerGraphEditor editor;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([
      editor.controller,
      editor.controller.viewportZoomNotifier,
      editor.previewNodeId,
      editor.previewPlaying,
      editor.previewElapsed,
      editor.nodeRevision,
    ]),
    builder: (context, child) {
      final controller = editor.controller;
      final selectionCount = controller.selectedNodeIds.length;
      final hasNodes = controller.nodes.isNotEmpty;
      final hasSelection = selectionCount > 0;
      final canUndo = controller.history.canUndo;
      final canRedo = controller.history.canRedo;
      final canAlign = selectionCount >= 2;
      final canDistribute = selectionCount >= 3;
      return Material(
        color: Colors.transparent,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _button(
                tooltip: 'Select all nodes',
                icon: Icons.select_all,
                onPressed: hasNodes ? controller.selectAllNodes : null,
              ),
              _button(
                tooltip: 'Fit graph',
                icon: Icons.fit_screen,
                onPressed: hasNodes
                    ? () => controller.focusAllNodes(animate: false)
                    : null,
              ),
              _button(
                tooltip: 'Fit to selection',
                icon: Icons.center_focus_strong,
                onPressed: hasSelection
                    ? () => controller.focusNodesById(
                        controller.selectedNodeIds,
                        animate: false,
                      )
                    : null,
              ),
              _button(
                tooltip: 'Reset view',
                icon: Icons.refresh,
                onPressed: () => controller.resetViewport(animate: false),
              ),
              _button(
                tooltip: 'Zoom out',
                icon: Icons.remove,
                onPressed: () =>
                    controller.setViewportZoom(-0.1, animate: false),
              ),
              SizedBox(
                width: 48,
                child: Text(
                  '${(controller.viewportZoom * 100).round()}%',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xffe9e9e9),
                    fontSize: 12,
                  ),
                ),
              ),
              _button(
                tooltip: 'Zoom in',
                icon: Icons.add,
                onPressed: () =>
                    controller.setViewportZoom(0.1, animate: false),
              ),
              _button(
                tooltip: controller.config.enableSnapToGrid
                    ? 'Disable snap to grid'
                    : 'Enable snap to grid',
                icon: Icons.grid_4x4,
                active: controller.config.enableSnapToGrid,
                onPressed: () => controller.enableSnapToGrid(
                  !controller.config.enableSnapToGrid,
                ),
              ),
              _button(
                tooltip: 'Auto-layout',
                icon: Icons.account_tree_outlined,
                onPressed: hasNodes ? editor.autoLayout : null,
              ),
              _button(
                tooltip: 'Align selected horizontally',
                icon: Icons.align_vertical_center,
                onPressed: canAlign
                    ? () => controller.alignSelectedNodes(
                        NodeAlignment.centerVertical,
                      )
                    : null,
              ),
              _button(
                tooltip: 'Align selected vertically',
                icon: Icons.align_horizontal_center,
                onPressed: canAlign
                    ? () => controller.alignSelectedNodes(
                        NodeAlignment.centerHorizontal,
                      )
                    : null,
              ),
              _button(
                tooltip: 'Distribute selected evenly',
                icon: Icons.space_bar,
                onPressed: canDistribute
                    ? () => controller.distributeSelectedNodes(
                        NodeDistributionAxis.horizontal,
                      )
                    : null,
              ),
              _button(
                tooltip: 'Add annotation block',
                icon: Icons.rectangle_outlined,
                onPressed: editor.frameSelection,
              ),
              _separator,
              _button(
                tooltip: editor.previewPlaying.value
                    ? 'Pause preview playhead'
                    : 'Play preview playhead',
                icon: editor.previewPlaying.value
                    ? Icons.pause
                    : Icons.play_arrow,
                active: editor.previewPlaying.value,
                onPressed: hasNodes ? editor.togglePreview : null,
              ),
              _button(
                tooltip: 'Reset preview playhead',
                icon: Icons.stop,
                onPressed: editor.resetPreview,
              ),
              _PreviewStatus(editor: editor),
              _separator,
              _button(
                tooltip: 'Undo',
                icon: Icons.undo,
                onPressed: canUndo ? controller.history.undo : null,
              ),
              _button(
                tooltip: 'Redo',
                icon: Icons.redo,
                onPressed: canRedo ? controller.history.redo : null,
              ),
              _button(
                tooltip: 'Delete selection',
                icon: Icons.delete_outline,
                onPressed: hasSelection || controller.selectedLinkIds.isNotEmpty
                    ? controller.deleteSelection
                    : null,
              ),
            ],
          ),
        ),
      );
    },
  );

  static Widget _button({
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
    bool active = false,
  }) => Builder(
    builder: (context) => IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon),
      style: IconButton.styleFrom(
        visualDensity: VisualDensity.compact,
        foregroundColor: active ? Theme.of(context).colorScheme.primary : null,
      ),
    ),
  );

  static const Widget _separator = Padding(
    padding: EdgeInsets.symmetric(horizontal: 5),
    child: SizedBox(
      width: 1,
      height: 22,
      child: ColoredBox(color: Color(0xff454545)),
    ),
  );
}

class _PreviewStatus extends StatelessWidget {
  const _PreviewStatus({required this.editor});

  final ShowRunnerGraphEditor editor;

  @override
  Widget build(BuildContext context) {
    final current = editor.controller.nodes[editor.previewNodeId.value];
    String format(Duration duration) =>
        '${(duration.inMilliseconds / 1000).toStringAsFixed(2)}s';
    return Container(
      constraints: const BoxConstraints(minWidth: 250, maxWidth: 330),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0x47000000),
        border: Border.all(color: const Color(0x1fffffff)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: editor.previewProgress,
                    minHeight: 6,
                    backgroundColor: const Color(0xff101010),
                    valueColor: const AlwaysStoppedAnimation(Color(0xffe9aaff)),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  current == null
                      ? 'Preview idle'
                      : current.displayTitle(context),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${format(editor.previewElapsed.value)} / ${format(editor.previewTotal)}',
            style: const TextStyle(color: Color(0xffd6d6d6), fontSize: 10),
          ),
        ],
      ),
    );
  }
}
