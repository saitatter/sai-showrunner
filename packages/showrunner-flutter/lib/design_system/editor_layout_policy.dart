import 'dart:math' as math;

enum DesktopEditorSize { compact, standard, wide }

/// Uses the editor's actual logical constraints, after the app sidebar/tabs.
/// A compact inspector overlays rather than consuming the usable canvas width.
final class EditorLayoutPolicy {
  const EditorLayoutPolicy._(
    this.size,
    this.sidebarWidth,
    this.toolbarMaxHeight,
  );
  factory EditorLayoutPolicy.forViewport(double width, double height) {
    final compact = width < 900 || height < 560;
    return EditorLayoutPolicy._(
      compact
          ? DesktopEditorSize.compact
          : width >= 1440 && height >= 800
          ? DesktopEditorSize.wide
          : DesktopEditorSize.standard,
      math.min(352, width),
      compact ? height * .35 : double.infinity,
    );
  }
  final DesktopEditorSize size;
  final double sidebarWidth, toolbarMaxHeight;
  bool get compact => size == DesktopEditorSize.compact;
}
