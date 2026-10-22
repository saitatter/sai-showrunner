import 'package:flutter/material.dart';

/// Owns presentation-only split position; authoring and selection stay upstream.
class OverlayEditorSidebar extends StatefulWidget {
  const OverlayEditorSidebar({
    super.key,
    required this.inspector,
    required this.layers,
  });
  final Widget inspector, layers;
  @override
  State<OverlayEditorSidebar> createState() => _OverlayEditorSidebarState();
}

class _OverlayEditorSidebarState extends State<OverlayEditorSidebar> {
  int _inspectorFlex = 55;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(
        flex: _inspectorFlex,
        child: KeyedSubtree(
          key: const ValueKey('overlay-widget-inspector-pane'),
          child: Material(
            color: const Color(0xff202020),
            child: widget.inspector,
          ),
        ),
      ),
      MouseRegion(
        cursor: SystemMouseCursors.resizeUpDown,
        child: GestureDetector(
          key: const ValueKey('overlay-inspector-splitter'),
          behavior: HitTestBehavior.opaque,
          onVerticalDragUpdate: (details) => setState(() {
            _inspectorFlex = (_inspectorFlex + (details.delta.dy / 8).round())
                .clamp(25, 75);
          }),
          child: SizedBox(
            height: 7,
            child: Center(
              child: Divider(
                height: 1,
                thickness: 1,
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
          ),
        ),
      ),
      Expanded(
        flex: 100 - _inspectorFlex,
        child: KeyedSubtree(
          key: const ValueKey('overlay-widget-list-pane'),
          child: widget.layers,
        ),
      ),
    ],
  );
}
