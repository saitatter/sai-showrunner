import 'package:flutter/material.dart';
import '../../../../design_system/editor_layout_policy.dart';
import 'overlay_editor_sidebar.dart';

/// Stable canvas/sidebar subtrees preserve input and split state across resizing.
class OverlayEditorLayout extends StatefulWidget {
  const OverlayEditorLayout({
    super.key,
    required this.toolbar,
    required this.canvas,
    required this.inspector,
    required this.layers,
    required this.status,
    required this.saving,
    required this.onSave,
    required this.onReturnToCanvas,
  });
  final Widget toolbar, canvas, inspector, layers;
  final String status;
  final bool saving;
  final VoidCallback onSave, onReturnToCanvas;
  @override
  State<OverlayEditorLayout> createState() => OverlayEditorLayoutState();
}

class OverlayEditorLayoutState extends State<OverlayEditorLayout> {
  bool? _panelOverride;
  bool _compact = false;
  bool get _panelOpen => _panelOverride ?? !_compact;
  void toggleInspector() {
    setState(() => _panelOverride = !_panelOpen);
    if (!_panelOpen) widget.onReturnToCanvas();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final policy = EditorLayoutPolicy.forViewport(
        constraints.maxWidth,
        constraints.maxHeight,
      );
      _compact = policy.compact;
      final panelOpen = _panelOpen;
      return Column(
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: policy.toolbarMaxHeight),
            child: SingleChildScrollView(child: widget.toolbar),
          ),
          const Divider(height: 1),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  key: const ValueKey('overlay-canvas-region'),
                  right: !policy.compact && panelOpen
                      ? policy.sidebarWidth + 1
                      : 0,
                  child: ExcludeFocus(
                    excluding: policy.compact && panelOpen,
                    child: widget.canvas,
                  ),
                ),
                if (policy.compact && panelOpen)
                  Positioned.fill(
                    key: const ValueKey('overlay-sidebar-barrier'),
                    child: GestureDetector(
                      key: const ValueKey('overlay-sidebar-dismiss'),
                      behavior: HitTestBehavior.opaque,
                      onTap: toggleInspector,
                      child: ColoredBox(
                        color: Colors.black.withValues(alpha: .25),
                      ),
                    ),
                  ),
                Positioned(
                  key: const ValueKey('overlay-sidebar-divider-region'),
                  right: policy.sidebarWidth,
                  top: 0,
                  bottom: 0,
                  width: 1,
                  child: Offstage(
                    offstage: policy.compact || !panelOpen,
                    child: const VerticalDivider(width: 1),
                  ),
                ),
                Positioned(
                  key: const ValueKey('overlay-sidebar-region'),
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: policy.sidebarWidth,
                  child: Offstage(
                    offstage: !panelOpen,
                    child: ExcludeFocus(
                      excluding: !panelOpen,
                      child: SizedBox(
                        key: const ValueKey('overlay-widget-sidebar'),
                        width: policy.sidebarWidth,
                        child: OverlayEditorSidebar(
                          inspector: widget.inspector,
                          layers: widget.layers,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(
              children: [
                if (policy.compact || !panelOpen)
                  IconButton(
                    key: const ValueKey('overlay-toggle-inspector'),
                    tooltip: 'Inspector and layers (Ctrl+I)',
                    isSelected: panelOpen,
                    icon: const Icon(Icons.view_sidebar_outlined),
                    onPressed: toggleInspector,
                  ),
                Expanded(
                  child: Text(
                    widget.status,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                FilledButton(
                  key: const ValueKey('overlay-save'),
                  onPressed: widget.saving ? null : widget.onSave,
                  child: Text(widget.saving ? 'Saving\u2026' : 'Save'),
                ),
              ],
            ),
          ),
        ],
      );
    },
  );
}
